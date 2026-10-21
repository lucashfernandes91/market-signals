import json
import os
from pathlib import Path

from asgiref.sync import sync_to_async

from apps.notifications.models import Device, Notification

from .base import NotificationProvider


class FcmNotificationProvider(NotificationProvider):
    async def send(self, notification: Notification) -> None:
        await sync_to_async(self._send_sync)(notification)

    def _send_sync(self, notification: Notification) -> None:
        import firebase_admin
        from firebase_admin import credentials, messaging

        app = self._firebase_app(firebase_admin, credentials)
        devices = list(
            Device.objects.filter(
                user_id=notification.user_id,
                provider=Device.Provider.FCM,
                enabled=True,
            )
        )
        if not devices:
            raise RuntimeError("Usuário não possui dispositivo FCM ativo.")

        delivered = 0
        for device in devices:
            message = messaging.Message(
                notification=messaging.Notification(
                    title=notification.title,
                    body=notification.body,
                ),
                data={key: self._stringify(value) for key, value in notification.payload.items()},
                token=device.token,
            )
            try:
                messaging.send(message, app=app)
                delivered += 1
            except messaging.UnregisteredError:
                Device.objects.filter(pk=device.pk).update(enabled=False)

        if delivered == 0:
            raise RuntimeError("Nenhum dispositivo FCM aceitou a notificação.")

    @staticmethod
    def _firebase_app(firebase_admin, credentials):
        try:
            return firebase_admin.get_app()
        except ValueError:
            path = os.environ.get("FIREBASE_CREDENTIALS_PATH", "")
            if not path or not Path(path).is_file():
                raise RuntimeError("FIREBASE_CREDENTIALS_PATH não aponta para um arquivo válido.")
            return firebase_admin.initialize_app(credentials.Certificate(path))

    @staticmethod
    def _stringify(value) -> str:
        if isinstance(value, str):
            return value
        return json.dumps(value, ensure_ascii=False, separators=(",", ":"))
