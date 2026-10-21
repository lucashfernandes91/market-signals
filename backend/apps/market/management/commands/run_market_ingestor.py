import asyncio
import logging
import os
import random

from asgiref.sync import sync_to_async
from channels.layers import get_channel_layer
from django.core.management.base import BaseCommand
from redis.exceptions import ConnectionError as RedisConnectionError
from redis.exceptions import TimeoutError as RedisTimeoutError

from apps.market.ingestion import ingest_quote
from apps.market.models import ProviderMarket
from apps.market.providers import MarketSubscription
from apps.market.providers.registry import get_configured_provider_code, get_market_provider
from infrastructure.redis.client import get_async_redis_client
from infrastructure.runtime import install_shutdown_handler

logger = logging.getLogger(__name__)


def subscription_reload_seconds() -> int:
    try:
        seconds = int(os.environ.get("MARKET_SUBSCRIPTION_RELOAD_SECONDS", "60"))
    except ValueError as exc:
        raise ValueError("MARKET_SUBSCRIPTION_RELOAD_SECONDS deve ser um inteiro.") from exc
    if seconds < 10:
        raise ValueError("MARKET_SUBSCRIPTION_RELOAD_SECONDS deve ser de pelo menos 10.")
    return seconds


def load_subscriptions(provider_name: str) -> list[MarketSubscription]:
    subscriptions = [
        MarketSubscription(
            market_id=market_id,
            symbol=canonical_symbol,
            provider_symbol=external_symbol,
            provider=provider_name,
            provider_market_id=provider_market_id,
        )
        for provider_market_id, market_id, canonical_symbol, external_symbol in (
            ProviderMarket.objects.filter(
                provider=provider_name,
                is_active=True,
                market__is_active=True,
            ).values_list("id", "market_id", "market__canonical_symbol", "external_symbol")
        )
    ]
    if subscriptions:
        return subscriptions
    return []


get_subscriptions = sync_to_async(load_subscriptions)


async def run_ingestor() -> None:
    install_shutdown_handler()
    provider_name = get_configured_provider_code()
    reload_seconds = subscription_reload_seconds()
    redis = get_async_redis_client()
    channel_layer = get_channel_layer()
    try:
        backoff = 1.0
        while True:
            subscriptions = await get_subscriptions(provider_name)
            if not subscriptions:
                logger.warning("market.no_active_subscriptions")
                await asyncio.sleep(reload_seconds)
                continue
            provider = get_market_provider(provider_name)
            try:
                await _ingest_subscription_cycle(
                    provider=provider,
                    subscriptions=subscriptions,
                    reload_seconds=reload_seconds,
                    redis=redis,
                    channel_layer=channel_layer,
                )
                backoff = 1.0
            except (RedisConnectionError, RedisTimeoutError):
                logger.exception("market.redis_unavailable")
                await asyncio.sleep(backoff + random.uniform(0, 0.5))
                backoff = min(backoff * 2, 30)
    finally:
        await redis.aclose()


async def _ingest_subscription_cycle(
    *,
    provider,
    subscriptions: list[MarketSubscription],
    reload_seconds: int,
    redis,
    channel_layer,
) -> None:
    stream = provider.stream_quotes(subscriptions)
    deadline = asyncio.get_running_loop().time() + reload_seconds
    try:
        while remaining := deadline - asyncio.get_running_loop().time():
            if remaining <= 0:
                return
            try:
                quote = await asyncio.wait_for(anext(stream), timeout=remaining)
            except TimeoutError:
                return
            await ingest_quote(quote=quote, redis=redis, channel_layer=channel_layer)
    finally:
        aclose = getattr(stream, "aclose", None)
        if callable(aclose):
            await aclose()


class Command(BaseCommand):
    help = "Executa o ingestor de mercado com o provider configurado"

    def handle(self, *args, **options):
        try:
            asyncio.run(run_ingestor())
        except (KeyboardInterrupt, asyncio.CancelledError):
            self.stdout.write(self.style.WARNING("Ingestor encerrado."))
