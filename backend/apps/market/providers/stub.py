import asyncio
from collections.abc import AsyncIterator, Sequence
from datetime import UTC, datetime
from decimal import Decimal

from .base import MarketProvider
from .models import MarketCandle, MarketQuote, MarketSubscription, ProviderCatalogMarket


class StubMarketProvider(MarketProvider):
    code = "stub"
    display_name = "Stub"

    def __init__(self, interval_seconds: float = 1.0) -> None:
        self.interval_seconds = interval_seconds
        self._tick = 0

    async def fetch_catalog(self) -> list[ProviderCatalogMarket]:
        return []

    async def stream_quotes(
        self,
        markets: Sequence[MarketSubscription],
    ) -> AsyncIterator[MarketQuote]:
        while True:
            self._tick += 1
            for index, market in enumerate(markets, start=1):
                base_price = Decimal(index * 1_000)
                yield MarketQuote(
                    market_id=market.market_id,
                    symbol=market.symbol,
                    price=base_price + Decimal(self._tick),
                    volume_24h=Decimal(index * 1_000_000 + self._tick * 100),
                    timestamp=datetime.now(UTC),
                    provider=self.code,
                    provider_name=self.display_name,
                    provider_symbol=market.provider_symbol,
                    provider_market_id=market.provider_market_id,
                )
            await asyncio.sleep(self.interval_seconds)

    async def fetch_candles(
        self,
        market: MarketSubscription,
        *,
        interval: str,
        limit: int,
    ) -> list[MarketCandle]:
        return []
