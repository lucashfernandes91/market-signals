from apps.notifications.models import Notification

from .base import NotificationProvider


class StubNotificationProvider(NotificationProvider):
    async def send(self, notification: Notification) -> None:
        return None
