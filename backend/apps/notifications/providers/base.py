from abc import ABC, abstractmethod

from apps.notifications.models import Notification


class NotificationProvider(ABC):
    @abstractmethod
    async def send(self, notification: Notification) -> None:
        raise NotImplementedError
