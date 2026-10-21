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
        verbose_name="usuário",
    )
    market = models.ForeignKey(
        Market, on_delete=models.CASCADE, related_name="alerts", verbose_name="mercado"
    )
    name = models.CharField("nome", max_length=120)
    status = models.CharField(
        "status", max_length=16, choices=Status.choices, default=Status.ACTIVE
    )
    logic = models.CharField("lógica", max_length=3, choices=Logic.choices, default=Logic.AND)
    cooldown_seconds = models.PositiveIntegerField("intervalo mínimo (segundos)", default=300)
    last_triggered_at = models.DateTimeField("último disparo em", null=True, blank=True)

    class Meta:
        verbose_name = "alerta"
        verbose_name_plural = "alertas"
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

    alert = models.ForeignKey(
        Alert, on_delete=models.CASCADE, related_name="conditions", verbose_name="alerta"
    )
    condition_type = models.CharField("tipo de condição", max_length=32, choices=Type.choices)
    operator = models.CharField("operador", max_length=4, choices=Operator.choices)
    value_numeric = models.DecimalField("valor numérico", max_digits=28, decimal_places=12)
    window_seconds = models.PositiveIntegerField("janela (segundos)", null=True, blank=True)
    metadata = models.JSONField("metadados", default=dict, blank=True)
    position = models.PositiveIntegerField("posição", default=0)

    class Meta:
        verbose_name = "condição de alerta"
        verbose_name_plural = "condições de alerta"
        ordering = ("position", "created_at")

    def __str__(self) -> str:
        return f"{self.alert}: {self.condition_type}"


class AlertEvent(UUIDTimeStampedModel):
    class NotificationStatus(models.TextChoices):
        PENDING = "pending", "Pendente"
        QUEUED = "queued", "Na fila"
        SENT = "sent", "Enviada"
        FAILED = "failed", "Falhou"

    alert = models.ForeignKey(
        Alert, on_delete=models.CASCADE, related_name="events", verbose_name="alerta"
    )
    source_event_id = models.CharField("ID do evento de origem", max_length=64, blank=True)
    market = models.ForeignKey(
        Market, on_delete=models.CASCADE, related_name="alert_events", verbose_name="mercado"
    )
    observed_value = models.DecimalField("valor observado", max_digits=28, decimal_places=12)
    context = models.JSONField("contexto", default=dict, blank=True)
    triggered_at = models.DateTimeField("disparado em")
    notification_status = models.CharField(
        max_length=16,
        choices=NotificationStatus.choices,
        default=NotificationStatus.PENDING,
        verbose_name="status da notificação",
    )

    class Meta:
        verbose_name = "evento de alerta"
        verbose_name_plural = "eventos de alerta"
        ordering = ("-triggered_at",)
        indexes = [models.Index(fields=("alert", "triggered_at"))]
        constraints = [
            models.UniqueConstraint(
                fields=("alert", "source_event_id"),
                condition=~models.Q(source_event_id=""),
                name="alert_event_unique_source_per_alert",
            )
        ]

    def __str__(self) -> str:
        return f"{self.alert} em {self.triggered_at.isoformat()}"
