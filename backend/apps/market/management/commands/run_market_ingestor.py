import asyncio
import logging
import random

from asgiref.sync import sync_to_async
from channels.layers import get_channel_layer
from django.core.management.base import BaseCommand
from redis.exceptions import ConnectionError as RedisConnectionError
from redis.exceptions import TimeoutError as RedisTimeoutError

from apps.market.ingestion import ingest_quote
from apps.market.models import Market
from apps.market.providers import MarketSubscription, StubMarketProvider
from infrastructure.redis.client import get_async_redis_client
from infrastructure.runtime import install_shutdown_handler

logger = logging.getLogger(__name__)


@sync_to_async
def get_subscriptions() -> list[MarketSubscription]:
    return [
        MarketSubscription(market_id=market_id, symbol=symbol)
        for market_id, symbol in Market.objects.filter(is_active=True).values_list(
            "id", "canonical_symbol"
        )
    ]


async def run_ingestor() -> None:
    install_shutdown_handler()
    subscriptions = await get_subscriptions()
    if not subscriptions:
        raise RuntimeError("Nenhum mercado ativo. Execute seed_market antes do ingestor.")

    provider = StubMarketProvider()
    redis = get_async_redis_client()
    channel_layer = get_channel_layer()
    try:
        backoff = 1.0
        async for quote in provider.stream_quotes(subscriptions):
            try:
                await ingest_quote(quote=quote, redis=redis, channel_layer=channel_layer)
                backoff = 1.0
            except (RedisConnectionError, RedisTimeoutError):
                logger.exception("market.redis_unavailable")
                await asyncio.sleep(backoff + random.uniform(0, 0.5))
                backoff = min(backoff * 2, 30)
    finally:
        await redis.aclose()


class Command(BaseCommand):
    help = "Executa o ingestor de mercado com o provider configurado"

    def handle(self, *args, **options):
        try:
            asyncio.run(run_ingestor())
        except (KeyboardInterrupt, asyncio.CancelledError):
            self.stdout.write(self.style.WARNING("Ingestor encerrado."))
