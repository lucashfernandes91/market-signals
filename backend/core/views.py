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
    redis = None
    try:
        connections["default"].ensure_connection()
        redis = get_redis_client()
        redis.ping()
    except (OperationalError, RedisError):
        return JsonResponse({"status": "unavailable"}, status=503)
    finally:
        if redis is not None:
            redis.close()
    return JsonResponse({"status": "ok", "database": "ok", "redis": "ok"})


@require_GET
def status(request):
    return JsonResponse({"service": "market-radar-backend", "status": "ok", "version": "v1"})
