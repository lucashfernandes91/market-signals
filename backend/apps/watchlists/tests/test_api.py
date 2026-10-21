from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase

from apps.market.models import Asset, Market
from apps.users.models import User
from apps.watchlists.models import Watchlist, WatchlistItem


class WatchlistApiTests(APITestCase):
    def setUp(self):
        self.user = User.objects.create_user(email="lists@example.com", password="password")
        self.client.force_authenticate(self.user)
        usdt = Asset.objects.create(
            symbol="USDT", name="Tether", slug="tether", asset_type="crypto"
        )
        self.markets = []
        for symbol, name in (("BTC", "Bitcoin"), ("ETH", "Ethereum")):
            asset = Asset.objects.create(
                symbol=symbol, name=name, slug=name.lower(), asset_type="crypto"
            )
            self.markets.append(
                Market.objects.create(
                    base_asset=asset,
                    quote_asset=usdt,
                    canonical_symbol=f"{symbol}-USDT",
                )
            )
        self.watchlist = Watchlist.objects.create(user=self.user, name="Principal")
        for position, market in enumerate(self.markets):
            WatchlistItem.objects.create(
                watchlist=self.watchlist, market=market, position=position
            )

    def test_reorders_all_items(self):
        url = reverse("watchlists:watchlist-order-items", args=(self.watchlist.id,))

        response = self.client.patch(
            url,
            {"market_ids": [str(self.markets[1].id), str(self.markets[0].id)]},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        ordered = [item["market"]["canonical_symbol"] for item in response.data["items"]]
        self.assertEqual(ordered, ["ETH-USDT", "BTC-USDT"])

    def test_adds_multiple_items_idempotently(self):
        extra_asset = Asset.objects.create(
            symbol="SOL", name="Solana", slug="solana", asset_type="crypto"
        )
        extra_market = Market.objects.create(
            base_asset=extra_asset,
            quote_asset=self.markets[0].quote_asset,
            canonical_symbol="SOL-USDT",
        )
        url = reverse("watchlists:watchlist-add-items-batch", args=(self.watchlist.id,))

        first = self.client.post(url, {"market_ids": [str(extra_market.id)]}, format="json")
        second = self.client.post(url, {"market_ids": [str(extra_market.id)]}, format="json")

        self.assertEqual(first.status_code, status.HTTP_200_OK)
        self.assertEqual(second.status_code, status.HTTP_200_OK)
        self.assertEqual(
            WatchlistItem.objects.filter(watchlist=self.watchlist, market=extra_market).count(),
            1,
        )

    def test_copies_list_with_positions(self):
        url = reverse("watchlists:watchlist-copy-watchlist", args=(self.watchlist.id,))

        response = self.client.post(url, {"name": "Cópia"}, format="json")

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        copied = Watchlist.objects.get(name="Cópia")
        self.assertEqual(
            list(copied.items.values_list("market_id", "position")),
            list(self.watchlist.items.values_list("market_id", "position")),
        )
