from django.contrib import admin
from django.test import TestCase
from django.urls import reverse

from apps.alerts.models import Alert
from apps.market.models import Asset
from apps.users.models import User


class AdminSmokeTests(TestCase):
    def test_superuser_can_open_admin_and_models_are_registered(self):
        superuser = User.objects.create_superuser(
            email="admin@example.com", password="test-password-123"
        )
        self.client.force_login(superuser)

        response = self.client.get(reverse("admin:index"))

        self.assertEqual(response.status_code, 200)
        self.assertIn(Alert, admin.site._registry)
        self.assertIn(Asset, admin.site._registry)
