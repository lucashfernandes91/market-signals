from abc import ABC, abstractmethod
from collections.abc import AsyncIterator, Sequence

from .models import MarketCandle, MarketQuote, MarketSubscription, ProviderCatalogMarket


class MarketProvider(ABC):
    code: str
    display_name: str

    async def fetch_catalog(self) -> list[ProviderCatalogMarket]:
        raise NotImplementedError

    @abstractmethod
    async def fetch_candles(
        self,
        market: MarketSubscription,
        *,
        interval: str,
        limit: int,
    ) -> list[MarketCandle]:
        raise NotImplementedError

    @abstractmethod
    def stream_quotes(
        self,
        markets: Sequence[MarketSubscription],
    ) -> AsyncIterator[MarketQuote]:
        raise NotImplementedError
