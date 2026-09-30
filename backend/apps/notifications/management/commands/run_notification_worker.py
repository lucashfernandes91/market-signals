import asyncio
import os
import socket

from asgiref.sync import sync_to_async
from django.core.management.base import BaseCommand
from redis.exceptions import ConnectionError as RedisConnectionError
from redis.exceptions import ResponseError
from redis.exceptions import TimeoutError as RedisTimeoutError

from apps.notifications.providers import StubNotificationProvider
from apps.notifications.services import mark_notification_sent, prepare_notification
from infrastructure.redis.client import get_async_redis_client
from infrastructure.redis.keys import notification_jobs_stream

GROUP = "notification-workers"
PENDING_MIN_IDLE_MS = 30_000


async def ensure_group(redis) -> None:
    try:
        await redis.xgroup_create(notification_jobs_stream(), GROUP, id="0", mkstream=True)
    except ResponseError as exc:
        if "BUSYGROUP" not in str(exc):
            raise


async def process_messages(redis, stream: str, messages: list) -> None:
    provider = StubNotificationProvider()
    for message_id, payload in messages:
        notification = await sync_to_async(prepare_notification)(
            alert_event_id=payload["alert_event_id"]
        )
        await provider.send(notification)
        await sync_to_async(mark_notification_sent)(notification=notification)
        await redis.xack(stream, GROUP, message_id)


async def reclaim_pending(redis, consumer: str) -> None:
    next_id = "0-0"
    while True:
        next_id, messages, *_ = await redis.xautoclaim(
            notification_jobs_stream(),
            GROUP,
            consumer,
            min_idle_time=PENDING_MIN_IDLE_MS,
            start_id=next_id,
            count=50,
        )
        await process_messages(redis, notification_jobs_stream(), messages)
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
                    {notification_jobs_stream(): ">"},
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
    help = "Consome jobs e envia notificações pelo provider configurado"

    def handle(self, *args, **options):
        try:
            asyncio.run(run_worker())
        except KeyboardInterrupt:
            self.stdout.write(self.style.WARNING("Notification Worker encerrado."))
