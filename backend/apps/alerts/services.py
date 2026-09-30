from datetime import timedelta
from decimal import Decimal
from uuid import UUID

from django.db import transaction
from django.utils import timezone

from .evaluator import evaluate_alert
from .models import Alert, AlertEvent


@transaction.atomic
def process_market_event(*, payload: dict[str, str]) -> list[AlertEvent]:
    market_id = UUID(payload["market_id"])
    now = timezone.now()
    alerts = Alert.objects.filter(
        market_id=market_id,
        status=Alert.Status.ACTIVE,
    ).prefetch_related("conditions")

    triggered_events = []
    for alert in alerts:
        if alert.last_triggered_at is not None:
            cooldown_until = alert.last_triggered_at + timedelta(seconds=alert.cooldown_seconds)
            if cooldown_until > now:
                continue

        if not evaluate_alert(
            logic=alert.logic,
            conditions=alert.conditions.all(),
            market_data=payload,
        ):
            continue

        event = AlertEvent.objects.create(
            alert=alert,
            market_id=market_id,
            observed_value=Decimal(payload["price"]),
            context=payload,
            triggered_at=now,
            notification_status=AlertEvent.NotificationStatus.QUEUED,
        )
        alert.last_triggered_at = now
        alert.save(update_fields=("last_triggered_at", "updated_at"))
        triggered_events.append(event)

    return triggered_events
