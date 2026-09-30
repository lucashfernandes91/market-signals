from django.conf import settings
from django.db import models

from apps.common.models import UUIDTimeStampedModel
from apps.market.models import Market


class Alert(UUIDTimeStampedModel):
    class Status(models.TextChoices):
        ACTIVE = "active", "Ativo"
        PAUSED = "paused", "Pausado"
        DISABLED = "disabled", "Desabilitado"

    class Logic(models.TextChoices):
        AND = "AND", "E"
        OR = "OR", "OU"

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="alerts",
    )
    market = models.ForeignKey(Market, on_delete=models.CASCADE, related_name="alerts")
    name = models.CharField(max_length=120)
    status = models.CharField(max_length=16, choices=Status.choices, default=Status.ACTIVE)
    logic = models.CharField(max_length=3, choices=Logic.choices, default=Logic.AND)
    cooldown_seconds = models.PositiveIntegerField(default=300)
    last_triggered_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ("-created_at",)
        indexes = [models.Index(fields=("market", "status"))]

    def __str__(self) -> str:
        return self.name


class AlertCondition(UUIDTimeStampedModel):
    class Type(models.TextChoices):
        PRICE_ABOVE = "PRICE_ABOVE", "Preço acima"
        PRICE_BELOW = "PRICE_BELOW", "Preço abaixo"
        PRICE_CHANGE_PERCENT = "PRICE_CHANGE_PERCENT", "Variação de preço (%)"
        VOLUME_CHANGE_PERCENT = "VOLUME_CHANGE_PERCENT", "Variação de volume (%)"

    class Operator(models.TextChoices):
        GREATER_THAN = "gt", ">"
        GREATER_THAN_OR_EQUAL = "gte", ">="
        LESS_THAN = "lt", "<"
        LESS_THAN_OR_EQUAL = "lte", "<="

    alert = models.ForeignKey(Alert, on_delete=models.CASCADE, related_name="conditions")
    condition_type = models.CharField(max_length=32, choices=Type.choices)
    operator = models.CharField(max_length=4, choices=Operator.choices)
    value_numeric = models.DecimalField(max_digits=28, decimal_places=12)
    window_seconds = models.PositiveIntegerField(null=True, blank=True)
    metadata = models.JSONField(default=dict, blank=True)
    position = models.PositiveIntegerField(default=0)

    class Meta:
        ordering = ("position", "created_at")

    def __str__(self) -> str:
        return f"{self.alert}: {self.condition_type}"


class AlertEvent(UUIDTimeStampedModel):
    class NotificationStatus(models.TextChoices):
        PENDING = "pending", "Pendente"
        QUEUED = "queued", "Na fila"
        SENT = "sent", "Enviada"
        FAILED = "failed", "Falhou"

    alert = models.ForeignKey(Alert, on_delete=models.CASCADE, related_name="events")
    market = models.ForeignKey(Market, on_delete=models.CASCADE, related_name="alert_events")
    observed_value = models.DecimalField(max_digits=28, decimal_places=12)
    context = models.JSONField(default=dict, blank=True)
    triggered_at = models.DateTimeField()
    notification_status = models.CharField(
        max_length=16,
        choices=NotificationStatus.choices,
        default=NotificationStatus.PENDING,
    )

    class Meta:
        ordering = ("-triggered_at",)
        indexes = [models.Index(fields=("alert", "triggered_at"))]

    def __str__(self) -> str:
        return f"{self.alert} em {self.triggered_at.isoformat()}"
