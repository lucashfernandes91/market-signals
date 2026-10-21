from django.db import models

from apps.common.models import UUIDTimeStampedModel


class Asset(UUIDTimeStampedModel):
    class Type(models.TextChoices):
        CRYPTO = "crypto", "Criptomoeda"
        FIAT = "fiat", "Moeda fiduciária"

    symbol = models.CharField("símbolo", max_length=16, unique=True)
    name = models.CharField("nome", max_length=120)
    slug = models.SlugField("slug", max_length=120, unique=True)
    asset_type = models.CharField("tipo de ativo", max_length=16, choices=Type.choices)
    is_active = models.BooleanField("ativo", default=True)

    class Meta:
        verbose_name = "ativo"
        verbose_name_plural = "ativos"
        ordering = ("symbol",)

    def __str__(self) -> str:
        return self.symbol


class Market(UUIDTimeStampedModel):
    base_asset = models.ForeignKey(
        Asset, on_delete=models.PROTECT, related_name="base_markets", verbose_name="ativo base"
    )
    quote_asset = models.ForeignKey(
        Asset,
        on_delete=models.PROTECT,
        related_name="quote_markets",
        verbose_name="ativo de cotação",
    )
    canonical_symbol = models.CharField("símbolo canônico", max_length=40, unique=True)
    is_active = models.BooleanField("ativo", default=True)

    class Meta:
        verbose_name = "mercado"
        verbose_name_plural = "mercados"
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
    provider = models.CharField("provedor", max_length=32)
    market = models.ForeignKey(
        Market, on_delete=models.CASCADE, related_name="provider_markets", verbose_name="mercado"
    )
    external_symbol = models.CharField("símbolo externo", max_length=80)
    metadata = models.JSONField("metadados", default=dict, blank=True)
    is_active = models.BooleanField("ativo", default=True)

    class Meta:
        verbose_name = "mercado do provedor"
        verbose_name_plural = "mercados dos provedores"
        ordering = ("provider", "external_symbol")
        constraints = [
            models.UniqueConstraint(
                fields=("provider", "external_symbol"),
                name="provider_market_unique_external_symbol",
            )
        ]

    def __str__(self) -> str:
        return f"{self.provider}:{self.external_symbol}"
