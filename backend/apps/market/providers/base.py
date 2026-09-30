from abc import ABC, abstractmethod
from collections.abc import AsyncIterator, Sequence

from .models import MarketQuote, MarketSubscription


class MarketProvider(ABC):
    @abstractmethod
    def stream_quotes(
        self,
        markets: Sequence[MarketSubscription],
    ) -> AsyncIterator[MarketQuote]:
        raise NotImplementedError
