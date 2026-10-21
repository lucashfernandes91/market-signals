from dataclasses import dataclass, field
from datetime import UTC, datetime
from decimal import Decimal
from uuid import UUID


@dataclass(frozen=True, slots=True)
class MarketSubscription:
    market_id: UUID
    symbol: str
    provider_symbol: str | None = None
    provider: str = "binance"
    provider_name: str = "Binance"
    provider_market_id: UUID | None = None


@dataclass(frozen=True, slots=True)
class ProviderCatalogMarket:
    external_symbol: str
    base_symbol: str
    quote_symbol: str
    status: str
    base_precision: int | None = None
    quote_precision: int | None = None
    metadata: dict[str, object] = field(default_factory=dict)


@dataclass(frozen=True, slots=True)
class MarketQuote:
    market_id: UUID
    symbol: str
    price: Decimal
    volume_24h: Decimal
    timestamp: datetime
    change_24h_percent: Decimal = Decimal("0")
    stale: bool = False
    source_status: str | None = None
    provider: str = "binance"
    provider_name: str = "Binance"
    provider_symbol: str | None = None
    provider_market_id: UUID | None = None
    received_at: datetime = field(default_factory=lambda: datetime.now(UTC))

    def as_redis_mapping(self) -> dict[str, str]:
        payload = {
            "market_id": str(self.market_id),
            "symbol": self.symbol,
            "price": str(self.price),
            "volume_24h": str(self.volume_24h),
            "change_24h_percent": str(self.change_24h_percent),
            "timestamp": self.timestamp.isoformat(),
            "provider_timestamp": self.timestamp.isoformat(),
            "received_at": self.received_at.isoformat(),
            "provider": self.provider,
            "provider_name": self.provider_name,
            "provider_symbol": self.provider_symbol or self.symbol.replace("-", "").upper(),
            "stale": str(self.stale).lower(),
            "source_status": self.source_status or ("stale" if self.stale else "live"),
        }
        if self.provider_market_id is not None:
            payload["provider_market_id"] = str(self.provider_market_id)
        return payload


@dataclass(frozen=True, slots=True)
class MarketCandle:
    market_id: UUID
    symbol: str
    interval: str
    open_time: datetime
    close_time: datetime
    open: Decimal
    high: Decimal
    low: Decimal
    close: Decimal
    volume: Decimal
    quote_volume: Decimal
    trades: int
