from collections.abc import Collection, Mapping, Sequence
from datetime import timedelta
from decimal import Decimal
from uuid import UUID

from django.db import transaction
from django.utils import timezone

from .evaluator import evaluate_alert, observed_value_for_condition
from .models import Alert, AlertCondition, AlertEvent


@transaction.atomic
def process_market_event(
    *,
    payload: dict[str, str],
    source_event_id: str = "",
    candidate_ids: Collection[str] | None = None,
    history: Sequence[Mapping[str, str]] = (),
) -> list[AlertEvent]:
    market_id = UUID(payload["market_id"])
    now = timezone.now()
    alerts = Alert.objects.filter(
        market_id=market_id,
        status=Alert.Status.ACTIVE,
    )
    if candidate_ids is not None:
        if not candidate_ids:
            return []
        alerts = alerts.filter(id__in=candidate_ids)
    alerts = alerts.prefetch_related("conditions")

    triggered_events = []
    for alert in alerts:
        if source_event_id:
            existing = AlertEvent.objects.filter(
                alert=alert, source_event_id=source_event_id
            ).first()
            if existing is not None:
                triggered_events.append(existing)
                continue
        if alert.last_triggered_at is not None:
            cooldown_until = alert.last_triggered_at + timedelta(seconds=alert.cooldown_seconds)
            if cooldown_until > now:
                continue

        conditions = list(alert.conditions.all())
        if not evaluate_alert(
            logic=alert.logic,
            conditions=conditions,
            market_data=payload,
            history=history,
        ):
            continue

        context = dict(payload)
        metrics = {}
        for condition in conditions:
            if condition.condition_type in (
                AlertCondition.Type.PRICE_CHANGE_PERCENT,
                AlertCondition.Type.VOLUME_CHANGE_PERCENT,
            ):
                observed = observed_value_for_condition(condition, payload, history)
                if observed is not None:
                    metrics[f"{condition.condition_type}:{condition.window_seconds or 3600}"] = str(
                        observed
                    )
        context["alert_metrics"] = metrics
        event_fields = {
            "market_id": market_id,
            "observed_value": Decimal(payload["price"]),
            "context": context,
            "triggered_at": now,
            "notification_status": AlertEvent.NotificationStatus.QUEUED,
        }
        if source_event_id:
            event, created = AlertEvent.objects.get_or_create(
                alert=alert,
                source_event_id=source_event_id,
                defaults=event_fields,
            )
            if not created:
                triggered_events.append(event)
                continue
        else:
            event = AlertEvent.objects.create(alert=alert, source_event_id="", **event_fields)
        alert.last_triggered_at = now
        alert.save(update_fields=("last_triggered_at", "updated_at"))
        triggered_events.append(event)

    return triggered_events
