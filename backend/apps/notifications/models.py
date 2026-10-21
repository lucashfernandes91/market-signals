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
        verbose_name="usuário",
    )
    platform = models.CharField("plataforma", max_length=16, choices=Platform.choices)
    provider = models.CharField("provedor", max_length=16, choices=Provider.choices)
    token = models.TextField("token", unique=True)
    device_id = models.CharField("ID do dispositivo", max_length=180, blank=True)
    enabled = models.BooleanField("habilitado", default=True)
    last_seen_at = models.DateTimeField("visto pela última vez em", null=True, blank=True)

    class Meta:
        verbose_name = "dispositivo"
        verbose_name_plural = "dispositivos"
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
        verbose_name="usuário",
    )
    alert_event = models.ForeignKey(
        AlertEvent,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="notifications",
        verbose_name="evento de alerta",
    )
    type = models.CharField("tipo", max_length=40)
    title = models.CharField("título", max_length=180)
    body = models.TextField("corpo")
    payload = models.JSONField("dados", default=dict, blank=True)
    status = models.CharField(
        "status", max_length=16, choices=Status.choices, default=Status.PENDING
    )
    sent_at = models.DateTimeField("enviada em", null=True, blank=True)
    opened_at = models.DateTimeField("aberta em", null=True, blank=True)

    class Meta:
        verbose_name = "notificação"
        verbose_name_plural = "notificações"
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
