from datetime import UTC
from decimal import Decimal
from unittest.mock import Mock
from uuid import uuid4

from django.test import SimpleTestCase

from apps.market.providers import MarketSubscription
from apps.market.providers.binance import BinanceMarketProvider
from apps.market.providers.models import ProviderCatalogMarket
from apps.market.providers.registry import ProviderConfigurationError, get_market_provider
from apps.market.providers.stub import StubMarketProvider


class StubMarketProviderTests(SimpleTestCase):
    async def test_emits_normalized_quote(self):
        market_id = uuid4()
        provider = StubMarketProvider(interval_seconds=0)
        quotes = provider.stream_quotes(
            [MarketSubscription(market_id=market_id, symbol="BTC-USDT")]
        )

        quote = await anext(quotes)
        await quotes.aclose()

        self.assertEqual(quote.market_id, market_id)
        self.assertEqual(quote.symbol, "BTC-USDT")
        self.assertEqual(quote.timestamp.tzinfo, UTC)
        self.assertGreater(quote.price, 0)


class BinanceProviderTests(SimpleTestCase):
    def setUp(self):
        self.market = MarketSubscription(market_id=uuid4(), symbol="BTC-USDT")

    def test_registry_exposes_only_binance(self):
        self.assertIsInstance(get_market_provider("binance"), BinanceMarketProvider)
        with self.assertRaises(ProviderConfigurationError):
            get_market_provider("coinbase")

    def test_normalizes_ticker_and_detects_fresh_data(self):
        provider = BinanceMarketProvider(stale_after_seconds=2_000_000)
        quote = provider._normalize_ticker(
            self.market,
            {
                "E": 1790784000000,
                "c": "70123.42",
                "q": "18722399122.00",
                "P": "5.25",
            },
        )

        self.assertEqual(quote.symbol, "BTC-USDT")
        self.assertEqual(quote.price, Decimal("70123.42"))
        self.assertEqual(quote.change_24h_percent, Decimal("5.25"))
        self.assertFalse(quote.stale)

    async def test_fetches_and_normalizes_candles(self):
        provider = BinanceMarketProvider()
        provider._fetch_json = Mock(
            return_value=[
                [
                    1790784000000,
                    "70000",
                    "70200",
                    "69900",
                    "70100",
                    "100",
                    1790784059999,
                    "7000000",
                    42,
                    "50",
                    "3500000",
                    "0",
                ]
            ]
        )

        candles = await provider.fetch_candles(self.market, interval="1m", limit=1)

        self.assertEqual(len(candles), 1)
        self.assertEqual(candles[0].close, Decimal("70100"))
        self.assertEqual(candles[0].trades, 42)

    async def test_fetches_multiple_spot_prices_in_one_request(self):
        provider = BinanceMarketProvider()
        provider._fetch_json = Mock(
            return_value=[
                {"symbol": "USDCUSDT", "price": "1.0001"},
                {"symbol": "USDTBRL", "price": "5.22"},
            ]
        )

        prices = await provider.fetch_spot_prices(("USDCUSDT", "USDTBRL"))

        self.assertEqual(prices["USDCUSDT"], Decimal("1.0001"))
        self.assertEqual(prices["USDTBRL"], Decimal("5.22"))
        requested_url = provider._fetch_json.call_args.args[0]
        self.assertIn("symbols=", requested_url)

    async def test_fetches_and_normalizes_catalog(self):
        provider = BinanceMarketProvider()
        provider._fetch_json = Mock(
            return_value={
                "symbols": [
                    {
                        "symbol": "BTCUSDT",
                        "baseAsset": "BTC",
                        "quoteAsset": "USDT",
                        "status": "TRADING",
                        "baseAssetPrecision": 8,
                        "quotePrecision": 8,
                    }
                ]
            }
        )

        catalog = await provider.fetch_catalog()

        self.assertEqual(
            catalog,
            [
                ProviderCatalogMarket(
                    external_symbol="BTCUSDT",
                    base_symbol="BTC",
                    quote_symbol="USDT",
                    status="TRADING",
                    base_precision=8,
                    quote_precision=8,
                    metadata={
                        "order_types": [],
                        "quote_order_qty_market_allowed": False,
                    },
                )
            ],
        )
