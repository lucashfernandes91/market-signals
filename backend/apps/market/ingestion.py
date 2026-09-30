from channels.layers import BaseChannelLayer
from redis.asyncio import Redis

from infrastructure.redis.keys import market_state_key
from infrastructure.redis.streams import publish_market_event

from .providers import MarketQuote


async def ingest_quote(
    *,
    quote: MarketQuote,
    redis: Redis,
    channel_layer: BaseChannelLayer,
) -> None:
    payload = quote.as_redis_mapping()
    await redis.hset(market_state_key(quote.market_id), mapping=payload)
    await publish_market_event(redis, payload)
    await channel_layer.group_send(
        f"market.{quote.market_id}",
        {"type": "market.update", "data": payload},
    )
