import json
import logging

from redis.asyncio import Redis

from .keys import dead_letter_stream, retry_key

logger = logging.getLogger(__name__)
MAX_ATTEMPTS = 3


async def record_failure(
    redis: Redis,
    *,
    stream: str,
    group: str,
    message_id: str,
    payload: dict[str, str],
    error: Exception,
) -> bool:
    key = retry_key(group, message_id)
    attempts = await redis.incr(key)
    await redis.expire(key, 86_400)
    logger.error(
        "worker.message_failed",
        extra={"message_id": message_id},
        exc_info=(type(error), error, error.__traceback__),
    )
    if attempts < MAX_ATTEMPTS:
        return False
    await redis.xadd(
        dead_letter_stream(),
        {
            "source_stream": stream,
            "group": group,
            "message_id": message_id,
            "payload": json.dumps(payload, ensure_ascii=False),
            "error": type(error).__name__,
            "attempts": str(attempts),
        },
    )
    await redis.xack(stream, group, message_id)
    await redis.delete(key)
    return True
