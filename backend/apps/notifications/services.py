from uuid import UUID

from django.db import transaction
from django.utils import timezone

from apps.alerts.models import AlertEvent

from .models import Notification


@transaction.atomic
def prepare_notification(*, alert_event_id: str) -> Notification:
    event = AlertEvent.objects.select_related("alert", "alert__user", "market").get(
        id=UUID(alert_event_id)
    )
    notification, _ = Notification.objects.get_or_create(
        alert_event=event,
        user=event.alert.user,
        type="market_alert",
        defaults={
            "title": event.alert.name,
            "body": f"{event.market.canonical_symbol}: {event.observed_value}",
            "payload": {"alert_event_id": str(event.id)},
        },
    )
    return notification


def mark_notification_sent(*, notification: Notification) -> None:
    notification.status = Notification.Status.SENT
    notification.sent_at = timezone.now()
    notification.save(update_fields=("status", "sent_at", "updated_at"))
