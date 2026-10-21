import asyncio
from collections.abc import Sequence
from uuid import UUID

from .models import Market, ProviderMarket
from .providers.models import MarketCandle, MarketSubscription
from .providers.registry import get_configured_provider_code, get_market_provider


class MarketSourceUnavailable(Exception):
    """A fonte configurada não possui uma listagem ativa para o mercado."""


def provider_markets_for(markets: Sequence[Market]) -> dict[UUID, ProviderMarket]:
    market_ids = [market.id for market in markets]
    if not market_ids:
        return {}
    return {
        provider_market.market_id: provider_market
        for provider_market in ProviderMarket.objects.filter(
            provider=get_configured_provider_code(),
            market_id__in=market_ids,
            is_active=True,
            market__is_active=True,
        )
    }


def subscriptions_for_markets(markets: Sequence[Market]) -> list[MarketSubscription]:
    provider = get_market_provider()
    provider_markets = provider_markets_for(markets)
    return [
        MarketSubscription(
            market_id=market.id,
            symbol=market.canonical_symbol,
            provider=provider.code,
            provider_name=provider.display_name,
            provider_market_id=provider_markets[market.id].id
            if market.id in provider_markets
            else None,
            provider_symbol=provider_markets[market.id].external_symbol
            if market.id in provider_markets
            else None,
        )
        for market in markets
    ]


def ensure_active_listing(subscription: MarketSubscription) -> None:
    if subscription.provider_market_id is None or subscription.provider_symbol is None:
        raise MarketSourceUnavailable("O mercado não está disponível na fonte configurada.")


def origin_for_subscription(subscription: MarketSubscription) -> dict[str, str | None]:
    return {
        "provider_market_id": str(subscription.provider_market_id)
        if subscription.provider_market_id
        else None,
        "provider": subscription.provider,
        "provider_name": subscription.provider_name,
        "provider_symbol": subscription.provider_symbol
        or subscription.symbol.replace("-", "").upper(),
    }


async def fetch_candles(
    subscription: MarketSubscription,
    *,
    interval: str,
    limit: int,
) -> list[MarketCandle]:
    ensure_active_listing(subscription)
    provider = get_market_provider(subscription.provider)
    return await provider.fetch_candles(subscription, interval=interval, limit=limit)


async def fetch_candles_for_subscriptions(
    subscriptions: Sequence[MarketSubscription],
    *,
    interval: str,
    limit: int,
) -> list[list[MarketCandle] | Exception]:
    if not subscriptions:
        return []
    for subscription in subscriptions:
        ensure_active_listing(subscription)
    provider = get_market_provider(subscriptions[0].provider)
    return await asyncio.gather(
        *[
            provider.fetch_candles(subscription, interval=interval, limit=limit)
            for subscription in subscriptions
        ],
        return_exceptions=True,
    )
