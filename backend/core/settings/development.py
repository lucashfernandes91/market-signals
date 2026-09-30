import os

from .base import *  # noqa: F403

SECRET_KEY = "django-insecure-local-development-only"
DEBUG = True
ALLOWED_HOSTS = ["localhost", "127.0.0.1"]
CORS_ALLOWED_ORIGINS = ["http://localhost:3000", "http://localhost:8080"]

REDIS_URL = os.environ.get("REDIS_URL", "redis://localhost:6380/0")
CHANNEL_LAYERS = {
    "default": {
        "BACKEND": "channels_redis.core.RedisChannelLayer",
        "CONFIG": {"hosts": [REDIS_URL]},
    }
}
