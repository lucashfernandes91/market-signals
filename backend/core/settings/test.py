from .base import *  # noqa: F403

SECRET_KEY = "django-insecure-tests-only"
DATABASES["default"]["NAME"] = BASE_DIR / "data" / "test_market_radar.sqlite3"  # noqa: F405

CHANNEL_LAYERS = {"default": {"BACKEND": "channels.layers.InMemoryChannelLayer"}}
