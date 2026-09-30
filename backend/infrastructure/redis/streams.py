from collections.abc import Mapping

from redis.asyncio import Redis

from .keys import market_events_stream, notification_jobs_stream


async def publish_market_event(redis: Redis, payload: Mapping[str, str]) -> str:
    return await redis.xadd(market_events_stream(), payload, maxlen=100_000, approximate=True)


async def publish_notification_job(redis: Redis, payload: Mapping[str, str]) -> str:
    return await redis.xadd(
        notification_jobs_stream(),
        payload,
        maxlen=100_000,
        approximate=True,
    )
