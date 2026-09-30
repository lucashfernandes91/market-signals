from datetime import UTC, datetime
from decimal import Decimal
from uuid import uuid4

from channels.layers import InMemoryChannelLayer
from django.test import SimpleTestCase

from apps.market.ingestion import ingest_quote
from apps.market.providers import MarketQuote
from infrastructure.redis.keys import market_events_stream, market_state_key


class FakeRedis:
    def __init__(self):
        self.hashes = {}
        self.streams = []

    async def hset(self, key, mapping):
        self.hashes[key] = mapping

    async def xadd(self, stream, payload, **kwargs):
        self.streams.append((stream, payload, kwargs))
        return "1-0"


class MarketIngestionTests(SimpleTestCase):
    async def test_persists_publishes_and_broadcasts_quote(self):
        market_id = uuid4()
        quote = MarketQuote(
            market_id=market_id,
            symbol="BTC-USDT",
            price=Decimal("70000.50"),
            volume_24h=Decimal("123456.78"),
            timestamp=datetime.now(UTC),
        )
        redis = FakeRedis()
        channel_layer = InMemoryChannelLayer()
        channel_name = await channel_layer.new_channel()
        await channel_layer.group_add(f"market.{market_id}", channel_name)

        await ingest_quote(quote=quote, redis=redis, channel_layer=channel_layer)

        self.assertEqual(redis.hashes[market_state_key(market_id)]["price"], "70000.50")
        self.assertEqual(redis.streams[0][0], market_events_stream())
        event = await channel_layer.receive(channel_name)
        self.assertEqual(event["type"], "market.update")
        self.assertEqual(event["data"]["symbol"], "BTC-USDT")
