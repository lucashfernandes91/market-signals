from django.core.management import call_command
from django.test import TestCase

from apps.market.models import Asset, Market, ProviderMarket


class SeedMarketTests(TestCase):
    def test_seed_is_idempotent(self):
        call_command("seed_market", verbosity=0)
        call_command("seed_market", verbosity=0)

        self.assertEqual(Asset.objects.count(), 6)
        self.assertEqual(Market.objects.count(), 3)
        self.assertEqual(ProviderMarket.objects.filter(provider="stub").count(), 3)
