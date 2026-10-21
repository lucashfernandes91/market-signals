import os

from .fcm import FcmNotificationProvider
from .stub import StubNotificationProvider


def build_notification_provider():
    provider = os.environ.get("NOTIFICATION_PROVIDER", "stub").strip().lower()
    if provider == "stub":
        return StubNotificationProvider()
    if provider == "fcm":
        return FcmNotificationProvider()
    raise ValueError(f"Provider de notificação inválido: {provider}")


__all__ = ("FcmNotificationProvider", "StubNotificationProvider", "build_notification_provider")
