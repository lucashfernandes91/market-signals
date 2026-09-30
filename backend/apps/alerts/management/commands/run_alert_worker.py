import asyncio
import os
import socket

from asgiref.sync import sync_to_async
from django.core.management.base import BaseCommand
from redis.exceptions import ConnectionError as RedisConnectionError
from redis.exceptions import ResponseError
from redis.exceptions import TimeoutError as RedisTimeoutError

from apps.alerts.services import process_market_event
from infrastructure.redis.client import get_async_redis_client
from infrastructure.redis.keys import market_events_stream
from infrastructure.redis.streams import publish_notification_job

GROUP = "alert-workers"
PENDING_MIN_IDLE_MS = 30_000


async def ensure_group(redis) -> None:
    try:
        await redis.xgroup_create(market_events_stream(), GROUP, id="0", mkstream=True)
    except ResponseError as exc:
        if "BUSYGROUP" not in str(exc):
            raise


async def process_messages(redis, stream: str, messages: list) -> None:
    for message_id, payload in messages:
        events = await sync_to_async(process_market_event)(payload=payload)
        for event in events:
            await publish_notification_job(
                redis,
                {
                    "alert_event_id": str(event.id),
                    "user_id": str(event.alert.user_id),
                },
            )
        await redis.xack(stream, GROUP, message_id)


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
    redis = get_async_redis_client()
    consumer = f"{socket.gethostname()}-{os.getpid()}"
    await ensure_group(redis)
    try:
        await reclaim_pending(redis, consumer)
        while True:
            try:
                batches = await redis.xreadgroup(
                    GROUP,
                    consumer,
                    {market_events_stream(): ">"},
                    count=50,
                    block=5_000,
                )
            except RedisTimeoutError:
                continue
            except RedisConnectionError:
                await asyncio.sleep(1)
                continue
            for stream, messages in batches:
                await process_messages(redis, stream, messages)
    finally:
        await redis.aclose()


class Command(BaseCommand):
    help = "Consome eventos de mercado e avalia alertas"

    def handle(self, *args, **options):
        try:
            asyncio.run(run_worker())
        except KeyboardInterrupt:
            self.stdout.write(self.style.WARNING("Alert Worker encerrado."))
