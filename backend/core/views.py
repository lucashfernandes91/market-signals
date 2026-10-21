import os
from uuid import uuid4

from channels.layers import get_channel_layer
from django.conf import settings
from django.core.cache import cache
from django.db import connections
from django.db.utils import OperationalError
from django.http import JsonResponse
from django.views.decorators.http import require_GET
from redis.exceptions import RedisError

from infrastructure.redis.client import get_redis_client


@require_GET
def live(request):
    return JsonResponse({"status": "ok"})


@require_GET
def ready(request):
    try:
        connections["default"].ensure_connection()
    except OperationalError:
        return JsonResponse({"status": "unavailable"}, status=503)

    try:
        redis_client = get_redis_client()
    except (TypeError, ValueError):
        return JsonResponse({"status": "unavailable"}, status=503)
    try:
        redis_client.ping()
    except RedisError:
        return JsonResponse({"status": "unavailable"}, status=503)
    finally:
        redis_client.close()

    try:
        cache_key = f"health:ready:{uuid4().hex}"
        cache.set(cache_key, "ok", timeout=1)
        cache_available = cache.get(cache_key) == "ok"
        cache.delete(cache_key)
    except (RedisError, OSError, TypeError, ValueError):
        cache_available = False

    try:
        channel_layer = get_channel_layer()
        channels_configured = channel_layer is not None and bool(
            settings.CHANNEL_LAYERS.get("default", {}).get("BACKEND")
        )
    except (ImportError, KeyError, TypeError, ValueError):
        channels_configured = False

    if not cache_available or not channels_configured:
        return JsonResponse({"status": "unavailable"}, status=503)

    return JsonResponse({"status": "ok", "database": "ok", "redis": "ok"})


@require_GET
def status(request):
    return JsonResponse(
        {
            "service": "market-radar-backend",
            "status": "ok",
            "version": os.environ.get("APP_VERSION", "v1"),
        }
    )
