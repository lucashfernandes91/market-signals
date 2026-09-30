from django.conf import settings
from django.db import models

from apps.alerts.models import AlertEvent
from apps.common.models import UUIDTimeStampedModel


class Device(UUIDTimeStampedModel):
    class Platform(models.TextChoices):
        ANDROID = "android", "Android"
        IOS = "ios", "iOS"
        WEB = "web", "Web"

    class Provider(models.TextChoices):
        FCM = "fcm", "Firebase Cloud Messaging"
        APNS = "apns", "Apple Push Notification Service"
        WEB_PUSH = "web_push", "Web Push"

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="devices",
    )
    platform = models.CharField(max_length=16, choices=Platform.choices)
    provider = models.CharField(max_length=16, choices=Provider.choices)
    token = models.TextField(unique=True)
    device_id = models.CharField(max_length=180, blank=True)
    enabled = models.BooleanField(default=True)
    last_seen_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ("-last_seen_at", "-created_at")

    def __str__(self) -> str:
        return f"{self.user.email}: {self.platform}"


class Notification(UUIDTimeStampedModel):
    class Status(models.TextChoices):
        PENDING = "pending", "Pendente"
        SENT = "sent", "Enviada"
        FAILED = "failed", "Falhou"
        OPENED = "opened", "Aberta"

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="notifications",
    )
    alert_event = models.ForeignKey(
        AlertEvent,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="notifications",
    )
    type = models.CharField(max_length=40)
    title = models.CharField(max_length=180)
    body = models.TextField()
    payload = models.JSONField(default=dict, blank=True)
    status = models.CharField(max_length=16, choices=Status.choices, default=Status.PENDING)
    sent_at = models.DateTimeField(null=True, blank=True)
    opened_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ("-created_at",)
        indexes = [models.Index(fields=("user", "status"))]
        constraints = [
            models.UniqueConstraint(
                fields=("alert_event", "type"),
                condition=models.Q(alert_event__isnull=False),
                name="notification_unique_type_per_alert_event",
            )
        ]

    def __str__(self) -> str:
        return self.title
