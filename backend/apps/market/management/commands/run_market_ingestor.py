import asyncio

from asgiref.sync import sync_to_async
from channels.layers import get_channel_layer
from django.core.management.base import BaseCommand

from apps.market.ingestion import ingest_quote
from apps.market.models import Market
from apps.market.providers import MarketSubscription, StubMarketProvider
from infrastructure.redis.client import get_async_redis_client


@sync_to_async
def get_subscriptions() -> list[MarketSubscription]:
    return [
        MarketSubscription(market_id=market_id, symbol=symbol)
        for market_id, symbol in Market.objects.filter(is_active=True).values_list(
            "id", "canonical_symbol"
        )
    ]


async def run_ingestor() -> None:
    subscriptions = await get_subscriptions()
    if not subscriptions:
        raise RuntimeError("Nenhum mercado ativo. Execute seed_market antes do ingestor.")

    provider = StubMarketProvider()
    redis = get_async_redis_client()
    channel_layer = get_channel_layer()
    try:
        async for quote in provider.stream_quotes(subscriptions):
            await ingest_quote(quote=quote, redis=redis, channel_layer=channel_layer)
    finally:
        await redis.aclose()


class Command(BaseCommand):
    help = "Executa o ingestor de mercado com o provider configurado"

    def handle(self, *args, **options):
        try:
            asyncio.run(run_ingestor())
        except KeyboardInterrupt:
            self.stdout.write(self.style.WARNING("Ingestor encerrado."))
