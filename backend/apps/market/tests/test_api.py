from datetime import UTC, datetime, timedelta
from decimal import Decimal
from unittest.mock import AsyncMock, Mock, patch

from django.urls import reverse
from redis.exceptions import RedisError
from rest_framework import status
from rest_framework.test import APITestCase

from apps.market.models import Asset, Market, ProviderMarket
from apps.market.providers import MarketCandle
from apps.market.rates import CurrencyRates
from apps.market.views import _read_market_states
from apps.users.models import User
from apps.watchlists.models import Watchlist, WatchlistItem


class MarketApiTests(APITestCase):
    def setUp(self):
        self.user = User.objects.create_user(email="market-api@example.com", password="password")
        self.client.force_authenticate(self.user)
        btc = Asset.objects.create(
            symbol="BTC", name="Bitcoin", slug="bitcoin", asset_type="crypto"
        )
        brl = Asset.objects.create(symbol="BRL", name="Real", slug="real", asset_type="fiat")
        self.market = Market.objects.create(
            base_asset=btc,
            quote_asset=brl,
            canonical_symbol="BTC-BRL",
        )
        ProviderMarket.objects.create(
            provider="binance", market=self.market, external_symbol="BTCBRL"
        )

    def test_market_state_reader_uses_one_pipeline_for_many_markets(self):
        class Pipeline:
            def __init__(self):
                self.keys = []

            def hgetall(self, key):
                self.keys.append(key)

            def execute(self):
                return [{"price": str(index)} for index in range(len(self.keys))]

        class Redis:
            def __init__(self):
                self.batch = Pipeline()

            def pipeline(self, transaction=False):
                return self.batch

            def hgetall(self, key):
                raise AssertionError("fallback Redis call should not be used")

        second = Market.objects.create(
            base_asset=Asset.objects.create(
                symbol="ETH", name="Ethereum", slug="ethereum", asset_type="crypto"
            ),
            quote_asset=self.market.quote_asset,
            canonical_symbol="ETH-BRL",
        )

        states = _read_market_states(Redis(), [self.market.id, second.id])

        self.assertEqual(states[str(self.market.id)]["price"], "0")
        self.assertEqual(states[str(second.id)]["price"], "1")

    def test_lists_active_markets(self):
        response = self.client.get(reverse("market:list"))

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["count"], 1)
        self.assertEqual(response.data["results"][0]["canonical_symbol"], "BTC-BRL")

    def test_lists_active_markets_without_authentication(self):
        self.client.force_authenticate(user=None)

        response = self.client.get(reverse("market:list"))

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["results"][0]["canonical_symbol"], "BTC-BRL")

    def test_lookup_returns_requested_active_markets_only(self):
        inactive = Market.objects.create(
            base_asset=self.market.base_asset,
            quote_asset=Asset.objects.create(
                symbol="USD", name="Dollar", slug="dollar", asset_type="fiat"
            ),
            canonical_symbol="BTC-USD",
            is_active=False,
        )

        response = self.client.get(
            reverse("market:lookup"), {"ids": f"{self.market.id},{inactive.id}"}
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual([item["id"] for item in response.data], [str(self.market.id)])

    @patch("apps.market.views.get_redis_client")
    def test_overview_returns_quote_without_fetching_candles(self, get_redis_client):
        redis = Mock()
        redis.hgetall.return_value = {
            "price": "600000",
            "change_24h_percent": "3.5",
            "volume_24h": "1000",
            "timestamp": "2026-09-30T12:00:00+00:00",
            "stale": "false",
        }
        get_redis_client.return_value = redis

        response = self.client.get(reverse("market:overview"))

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data[0]["market_id"], str(self.market.id))
        self.assertEqual(response.data[0]["change_24h_percent"], "3.5")

    @patch("apps.market.views.get_redis_client")
    def test_overview_filters_and_preserves_requested_market_order(self, get_redis_client):
        eth = Asset.objects.create(
            symbol="ETH", name="Ethereum", slug="ethereum", asset_type="crypto"
        )
        second = Market.objects.create(
            base_asset=eth,
            quote_asset=self.market.quote_asset,
            canonical_symbol="ETH-BRL",
        )
        redis = Mock()
        redis.hgetall.return_value = {
            "price": "100",
            "change_24h_percent": "1.5",
            "volume_24h": "200",
            "timestamp": "2026-10-04T12:00:00+00:00",
            "stale": "false",
        }
        get_redis_client.return_value = redis

        response = self.client.get(
            reverse("market:overview"),
            {"ids": f"{second.id},{self.market.id}"},
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(
            [item["market_id"] for item in response.data],
            [str(second.id), str(self.market.id)],
        )

    @patch("apps.market.views.get_redis_client")
    def test_guest_sees_only_ten_highest_volume_markets(self, get_redis_client):
        volumes = {str(self.market.id): "1"}
        for index in range(11):
            asset = Asset.objects.create(
                symbol=f"M{index:02d}",
                name=f"Market {index:02d}",
                slug=f"market-{index:02d}",
                asset_type="crypto",
            )
            market = Market.objects.create(
                base_asset=asset,
                quote_asset=self.market.quote_asset,
                canonical_symbol=f"M{index:02d}-BRL",
            )
            volumes[str(market.id)] = str(index + 10)

        redis = Mock()
        redis.hgetall.side_effect = lambda key: {
            "volume_24h": volumes.get(key.rsplit(":", 1)[-1], "0")
        }
        get_redis_client.return_value = redis
        self.client.force_authenticate(user=None)

        response = self.client.get(reverse("market:list"), {"page_size": 100})

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["count"], 10)
        self.assertEqual(response.data["results"][0]["canonical_symbol"], "M10-BRL")
        self.assertNotIn(
            "BTC-BRL", [market["canonical_symbol"] for market in response.data["results"]]
        )

    def test_searches_and_paginates_markets(self):
        eth = Asset.objects.create(
            symbol="ETH", name="Ethereum", slug="ethereum", asset_type="crypto"
        )
        Market.objects.create(
            base_asset=eth,
            quote_asset=self.market.quote_asset,
            canonical_symbol="ETH-BRL",
        )

        response = self.client.get(reverse("market:list"), {"search": "ethereum", "page_size": 1})

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["count"], 1)
        self.assertEqual(response.data["results"][0]["canonical_symbol"], "ETH-BRL")

    @patch("apps.market.views.get_redis_client")
    def test_returns_current_quote(self, get_redis_client):
        redis = Mock()
        redis.hgetall.return_value = {"price": "600000", "timestamp": "2026-09-30T12:00:00+00:00"}
        get_redis_client.return_value = redis

        response = self.client.get(reverse("market:quote", args=(self.market.id,)))

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["price"], "600000")
        self.assertEqual(response.data["source_status"], "live")

    @patch("apps.market.views.get_redis_client")
    def test_quote_reports_unavailable_source_without_cached_state(self, get_redis_client):
        redis = Mock()
        redis.hgetall.return_value = {}
        get_redis_client.return_value = redis

        response = self.client.get(reverse("market:quote", args=(self.market.id,)))

        self.assertEqual(response.status_code, status.HTTP_503_SERVICE_UNAVAILABLE)
        self.assertEqual(response.data["error"]["code"], "market_data_unavailable")
        self.assertNotIn("Binance", str(response.data))

    @patch("apps.market.views.get_redis_client", side_effect=RedisError("down"))
    def test_overview_hides_redis_failure_details(self, get_redis_client):
        response = self.client.get(reverse("market:overview"))

        self.assertEqual(response.status_code, status.HTTP_500_INTERNAL_SERVER_ERROR)
        self.assertEqual(
            response.data["error"]["message"], "Não foi possível processar a solicitação."
        )
        self.assertNotIn("Redis", str(response.data))

    @patch("apps.market.services.get_market_provider")
    def test_candles_return_recoverable_provider_error(self, get_market_provider):
        provider = Mock()
        provider.fetch_candles = AsyncMock(side_effect=TimeoutError("provider timeout"))
        get_market_provider.return_value = provider

        response = self.client.get(
            reverse("market:candles", args=(self.market.id,)), {"interval": "1h"}
        )

        self.assertEqual(response.status_code, status.HTTP_503_SERVICE_UNAVAILABLE)
        self.assertEqual(
            response.data["error"]["message"], "Não foi possível processar a solicitação."
        )
        self.assertNotIn("provider timeout", str(response.data))

    @patch("apps.market.services.get_market_provider")
    def test_radar_marks_source_unavailable_when_all_queries_fail(self, get_market_provider):
        provider = Mock()
        provider.fetch_candles = AsyncMock(side_effect=TimeoutError("provider timeout"))
        get_market_provider.return_value = provider

        response = self.client.get(reverse("market:radar"))

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["source_status"], "unavailable")

    @patch("apps.market.services.get_market_provider")
    def test_returns_aggregated_radar(self, get_market_provider):
        start = datetime(2026, 10, 1, tzinfo=UTC)
        provider = Mock()
        provider.fetch_candles = AsyncMock(return_value=[
            MarketCandle(
                market_id=self.market.id,
                symbol=self.market.canonical_symbol,
                interval="1h",
                open_time=start + timedelta(hours=index),
                close_time=start + timedelta(hours=index + 1),
                open=Decimal("100"),
                high=Decimal("110"),
                low=Decimal("95"),
                close=Decimal("105"),
                volume=Decimal("2"),
                quote_volume=Decimal("210"),
                trades=10,
            )
            for index in range(24)
        ])
        get_market_provider.return_value = provider

        response = self.client.get(reverse("market:radar"))

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["gainers"][0]["market"]["canonical_symbol"], "BTC-BRL")
        self.assertEqual(response.data["gainers"][0]["change_percent"], "5.00")
        self.assertEqual(response.data["volume"][0]["quote_volume"], "5040")

    @patch("apps.market.services.get_market_provider")
    def test_filters_radar_by_owned_watchlist(self, get_market_provider):
        provider = Mock()
        provider.fetch_candles = AsyncMock(return_value=[])
        get_market_provider.return_value = provider
        watchlist = Watchlist.objects.create(user=self.user, name="Principal")
        WatchlistItem.objects.create(watchlist=watchlist, market=self.market)

        response = self.client.get(reverse("market:radar"), {"watchlist_id": watchlist.id})

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["scope"]["name"], "Principal")
        self.assertEqual(provider.fetch_candles.await_count, 1)

    @patch("apps.market.views.get_currency_rates")
    def test_returns_live_currency_rates(self, rates):
        rates.return_value = CurrencyRates(
            usd=Decimal("0.9998"), brl=Decimal("5.42"), source="binance"
        )

        response = self.client.get(reverse("market:rates"))

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["base"], "USDT")
        self.assertEqual(response.data["rates"]["BRL"], "5.42")
