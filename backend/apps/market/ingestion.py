import json
from datetime import UTC, datetime

from channels.layers import BaseChannelLayer
from redis.asyncio import Redis

from infrastructure.redis.keys import market_history_key, market_state_key
from infrastructure.redis.streams import publish_market_event

from .providers import MarketQuote


async def ingest_quote(
    *,
    quote: MarketQuote,
    redis: Redis,
    channel_layer: BaseChannelLayer,
) -> None:
    payload = quote.as_redis_mapping()
    timestamp = quote.timestamp.timestamp()
    history_key = market_history_key(quote.market_id)
    point = json.dumps(
        {
            "price": str(quote.price),
            "volume_24h": str(quote.volume_24h),
            "change_24h_percent": str(quote.change_24h_percent),
            "timestamp": quote.timestamp.isoformat(),
        },
        separators=(",", ":"),
    )
    if hasattr(redis, "zadd"):
        await redis.zadd(history_key, {point: timestamp})
        await redis.zremrangebyscore(history_key, 0, timestamp - 86_400)
    payload["sequence"] = await publish_market_event(redis, payload)
    await redis.hset(market_state_key(quote.market_id), mapping=payload)
    await channel_layer.group_send(
        f"market.{quote.market_id}",
        {"type": "market.update", "data": payload},
    )


async def mark_stale_quotes(
    *,
    market_ids,
    redis: Redis,
    channel_layer: BaseChannelLayer,
    stale_after_seconds: int = 15,
    now: datetime | None = None,
) -> int:
    current_time = now or datetime.now(UTC)
    marked = 0
    for market_id in market_ids:
        key = market_state_key(market_id)
        state = await redis.hgetall(key)
        if not state or state.get("stale") == "true":
            continue
        raw_timestamp = state.get("timestamp")
        if not raw_timestamp:
            continue
        try:
            timestamp = datetime.fromisoformat(raw_timestamp.replace("Z", "+00:00"))
            if timestamp.tzinfo is None:
                timestamp = timestamp.replace(tzinfo=UTC)
        except ValueError:
            continue
        if (current_time - timestamp).total_seconds() <= stale_after_seconds:
            continue
        state["stale"] = "true"
        state["source_status"] = "stale"
        await redis.hset(key, mapping={"stale": "true", "source_status": "stale"})
        await channel_layer.group_send(
            f"market.{market_id}",
            {"type": "market.update", "data": state},
        )
        marked += 1
    return marked
