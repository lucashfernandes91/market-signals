from unittest.mock import Mock, patch

from django.db import connection
from django.test import TestCase
from django.urls import reverse
from redis.exceptions import ConnectionError as RedisConnectionError


class HealthEndpointTests(TestCase):
    def test_live(self):
        response = self.client.get(reverse("health-live"))

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {"status": "ok"})

    def test_request_id_is_returned(self):
        response = self.client.get(reverse("health-live"), HTTP_X_REQUEST_ID="dev-check-123")
        self.assertEqual(response["X-Request-ID"], "dev-check-123")

    def test_invalid_request_id_is_replaced(self):
        response = self.client.get(reverse("health-live"), HTTP_X_REQUEST_ID="invalid\nvalue")
        self.assertNotEqual(response["X-Request-ID"], "invalid\nvalue")
        self.assertEqual(len(response["X-Request-ID"]), 32)

    @patch("core.views.get_redis_client")
    def test_ready(self, get_redis_client):
        get_redis_client.return_value = Mock()
        response = self.client.get(reverse("health-ready"))

        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            response.json(),
            {"status": "ok", "database": "ok", "redis": "ok"},
        )

    @patch("core.views.get_redis_client")
    def test_ready_returns_503_when_redis_is_unavailable(self, get_redis_client):
        get_redis_client.return_value.ping.side_effect = RedisConnectionError()

        response = self.client.get(reverse("health-ready"))

        self.assertEqual(response.status_code, 503)
        self.assertEqual(response.json(), {"status": "unavailable"})

    def test_sqlite_connection_pragmas(self):
        with connection.cursor() as cursor:
            cursor.execute("PRAGMA foreign_keys")
            foreign_keys = cursor.fetchone()[0]
            cursor.execute("PRAGMA busy_timeout")
            busy_timeout = cursor.fetchone()[0]

        self.assertEqual(foreign_keys, 1)
        self.assertEqual(busy_timeout, 20_000)
