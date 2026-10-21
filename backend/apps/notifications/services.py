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
            "payload": {
                "type": "market_alert",
                "alert_event_id": str(event.id),
                "market_id": str(event.market_id),
            },
        },
    )
    payload = {
        "type": "market_alert",
        "notification_id": str(notification.id),
        "alert_event_id": str(event.id),
        "market_id": str(event.market_id),
    }
    if notification.payload != payload:
        notification.payload = payload
        notification.save(update_fields=("payload", "updated_at"))
    return notification


@transaction.atomic
def mark_notification_sent(*, notification: Notification) -> None:
    notification.status = Notification.Status.SENT
    notification.sent_at = timezone.now()
    notification.save(update_fields=("status", "sent_at", "updated_at"))
    if notification.alert_event_id:
        AlertEvent.objects.filter(id=notification.alert_event_id).update(
            notification_status=AlertEvent.NotificationStatus.SENT
        )


@transaction.atomic
def mark_notification_failed(*, alert_event_id: str) -> None:
    event_id = UUID(alert_event_id)
    Notification.objects.filter(alert_event_id=event_id).exclude(
        status=Notification.Status.SENT
    ).update(status=Notification.Status.FAILED)
    AlertEvent.objects.filter(id=event_id).exclude(
        notification_status=AlertEvent.NotificationStatus.SENT
    ).update(notification_status=AlertEvent.NotificationStatus.FAILED)
