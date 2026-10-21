from django.test import TestCase

from apps.market.catalog import CatalogPolicy, sync_catalog
from apps.market.models import Asset, Market, ProviderMarket
from apps.market.providers.models import ProviderCatalogMarket


class CatalogSyncTests(TestCase):
    def test_syncs_allowed_pairs_and_deactivates_suspended_binance_listing(self):
        usdt = Asset.objects.create(
            symbol="USDT", name="Tether", slug="tether", asset_type=Asset.Type.CRYPTO
        )
        sol = Asset.objects.create(
            symbol="SOL", name="Solana", slug="solana", asset_type=Asset.Type.CRYPTO
        )
        suspended_market = Market.objects.create(
            base_asset=sol,
            quote_asset=usdt,
            canonical_symbol="SOL-USDT",
        )
        suspended_listing = ProviderMarket.objects.create(
            provider="binance",
            market=suspended_market,
            external_symbol="SOLUSDT",
        )
        policy = CatalogPolicy(
            quote_assets=frozenset({"USDT"}),
            base_assets=frozenset(),
            excluded_assets=frozenset(),
            max_pairs=None,
        )

        result = sync_catalog(
            provider="binance",
            policy=policy,
            catalog=[
                ProviderCatalogMarket("BTCUSDT", "BTC", "USDT", "TRADING"),
                ProviderCatalogMarket("ETHBTC", "ETH", "BTC", "TRADING"),
                ProviderCatalogMarket("SOLUSDT", "SOL", "USDT", "BREAK"),
            ],
        )

        self.assertEqual(result.discovered, 3)
        self.assertEqual(result.allowed, 1)
        self.assertEqual(result.provider_markets_created, 1)
        self.assertTrue(
            ProviderMarket.objects.filter(external_symbol="BTCUSDT", is_active=True).exists()
        )
        self.assertFalse(ProviderMarket.objects.filter(external_symbol="ETHBTC").exists())
        suspended_listing.refresh_from_db()
        suspended_market.refresh_from_db()
        self.assertFalse(suspended_listing.is_active)
        self.assertFalse(suspended_market.is_active)
