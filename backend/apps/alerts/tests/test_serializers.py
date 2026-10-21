from uuid import uuid4

from django.test import SimpleTestCase

from apps.alerts.serializers import AlertSerializer


class AlertSerializerTests(SimpleTestCase):
    def _data(self, condition_type, window_seconds=None):
        return {
            "market_id": str(uuid4()),
            "name": "Alerta de teste",
            "conditions": [
                {
                    "condition_type": condition_type,
                    "operator": "gt",
                    "value_numeric": "5",
                    **({} if window_seconds is None else {"window_seconds": window_seconds}),
                }
            ],
        }

    def test_percent_condition_requires_positive_window(self):
        serializer = AlertSerializer(data=self._data("PRICE_CHANGE_PERCENT"))

        self.assertFalse(serializer.is_valid())
        self.assertIn("conditions", serializer.errors)

    def test_price_condition_rejects_window(self):
        serializer = AlertSerializer(data=self._data("PRICE_ABOVE", 300))

        self.assertFalse(serializer.is_valid())
        self.assertIn("conditions", serializer.errors)

    def test_percent_condition_accepts_positive_window(self):
        serializer = AlertSerializer(data=self._data("VOLUME_CHANGE_PERCENT", 3600))

        self.assertTrue(serializer.is_valid(), serializer.errors)