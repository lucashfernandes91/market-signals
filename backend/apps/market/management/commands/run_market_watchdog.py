import asyncio
import logging
import os
from uuid import UUID

from asgiref.sync import sync_to_async
from channels.layers import get_channel_layer
from django.core.management.base import BaseCommand
from redis.exceptions import ConnectionError as RedisConnectionError
from redis.exceptions import TimeoutError as RedisTimeoutError

from apps.market.ingestion import mark_stale_quotes
from apps.market.models import ProviderMarket
from apps.market.providers.registry import get_configured_provider_code
from infrastructure.redis.client import get_async_redis_client
from infrastructure.runtime import install_shutdown_handler

logger = logging.getLogger(__name__)


def _positive_int_from_environment(name: str, default: int) -> int:
    raw_value = os.environ.get(name, str(default))
    try:
        value = int(raw_value)
    except ValueError as exc:
        raise ValueError(f"{name} deve ser um inteiro.") from exc
    if value <= 0:
        raise ValueError(f"{name} deve ser maior que zero.")
    return value


def load_market_ids(provider_name: str) -> list[UUID]:
    return list(
        ProviderMarket.objects.filter(
            provider=provider_name,
            is_active=True,
            market__is_active=True,
        ).values_list("market_id", flat=True)
    )


get_market_ids = sync_to_async(load_market_ids)


async def run_watchdog() -> None:
    install_shutdown_handler()
    provider_name = get_configured_provider_code()
    check_seconds = _positive_int_from_environment("MARKET_STALE_CHECK_SECONDS", 5)
    stale_after_seconds = _positive_int_from_environment("MARKET_STALE_AFTER_SECONDS", 15)
    redis = get_async_redis_client()
    channel_layer = get_channel_layer()
    try:
        while True:
            try:
                market_ids = await get_market_ids(provider_name)
                marked = await mark_stale_quotes(
                    market_ids=market_ids,
                    redis=redis,
                    channel_layer=channel_layer,
                    stale_after_seconds=stale_after_seconds,
                )
                if marked:
                    logger.warning("market.quotes_marked_stale", extra={"count": marked})
            except (RedisConnectionError, RedisTimeoutError):
                logger.exception("market.stale_check_redis_unavailable")
            await asyncio.sleep(check_seconds)
    finally:
        await redis.aclose()


class Command(BaseCommand):
    help = "Monitora cotações sem atualização e publica o estado stale"

    def handle(self, *args, **options):
        try:
            asyncio.run(run_watchdog())
        except (KeyboardInterrupt, asyncio.CancelledError):
            self.stdout.write(self.style.WARNING("Watchdog de mercado encerrado."))
