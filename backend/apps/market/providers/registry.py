import os
from collections.abc import Callable

from .base import MarketProvider
from .binance import BinanceMarketProvider

DEFAULT_PROVIDER = "binance"


class ProviderConfigurationError(ValueError):
    pass


_PROVIDER_FACTORIES: dict[str, Callable[[], MarketProvider]] = {
    DEFAULT_PROVIDER: BinanceMarketProvider,
}


def active_provider_codes() -> frozenset[str]:
    return frozenset(_PROVIDER_FACTORIES)


def get_configured_provider_code() -> str:
    provider_code = os.environ.get("MARKET_PROVIDER", DEFAULT_PROVIDER).strip().lower()
    if provider_code not in _PROVIDER_FACTORIES:
        raise ProviderConfigurationError(
            "MARKET_PROVIDER deve ser 'binance'; nenhum outro provedor está habilitado."
        )
    return provider_code


def get_market_provider(provider_code: str | None = None) -> MarketProvider:
    code = (provider_code or get_configured_provider_code()).strip().lower()
    try:
        return _PROVIDER_FACTORIES[code]()
    except KeyError as exc:
        raise ProviderConfigurationError(f"Provedor de mercado não habilitado: {code}.") from exc
