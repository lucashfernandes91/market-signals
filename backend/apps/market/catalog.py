import os
from collections.abc import Iterable
from dataclasses import dataclass

from django.db import transaction
from django.utils.text import slugify

from .models import Asset, Market, ProviderMarket
from .providers.models import ProviderCatalogMarket
from .providers.registry import active_provider_codes, get_market_provider

TRADING_STATUS = "TRADING"
FIAT_SYMBOLS = frozenset({"AUD", "BRL", "CAD", "CHF", "EUR", "GBP", "JPY", "TRY", "USD"})


def _env_symbols(name: str, default: str = "") -> frozenset[str]:
    raw_value = os.environ.get(name, default)
    return frozenset(symbol.strip().upper() for symbol in raw_value.split(",") if symbol.strip())


@dataclass(frozen=True, slots=True)
class CatalogPolicy:
    quote_assets: frozenset[str]
    base_assets: frozenset[str]
    excluded_assets: frozenset[str]
    max_pairs: int | None

    @classmethod
    def from_environment(cls) -> "CatalogPolicy":
        raw_max_pairs = os.environ.get("MARKET_CATALOG_MAX_PAIRS", "0")
        try:
            max_pairs = int(raw_max_pairs)
        except ValueError as exc:
            raise ValueError("MARKET_CATALOG_MAX_PAIRS deve ser um inteiro.") from exc
        if max_pairs < 0:
            raise ValueError("MARKET_CATALOG_MAX_PAIRS não pode ser negativo.")
        return cls(
            quote_assets=_env_symbols("MARKET_CATALOG_QUOTE_ASSETS", "USDT"),
            base_assets=_env_symbols("MARKET_CATALOG_BASE_ASSETS"),
            excluded_assets=_env_symbols("MARKET_CATALOG_EXCLUDED_ASSETS"),
            max_pairs=max_pairs or None,
        )

    def allows(self, item: ProviderCatalogMarket) -> bool:
        base_symbol = item.base_symbol.upper()
        quote_symbol = item.quote_symbol.upper()
        return (
            item.status.upper() == TRADING_STATUS
            and len(base_symbol) <= 16
            and len(quote_symbol) <= 16
            and base_symbol != quote_symbol
            and quote_symbol in self.quote_assets
            and (not self.base_assets or base_symbol in self.base_assets)
            and base_symbol not in self.excluded_assets
            and quote_symbol not in self.excluded_assets
        )


@dataclass(frozen=True, slots=True)
class CatalogSyncResult:
    discovered: int
    allowed: int
    assets_created: int
    markets_created: int
    provider_markets_created: int
    deactivated: int


async def fetch_configured_catalog() -> tuple[str, list[ProviderCatalogMarket]]:
    provider = get_market_provider()
    return provider.code, await provider.fetch_catalog()


def sync_catalog(
    *,
    provider: str,
    catalog: Iterable[ProviderCatalogMarket],
    policy: CatalogPolicy | None = None,
) -> CatalogSyncResult:
    active_policy = policy or CatalogPolicy.from_environment()
    catalog_items = list(catalog)
    catalog_by_symbol = {item.external_symbol.upper(): item for item in catalog_items}
    allowed_items = sorted(
        (item for item in catalog_items if active_policy.allows(item)),
        key=lambda item: item.external_symbol,
    )
    if active_policy.max_pairs is not None:
        allowed_items = allowed_items[: active_policy.max_pairs]

    assets_created = 0
    markets_created = 0
    provider_markets_created = 0
    deactivated = 0
    with transaction.atomic():
        for item in allowed_items:
            base_asset, base_created = _upsert_asset(item.base_symbol, Asset.Type.CRYPTO)
            quote_asset, quote_created = _upsert_asset(
                item.quote_symbol,
                Asset.Type.FIAT if item.quote_symbol.upper() in FIAT_SYMBOLS else Asset.Type.CRYPTO,
            )
            assets_created += int(base_created) + int(quote_created)

            canonical_symbol = f"{base_asset.symbol}-{quote_asset.symbol}"
            market, market_created = Market.objects.update_or_create(
                canonical_symbol=canonical_symbol,
                defaults={
                    "base_asset": base_asset,
                    "quote_asset": quote_asset,
                    "is_active": True,
                },
            )
            markets_created += int(market_created)
            _, provider_market_created = ProviderMarket.objects.update_or_create(
                provider=provider,
                external_symbol=item.external_symbol.upper(),
                defaults={
                    "market": market,
                    "metadata": _metadata_for(item),
                    "is_active": True,
                },
            )
            provider_markets_created += int(provider_market_created)

        inactive_symbols = [
            external_symbol
            for external_symbol, item in catalog_by_symbol.items()
            if item.status.upper() != TRADING_STATUS
        ]
        missing_symbols = ProviderMarket.objects.filter(provider=provider, is_active=True).exclude(
            external_symbol__in=catalog_by_symbol
        )
        inactive_markets = list(
            ProviderMarket.objects.filter(
                provider=provider,
                is_active=True,
                external_symbol__in=inactive_symbols,
            ).values_list("market_id", flat=True)
        ) + list(missing_symbols.values_list("market_id", flat=True))
        deactivated += len(set(inactive_markets))
        ProviderMarket.objects.filter(
            provider=provider,
            is_active=True,
            external_symbol__in=inactive_symbols,
        ).update(is_active=False)
        missing_symbols.update(is_active=False)

        for market_id in set(inactive_markets):
            market = Market.objects.get(pk=market_id)
            if not market.provider_markets.filter(
                provider__in=active_provider_codes(), is_active=True
            ).exists():
                market.is_active = False
                market.save(update_fields=("is_active", "updated_at"))

    return CatalogSyncResult(
        discovered=len(catalog_items),
        allowed=len(allowed_items),
        assets_created=assets_created,
        markets_created=markets_created,
        provider_markets_created=provider_markets_created,
        deactivated=deactivated,
    )


def _upsert_asset(symbol: str, asset_type: str) -> tuple[Asset, bool]:
    normalized_symbol = symbol.upper()
    slug = slugify(normalized_symbol)
    if not slug or Asset.objects.filter(slug=slug).exclude(symbol=normalized_symbol).exists():
        encoded_symbol = "-".join(f"{ord(character):06x}" for character in normalized_symbol)
        slug = f"asset-{encoded_symbol}"
        suffix = 1
        while Asset.objects.filter(slug=slug).exclude(symbol=normalized_symbol).exists():
            slug = f"asset-{encoded_symbol}-{suffix}"
            suffix += 1

    asset, created = Asset.objects.get_or_create(
        symbol=normalized_symbol,
        defaults={
            "name": normalized_symbol,
            "slug": slug,
            "asset_type": asset_type,
            "is_active": True,
        },
    )
    if not created and not asset.is_active:
        asset.is_active = True
        asset.save(update_fields=("is_active", "updated_at"))
    return asset, created


def _metadata_for(item: ProviderCatalogMarket) -> dict[str, object]:
    return {
        "status": item.status.upper(),
        "base_precision": item.base_precision,
        "quote_precision": item.quote_precision,
        **item.metadata,
    }
