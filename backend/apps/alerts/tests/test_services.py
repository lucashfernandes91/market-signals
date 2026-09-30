from django.test import TestCase

from apps.alerts.models import Alert, AlertCondition, AlertEvent
from apps.alerts.services import process_market_event
from apps.market.models import Asset, Market
from apps.notifications.models import Notification
from apps.notifications.services import mark_notification_sent, prepare_notification
from apps.users.models import User


class AlertPipelineServiceTests(TestCase):
    def setUp(self):
        user = User.objects.create_user(email="alert@example.com", password="password")
        btc = Asset.objects.create(
            symbol="BTC",
            name="Bitcoin",
            slug="bitcoin",
            asset_type=Asset.Type.CRYPTO,
        )
        usdt = Asset.objects.create(
            symbol="USDT",
            name="Tether",
            slug="tether",
            asset_type=Asset.Type.CRYPTO,
        )
        self.market = Market.objects.create(
            base_asset=btc,
            quote_asset=usdt,
            canonical_symbol="BTC-USDT",
        )
        self.alert = Alert.objects.create(
            user=user,
            market=self.market,
            name="BTC acima de 70 mil",
            cooldown_seconds=300,
        )
        AlertCondition.objects.create(
            alert=self.alert,
            condition_type=AlertCondition.Type.PRICE_ABOVE,
            operator=AlertCondition.Operator.GREATER_THAN,
            value_numeric="70000",
        )

    def test_event_to_notification_pipeline(self):
        payload = {
            "market_id": str(self.market.id),
            "symbol": "BTC-USDT",
            "price": "70001",
            "volume_24h": "1000000",
            "timestamp": "2026-09-30T12:00:00+00:00",
        }

        events = process_market_event(payload=payload)

        self.assertEqual(len(events), 1)
        self.assertEqual(events[0].notification_status, AlertEvent.NotificationStatus.QUEUED)

        notification = prepare_notification(alert_event_id=str(events[0].id))
        mark_notification_sent(notification=notification)
        notification.refresh_from_db()

        self.assertEqual(notification.status, Notification.Status.SENT)
        self.assertIsNotNone(notification.sent_at)

    def test_cooldown_prevents_repeated_event(self):
        payload = {
            "market_id": str(self.market.id),
            "symbol": "BTC-USDT",
            "price": "70001",
        }

        first_events = process_market_event(payload=payload)
        second_events = process_market_event(payload=payload)

        self.assertEqual(len(first_events), 1)
        self.assertEqual(second_events, [])

    def test_replayed_stream_message_reuses_existing_event(self):
        self.alert.cooldown_seconds = 0
        self.alert.save(update_fields=("cooldown_seconds",))
        payload = {"market_id": str(self.market.id), "price": "70001"}

        first = process_market_event(payload=payload, source_event_id="123-0")
        replayed = process_market_event(payload=payload, source_event_id="123-0")

        self.assertEqual([event.id for event in first], [event.id for event in replayed])
        self.assertEqual(AlertEvent.objects.count(), 1)

    def test_empty_candidate_index_skips_alerts(self):
        payload = {"market_id": str(self.market.id), "price": "70001"}

        events = process_market_event(payload=payload, candidate_ids=set())

        self.assertEqual(events, [])
        self.assertEqual(AlertEvent.objects.count(), 0)
