from django.core.management.base import BaseCommand
from django.db import transaction

from apps.market.models import Asset, Market, ProviderMarket

ASSETS = (
    ("BTC", "Bitcoin", "bitcoin", Asset.Type.CRYPTO),
    ("ETH", "Ethereum", "ethereum", Asset.Type.CRYPTO),
    ("SOL", "Solana", "solana", Asset.Type.CRYPTO),
    ("USDT", "Tether", "tether", Asset.Type.CRYPTO),
    ("USD", "US Dollar", "us-dollar", Asset.Type.FIAT),
    ("BRL", "Real Brasileiro", "real-brasileiro", Asset.Type.FIAT),
)

MARKETS = (
    ("BTC", "USDT", "BTC-USDT", "BTCUSDT"),
    ("ETH", "USDT", "ETH-USDT", "ETHUSDT"),
    ("SOL", "USDT", "SOL-USDT", "SOLUSDT"),
)


class Command(BaseCommand):
    help = "Cria os ativos e mercados iniciais de forma idempotente"

    @transaction.atomic
    def handle(self, *args, **options):
        assets = {}
        for symbol, name, slug, asset_type in ASSETS:
            asset, _ = Asset.objects.update_or_create(
                symbol=symbol,
                defaults={
                    "name": name,
                    "slug": slug,
                    "asset_type": asset_type,
                    "is_active": True,
                },
            )
            assets[symbol] = asset

        for base_symbol, quote_symbol, canonical_symbol, external_symbol in MARKETS:
            market, _ = Market.objects.update_or_create(
                canonical_symbol=canonical_symbol,
                defaults={
                    "base_asset": assets[base_symbol],
                    "quote_asset": assets[quote_symbol],
                    "is_active": True,
                },
            )
            ProviderMarket.objects.update_or_create(
                provider="stub",
                external_symbol=external_symbol,
                defaults={"market": market, "is_active": True},
            )

        self.stdout.write(self.style.SUCCESS("Mercado inicial configurado."))
