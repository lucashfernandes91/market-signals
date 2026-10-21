from django.contrib.auth.password_validation import validate_password
from django.db import IntegrityError
from rest_framework import serializers

from .models import User, UserPreference
from .services import user_create


class UserSerializer(serializers.ModelSerializer):
    class Meta:
        model = User
        fields = ("id", "email", "first_name", "last_name", "date_joined")
        read_only_fields = fields


class UserPreferenceSerializer(serializers.ModelSerializer):
    fiat_currency = serializers.ChoiceField(choices=("BRL", "USD"))

    class Meta:
        model = UserPreference
        fields = ("fiat_currency", "timezone", "monitoring_profile", "theme", "updated_at")
        read_only_fields = ("updated_at",)


class RegisterSerializer(serializers.ModelSerializer):
    password = serializers.CharField(write_only=True, trim_whitespace=False)

    class Meta:
        model = User
        fields = ("email", "password", "first_name", "last_name")

    def validate_password(self, value: str) -> str:
        validate_password(value)
        return value

    def validate_email(self, value: str) -> str:
        normalized = value.strip().lower()
        if User.objects.filter(email__iexact=normalized).exists():
            raise serializers.ValidationError("Já existe uma conta com este e-mail.")
        return normalized

    def create(self, validated_data: dict) -> User:
        try:
            return user_create(**validated_data)
        except IntegrityError as exc:
            raise serializers.ValidationError(
                {"email": "Já existe uma conta com este e-mail."}
            ) from exc
