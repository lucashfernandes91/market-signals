from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase

from apps.users.models import User, UserPreference


class AuthenticationApiTests(APITestCase):
    password = "a-strong-test-password-2026"

    def test_register_creates_user_and_preferences(self):
        response = self.client.post(
            reverse("users:register"),
            {
                "email": "New.User@Example.COM",
                "password": self.password,
                "first_name": "New",
                "last_name": "User",
            },
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        user = User.objects.get(email="new.user@example.com")
        self.assertTrue(user.check_password(self.password))
        self.assertTrue(UserPreference.objects.filter(user=user).exists())
        self.assertNotIn("password", response.data)

    def test_token_and_me(self):
        user = User.objects.create_user(email="user@example.com", password=self.password)
        token_response = self.client.post(
            reverse("users:token-obtain-pair"),
            {"email": user.email, "password": self.password},
            format="json",
        )

        self.assertEqual(token_response.status_code, status.HTTP_200_OK)
        self.assertIn("access", token_response.data)
        self.assertIn("refresh", token_response.data)

        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {token_response.data['access']}")
        me_response = self.client.get(reverse("users:me"))

        self.assertEqual(me_response.status_code, status.HTTP_200_OK)
        self.assertEqual(me_response.data["email"], user.email)

    def test_me_requires_authentication(self):
        response = self.client.get(reverse("users:me"))

        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)
        self.assertEqual(response.data["error"]["code"], "request_error")

    def test_duplicate_email_uses_validation_envelope(self):
        User.objects.create_user(email="user@example.com", password=self.password)

        response = self.client.post(
            reverse("users:register"),
            {"email": "USER@example.com", "password": self.password},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data["error"]["code"], "validation_error")
        self.assertIn("email", response.data["error"]["details"])
