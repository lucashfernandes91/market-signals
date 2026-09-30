from dataclasses import dataclass
from datetime import datetime
from decimal import Decimal
from uuid import UUID


@dataclass(frozen=True, slots=True)
class MarketSubscription:
    market_id: UUID
    symbol: str


@dataclass(frozen=True, slots=True)
class MarketQuote:
    market_id: UUID
    symbol: str
    price: Decimal
    volume_24h: Decimal
    timestamp: datetime

    def as_redis_mapping(self) -> dict[str, str]:
        return {
            "market_id": str(self.market_id),
            "symbol": self.symbol,
            "price": str(self.price),
            "volume_24h": str(self.volume_24h),
            "timestamp": self.timestamp.isoformat(),
        }
