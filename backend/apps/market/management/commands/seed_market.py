from django.core.management.base import BaseCommand
from django.db import transaction

from apps.market.models import Asset, Market, ProviderMarket

ASSETS = (
    ("BTC", "Bitcoin", "bitcoin", Asset.Type.CRYPTO),
    ("ETH", "Ethereum", "ethereum", Asset.Type.CRYPTO),
    ("BNB", "BNB", "bnb", Asset.Type.CRYPTO),
    ("SOL", "Solana", "solana", Asset.Type.CRYPTO),
    ("XRP", "XRP", "xrp", Asset.Type.CRYPTO),
    ("DOGE", "Dogecoin", "dogecoin", Asset.Type.CRYPTO),
    ("ADA", "Cardano", "cardano", Asset.Type.CRYPTO),
    ("AVAX", "Avalanche", "avalanche", Asset.Type.CRYPTO),
    ("LINK", "Chainlink", "chainlink", Asset.Type.CRYPTO),
    ("DOT", "Polkadot", "polkadot", Asset.Type.CRYPTO),
    ("TRX", "TRON", "tron", Asset.Type.CRYPTO),
    ("LTC", "Litecoin", "litecoin", Asset.Type.CRYPTO),
    ("BCH", "Bitcoin Cash", "bitcoin-cash", Asset.Type.CRYPTO),
    ("NEAR", "NEAR Protocol", "near-protocol", Asset.Type.CRYPTO),
    ("APT", "Aptos", "aptos", Asset.Type.CRYPTO),
    ("UNI", "Uniswap", "uniswap", Asset.Type.CRYPTO),
    ("SHIB", "Shiba Inu", "shiba-inu", Asset.Type.CRYPTO),
    ("PEPE", "Pepe", "pepe", Asset.Type.CRYPTO),
    ("ARB", "Arbitrum", "arbitrum", Asset.Type.CRYPTO),
    ("OP", "Optimism", "optimism", Asset.Type.CRYPTO),
    ("USDT", "Tether", "tether", Asset.Type.CRYPTO),
    ("USD", "US Dollar", "us-dollar", Asset.Type.FIAT),
    ("BRL", "Real Brasileiro", "real-brasileiro", Asset.Type.FIAT),
)

MARKETS = (
    ("BTC", "USDT", "BTC-USDT", "BTCUSDT"),
    ("ETH", "USDT", "ETH-USDT", "ETHUSDT"),
    ("BNB", "USDT", "BNB-USDT", "BNBUSDT"),
    ("SOL", "USDT", "SOL-USDT", "SOLUSDT"),
    ("XRP", "USDT", "XRP-USDT", "XRPUSDT"),
    ("DOGE", "USDT", "DOGE-USDT", "DOGEUSDT"),
    ("ADA", "USDT", "ADA-USDT", "ADAUSDT"),
    ("AVAX", "USDT", "AVAX-USDT", "AVAXUSDT"),
    ("LINK", "USDT", "LINK-USDT", "LINKUSDT"),
    ("DOT", "USDT", "DOT-USDT", "DOTUSDT"),
    ("TRX", "USDT", "TRX-USDT", "TRXUSDT"),
    ("LTC", "USDT", "LTC-USDT", "LTCUSDT"),
    ("BCH", "USDT", "BCH-USDT", "BCHUSDT"),
    ("NEAR", "USDT", "NEAR-USDT", "NEARUSDT"),
    ("APT", "USDT", "APT-USDT", "APTUSDT"),
    ("UNI", "USDT", "UNI-USDT", "UNIUSDT"),
    ("SHIB", "USDT", "SHIB-USDT", "SHIBUSDT"),
    ("PEPE", "USDT", "PEPE-USDT", "PEPEUSDT"),
    ("ARB", "USDT", "ARB-USDT", "ARBUSDT"),
    ("OP", "USDT", "OP-USDT", "OPUSDT"),
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
                provider="binance",
                external_symbol=external_symbol,
                defaults={"market": market, "is_active": True},
            )

        self.stdout.write(self.style.SUCCESS("Mercado inicial configurado."))
