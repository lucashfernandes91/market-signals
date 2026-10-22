from django.core.management import call_command
from django.test import TestCase

from apps.market.management.commands.run_market_ingestor import load_subscriptions
from apps.market.models import Asset, Market, ProviderMarket


class SeedMarketTests(TestCase):
    def test_seed_is_idempotent(self):
        call_command("seed_market", verbosity=0)
        call_command("seed_market", verbosity=0)

        self.assertEqual(Asset.objects.count(), 23)
        self.assertEqual(Market.objects.count(), 20)
        self.assertEqual(ProviderMarket.objects.filter(provider="binance").count(), 20)
        self.assertFalse(ProviderMarket.objects.exclude(provider="binance").exists())

    def test_subscription_load_reflects_new_active_binance_listing(self):
        btc = Asset.objects.create(
            symbol="BTC", name="Bitcoin", slug="bitcoin", asset_type=Asset.Type.CRYPTO
        )
        usdt = Asset.objects.create(
            symbol="USDT", name="Tether", slug="tether", asset_type=Asset.Type.CRYPTO
        )
        first = Market.objects.create(
            base_asset=btc,
            quote_asset=usdt,
            canonical_symbol="BTC-USDT",
        )
        ProviderMarket.objects.create(provider="binance", market=first, external_symbol="BTCUSDT")
        self.assertEqual(len(load_subscriptions("binance")), 1)

        eth = Asset.objects.create(
            symbol="ETH", name="Ethereum", slug="ethereum", asset_type=Asset.Type.CRYPTO
        )
        second = Market.objects.create(
            base_asset=eth,
            quote_asset=usdt,
            canonical_symbol="ETH-USDT",
        )
        ProviderMarket.objects.create(provider="binance", market=second, external_symbol="ETHUSDT")

        self.assertEqual(
            {item.symbol for item in load_subscriptions("binance")},
            {"BTC-USDT", "ETH-USDT"},
        )
