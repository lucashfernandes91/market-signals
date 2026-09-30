from datetime import UTC
from uuid import uuid4

from django.test import SimpleTestCase

from apps.market.providers import MarketSubscription, StubMarketProvider


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
