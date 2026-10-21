from unittest.mock import patch

from django.test import SimpleTestCase

from apps.notifications.providers import (
    FcmNotificationProvider,
    StubNotificationProvider,
    build_notification_provider,
)


class NotificationProviderTests(SimpleTestCase):
    @patch.dict("os.environ", {"NOTIFICATION_PROVIDER": "stub"}, clear=False)
    def test_stub_is_default_for_dev(self):
        self.assertIsInstance(build_notification_provider(), StubNotificationProvider)

    @patch.dict("os.environ", {"NOTIFICATION_PROVIDER": "fcm"}, clear=False)
    def test_fcm_provider_is_selectable(self):
        self.assertIsInstance(build_notification_provider(), FcmNotificationProvider)

    @patch.dict("os.environ", {"NOTIFICATION_PROVIDER": "unknown"}, clear=False)
    def test_unknown_provider_fails_fast(self):
        with self.assertRaises(ValueError):
            build_notification_provider()
