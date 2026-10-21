import uuid
from typing import ClassVar

from django.contrib.auth.models import AbstractUser
from django.db import models
from django.db.models.functions import Lower

from .managers import UserManager


class User(AbstractUser):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    username = None  # type: ignore[assignment]
    email = models.EmailField("e-mail", unique=True)
    created_at = models.DateTimeField("criado em", auto_now_add=True)
    updated_at = models.DateTimeField("atualizado em", auto_now=True)

    USERNAME_FIELD = "email"
    REQUIRED_FIELDS: ClassVar[list[str]] = []

    objects = UserManager()  # type: ignore[misc,assignment]

    class Meta(AbstractUser.Meta):
        verbose_name = "usuário"
        verbose_name_plural = "usuários"
        constraints = [
            models.UniqueConstraint(Lower("email"), name="user_email_case_insensitive_unique")
        ]

    def __str__(self) -> str:
        return self.email


class UserPreference(models.Model):
    class MonitoringProfile(models.TextChoices):
        CONSERVATIVE = "conservative", "Conservador"
        TRADER = "trader", "Trader"
        HIGH_VOLATILITY = "high_volatility", "Alta volatilidade"
        LONG_TERM = "long_term", "Longo prazo"
        CUSTOM = "custom", "Personalizado"

    class Theme(models.TextChoices):
        SYSTEM = "system", "Sistema"
        LIGHT = "light", "Claro"
        DARK = "dark", "Escuro"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.OneToOneField(
        User, on_delete=models.CASCADE, related_name="preference", verbose_name="usuário"
    )
    fiat_currency = models.CharField("moeda fiduciária", max_length=8, default="BRL")
    timezone = models.CharField("fuso horário", max_length=64, default="America/Sao_Paulo")
    monitoring_profile = models.CharField(
        max_length=32,
        choices=MonitoringProfile.choices,
        default=MonitoringProfile.CONSERVATIVE,
        verbose_name="perfil de acompanhamento",
    )
    theme = models.CharField("tema", max_length=16, choices=Theme.choices, default=Theme.SYSTEM)
    created_at = models.DateTimeField("criado em", auto_now_add=True)
    updated_at = models.DateTimeField("atualizado em", auto_now=True)

    class Meta:
        verbose_name = "preferência do usuário"
        verbose_name_plural = "preferências dos usuários"

    def __str__(self) -> str:
        return f"Preferências de {self.user.email}"
