from django.db import models

from apps.common.models import UUIDTimeStampedModel


class Asset(UUIDTimeStampedModel):
    class Type(models.TextChoices):
        CRYPTO = "crypto", "Criptomoeda"
        FIAT = "fiat", "Moeda fiduciária"

    symbol = models.CharField(max_length=16, unique=True)
    name = models.CharField(max_length=120)
    slug = models.SlugField(max_length=120, unique=True)
    asset_type = models.CharField(max_length=16, choices=Type.choices)
    is_active = models.BooleanField(default=True)

    class Meta:
        ordering = ("symbol",)

    def __str__(self) -> str:
        return self.symbol


class Market(UUIDTimeStampedModel):
    base_asset = models.ForeignKey(Asset, on_delete=models.PROTECT, related_name="base_markets")
    quote_asset = models.ForeignKey(Asset, on_delete=models.PROTECT, related_name="quote_markets")
    canonical_symbol = models.CharField(max_length=40, unique=True)
    is_active = models.BooleanField(default=True)

    class Meta:
        ordering = ("canonical_symbol",)
        constraints = [
            models.UniqueConstraint(
                fields=("base_asset", "quote_asset"),
                name="market_unique_asset_pair",
            ),
            models.CheckConstraint(
                condition=~models.Q(base_asset=models.F("quote_asset")),
                name="market_assets_must_differ",
            ),
        ]

    def __str__(self) -> str:
        return self.canonical_symbol


class ProviderMarket(UUIDTimeStampedModel):
    provider = models.CharField(max_length=32)
    market = models.ForeignKey(Market, on_delete=models.CASCADE, related_name="provider_markets")
    external_symbol = models.CharField(max_length=80)
    metadata = models.JSONField(default=dict, blank=True)
    is_active = models.BooleanField(default=True)

    class Meta:
        ordering = ("provider", "external_symbol")
        constraints = [
            models.UniqueConstraint(
                fields=("provider", "external_symbol"),
                name="provider_market_unique_external_symbol",
            )
        ]

    def __str__(self) -> str:
        return f"{self.provider}:{self.external_symbol}"
