import asyncio
import logging
import os
import random
import socket

from asgiref.sync import sync_to_async
from django.core.management.base import BaseCommand
from redis.exceptions import ConnectionError as RedisConnectionError
from redis.exceptions import ResponseError
from redis.exceptions import TimeoutError as RedisTimeoutError

from apps.notifications.providers import build_notification_provider
from apps.notifications.services import (
    mark_notification_failed,
    mark_notification_sent,
    prepare_notification,
)
from infrastructure.redis.client import get_async_redis_client
from infrastructure.redis.failures import record_failure
from infrastructure.redis.keys import notification_jobs_stream, retry_key
from infrastructure.runtime import install_shutdown_handler

GROUP = "notification-workers"
PENDING_MIN_IDLE_MS = 30_000
logger = logging.getLogger(__name__)


async def ensure_group(redis) -> None:
    try:
        await redis.xgroup_create(notification_jobs_stream(), GROUP, id="0", mkstream=True)
    except ResponseError as exc:
        if "BUSYGROUP" not in str(exc):
            raise


async def process_messages(redis, stream: str, messages: list) -> None:
    provider = build_notification_provider()
    for message_id, payload in messages:
        try:
            notification = await sync_to_async(prepare_notification)(
                alert_event_id=payload["alert_event_id"]
            )
            if notification.status != notification.Status.SENT:
                await provider.send(notification)
                await sync_to_async(mark_notification_sent)(notification=notification)
            await redis.xack(stream, GROUP, message_id)
            await redis.delete(retry_key(GROUP, message_id))
        except Exception as exc:
            dead_lettered = await record_failure(
                redis,
                stream=stream,
                group=GROUP,
                message_id=message_id,
                payload=payload,
                error=exc,
            )
            if dead_lettered and "alert_event_id" in payload:
                await sync_to_async(mark_notification_failed)(
                    alert_event_id=payload["alert_event_id"]
                )


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
    install_shutdown_handler()
    redis = get_async_redis_client()
    consumer = f"{socket.gethostname()}-{os.getpid()}"
    try:
        await ensure_group(redis)
        backoff = 1.0
        while True:
            try:
                await reclaim_pending(redis, consumer)
                batches = await redis.xreadgroup(
                    GROUP,
                    consumer,
                    {notification_jobs_stream(): ">"},
                    count=50,
                    block=5_000,
                )
                for stream, messages in batches:
                    await process_messages(redis, stream, messages)
                backoff = 1.0
            except RedisTimeoutError:
                continue
            except RedisConnectionError:
                logger.exception("notification.redis_unavailable")
                await asyncio.sleep(backoff + random.uniform(0, 0.5))
                backoff = min(backoff * 2, 30)
    finally:
        await redis.aclose()


class Command(BaseCommand):
    help = "Consome jobs e envia notificações pelo provider configurado"

    def handle(self, *args, **options):
        try:
            asyncio.run(run_worker())
        except (KeyboardInterrupt, asyncio.CancelledError):
            self.stdout.write(self.style.WARNING("Notification Worker encerrado."))
