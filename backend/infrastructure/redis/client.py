from django.conf import settings
from redis import Redis
from redis.asyncio import Redis as AsyncRedis


def get_redis_client() -> Redis:
    return Redis.from_url(
        settings.REDIS_URL,
        decode_responses=True,
        socket_connect_timeout=5,
        socket_timeout=10,
    )


def get_async_redis_client() -> AsyncRedis:
    return AsyncRedis.from_url(
        settings.REDIS_URL,
        decode_responses=True,
        socket_connect_timeout=5,
        socket_timeout=10,
    )
