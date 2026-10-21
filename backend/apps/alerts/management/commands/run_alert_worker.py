import asyncio
import json
import logging
import os
import random
import socket
import time

from asgiref.sync import sync_to_async
from django.core.management.base import BaseCommand
from redis.exceptions import ConnectionError as RedisConnectionError
from redis.exceptions import ResponseError
from redis.exceptions import TimeoutError as RedisTimeoutError

from apps.alerts.index import rebuild_alert_index
from apps.alerts.services import process_market_event
from infrastructure.redis.client import get_async_redis_client
from infrastructure.redis.failures import record_failure
from infrastructure.redis.keys import (
    alerts_index_key,
    market_events_stream,
    market_history_key,
    retry_key,
)
from infrastructure.redis.streams import publish_notification_job
from infrastructure.runtime import install_shutdown_handler

GROUP = "alert-workers"
PENDING_MIN_IDLE_MS = 30_000
INDEX_REFRESH_SECONDS = 30
logger = logging.getLogger(__name__)


async def ensure_group(redis) -> None:
    try:
        await redis.xgroup_create(market_events_stream(), GROUP, id="0", mkstream=True)
    except ResponseError as exc:
        if "BUSYGROUP" not in str(exc):
            raise


async def process_messages(redis, stream: str, messages: list) -> None:
    for message_id, payload in messages:
        try:
            candidate_ids = await redis.smembers(alerts_index_key(payload["market_id"]))
            history = [
                json.loads(point)
                for point in await redis.zrange(market_history_key(payload["market_id"]), 0, -1)
            ]
            events = await sync_to_async(process_market_event)(
                payload=payload,
                source_event_id=message_id,
                candidate_ids=candidate_ids,
                history=history,
            )
            for event in events:
                await publish_notification_job(
                    redis,
                    {
                        "alert_event_id": str(event.id),
                        "user_id": str(event.alert.user_id),
                    },
                )
            await redis.xack(stream, GROUP, message_id)
            await redis.delete(retry_key(GROUP, message_id))
        except Exception as exc:
            await record_failure(
                redis,
                stream=stream,
                group=GROUP,
                message_id=message_id,
                payload=payload,
                error=exc,
            )


async def reclaim_pending(redis, consumer: str) -> None:
    next_id = "0-0"
    while True:
        next_id, messages, *_ = await redis.xautoclaim(
            market_events_stream(),
            GROUP,
            consumer,
            min_idle_time=PENDING_MIN_IDLE_MS,
            start_id=next_id,
            count=50,
        )
        await process_messages(redis, market_events_stream(), messages)
        if next_id == "0-0":
            return


async def run_worker() -> None:
    install_shutdown_handler()
    redis = get_async_redis_client()
    consumer = f"{socket.gethostname()}-{os.getpid()}"
    try:
        await ensure_group(redis)
        next_refresh = 0.0
        backoff = 1.0
        while True:
            try:
                if time.monotonic() >= next_refresh:
                    count = await sync_to_async(rebuild_alert_index)()
                    logger.info("alert.index_rebuilt", extra={"alert_count": count})
                    next_refresh = time.monotonic() + INDEX_REFRESH_SECONDS
                await reclaim_pending(redis, consumer)
                batches = await redis.xreadgroup(
                    GROUP,
                    consumer,
                    {market_events_stream(): ">"},
                    count=50,
                    block=5_000,
                )
                for stream, messages in batches:
                    await process_messages(redis, stream, messages)
                backoff = 1.0
            except RedisTimeoutError:
                continue
            except RedisConnectionError:
                logger.exception("alert.redis_unavailable")
                await asyncio.sleep(backoff + random.uniform(0, 0.5))
                backoff = min(backoff * 2, 30)
    finally:
        await redis.aclose()


class Command(BaseCommand):
    help = "Consome eventos de mercado e avalia alertas"

    def handle(self, *args, **options):
        try:
            asyncio.run(run_worker())
        except (KeyboardInterrupt, asyncio.CancelledError):
            self.stdout.write(self.style.WARNING("Alert Worker encerrado."))
