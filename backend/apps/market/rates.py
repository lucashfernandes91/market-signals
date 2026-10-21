import threading
import time
from dataclasses import dataclass
from decimal import Decimal

from asgiref.sync import async_to_sync

from .providers.registry import get_market_provider


@dataclass(frozen=True, slots=True)
class CurrencyRates:
    usd: Decimal
    brl: Decimal
    source: str

    def as_dict(self) -> dict[str, str | dict[str, str]]:
        return {
            "base": "USDT",
            "rates": {"USD": str(self.usd), "BRL": str(self.brl)},
            "source": self.source,
        }


_cache: tuple[float, CurrencyRates] | None = None
_lock = threading.Lock()
_cache_seconds = 300


def get_currency_rates() -> CurrencyRates:
    global _cache
    now = time.monotonic()
    with _lock:
        if _cache is not None and now - _cache[0] < _cache_seconds:
            return _cache[1]
        rates = async_to_sync(_load_provider_rates)()
        _cache = (now, rates)
        return rates


async def _load_provider_rates() -> CurrencyRates:
    provider = get_market_provider()
    fetch_spot_prices = getattr(provider, "fetch_spot_prices", None)
    if not callable(fetch_spot_prices):
        raise ValueError(f"{provider.code} não fornece taxas de conversão.")
    prices = await fetch_spot_prices(("USDCUSDT", "USDTBRL"))
    usd = prices["USDCUSDT"]
    brl = prices["USDTBRL"]
    if usd <= 0 or brl <= 0:
        raise ValueError("Taxa de conversão inválida.")
    return CurrencyRates(usd=Decimal("1") / usd, brl=brl, source=provider.code)
