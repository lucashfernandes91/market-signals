from datetime import UTC, datetime
from decimal import Decimal
from uuid import uuid4

from channels.layers import InMemoryChannelLayer
from django.test import SimpleTestCase

from apps.market.ingestion import ingest_quote, mark_stale_quotes
from apps.market.providers import MarketQuote
from infrastructure.redis.keys import market_events_stream, market_state_key


class FakeRedis:
    def __init__(self):
        self.hashes = {}
        self.streams = []

    async def hset(self, key, mapping):
        self.hashes.setdefault(key, {}).update(mapping)

    async def hgetall(self, key):
        return self.hashes.get(key, {}).copy()

    async def xadd(self, stream, payload, **kwargs):
        self.streams.append((stream, payload, kwargs))
        return "1-0"


class MarketIngestionTests(SimpleTestCase):
    async def test_persists_publishes_and_broadcasts_quote(self):
        market_id = uuid4()
        provider_market_id = uuid4()
        quote = MarketQuote(
            market_id=market_id,
            symbol="BTC-USDT",
            price=Decimal("70000.50"),
            volume_24h=Decimal("123456.78"),
            timestamp=datetime.now(UTC),
            change_24h_percent=Decimal("2.5"),
            provider_market_id=provider_market_id,
            provider_symbol="BTCUSDT",
        )
        redis = FakeRedis()
        channel_layer = InMemoryChannelLayer()
        channel_name = await channel_layer.new_channel()
        await channel_layer.group_add(f"market.{market_id}", channel_name)

        await ingest_quote(quote=quote, redis=redis, channel_layer=channel_layer)

        self.assertEqual(redis.hashes[market_state_key(market_id)]["price"], "70000.50")
        self.assertEqual(redis.hashes[market_state_key(market_id)]["change_24h_percent"], "2.5")
        self.assertEqual(redis.hashes[market_state_key(market_id)]["sequence"], "1-0")
        self.assertEqual(
            redis.hashes[market_state_key(market_id)]["provider_market_id"],
            str(provider_market_id),
        )
        self.assertEqual(redis.hashes[market_state_key(market_id)]["provider"], "binance")
        self.assertEqual(redis.hashes[market_state_key(market_id)]["provider_symbol"], "BTCUSDT")
        self.assertEqual(redis.hashes[market_state_key(market_id)]["source_status"], "live")
        self.assertEqual(redis.streams[0][0], market_events_stream())
        event = await channel_layer.receive(channel_name)
        self.assertEqual(event["type"], "market.update")
        self.assertEqual(event["data"]["symbol"], "BTC-USDT")

    async def test_marks_expired_quote_as_stale_and_broadcasts_it(self):
        market_id = uuid4()
        now = datetime(2026, 10, 1, 12, 0, tzinfo=UTC)
        redis = FakeRedis()
        redis.hashes[market_state_key(market_id)] = {
            "market_id": str(market_id),
            "price": "70000",
            "timestamp": "2026-10-01T11:59:40+00:00",
            "stale": "false",
        }
        channel_layer = InMemoryChannelLayer()
        channel_name = await channel_layer.new_channel()
        await channel_layer.group_add(f"market.{market_id}", channel_name)

        marked = await mark_stale_quotes(
            market_ids=[market_id],
            redis=redis,
            channel_layer=channel_layer,
            now=now,
        )

        self.assertEqual(marked, 1)
        self.assertEqual(redis.hashes[market_state_key(market_id)]["stale"], "true")
        self.assertEqual(redis.hashes[market_state_key(market_id)]["source_status"], "stale")
        event = await channel_layer.receive(channel_name)
        self.assertEqual(event["data"]["stale"], "true")
        self.assertEqual(event["data"]["source_status"], "stale")
