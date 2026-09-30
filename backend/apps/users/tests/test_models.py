from django.contrib.auth import get_user_model
from django.db import IntegrityError, transaction
from django.test import TestCase


class UserModelTests(TestCase):
    def test_create_user_with_email(self):
        user = get_user_model().objects.create_user(
            email="user@example.com",
            password="a-safe-test-password",
        )

        self.assertEqual(user.email, "user@example.com")
        self.assertTrue(user.check_password("a-safe-test-password"))
        self.assertFalse(user.is_staff)

    def test_email_is_unique(self):
        user_model = get_user_model()
        user_model.objects.create_user(email="user@example.com", password="password")

        with self.assertRaises(IntegrityError), transaction.atomic():
            user_model.objects.create_user(email="user@example.com", password="password")
