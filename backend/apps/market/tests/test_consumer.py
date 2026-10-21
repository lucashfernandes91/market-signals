from unittest.mock import patch

from channels.db import database_sync_to_async
from channels.testing import WebsocketCommunicator
from django.contrib.auth.models import AnonymousUser
from django.test import TransactionTestCase, override_settings
from rest_framework_simplejwt.tokens import AccessToken

from apps.market.consumers import MarketConsumer, MarketV1Consumer
from apps.market.models import Asset, Market, ProviderMarket
from apps.users.models import User

TEST_CHANNEL_LAYERS = {"default": {"BACKEND": "channels.layers.InMemoryChannelLayer"}}


@database_sync_to_async
def create_provider_market(*, is_active=True):
    btc = Asset.objects.create(
        symbol=f"BTC{Asset.objects.count()}",
        name="Bitcoin",
        slug=f"bitcoin-{Asset.objects.count()}",
        asset_type=Asset.Type.CRYPTO,
    )
    brl, _ = Asset.objects.get_or_create(
        symbol="BRL",
        defaults={"name": "Real", "slug": "real", "asset_type": Asset.Type.FIAT},
    )
    market = Market.objects.create(
        base_asset=btc,
        quote_asset=brl,
        canonical_symbol=f"{btc.symbol}-BRL",
    )
    ProviderMarket.objects.create(
        provider="binance",
        market=market,
        external_symbol=f"{btc.symbol}BRL",
        is_active=is_active,
    )
    return market.id


class FakeAsyncRedis:
    def __init__(self, state):
        self.state = state

    async def hgetall(self, key):
        return self.state

    async def aclose(self):
        return None


@override_settings(CHANNEL_LAYERS=TEST_CHANNEL_LAYERS)
class MarketConsumerTests(TransactionTestCase):
    async def test_authenticated_user_can_subscribe(self):
        user = await User.objects.acreate(email="ws@example.com")
        communicator = WebsocketCommunicator(MarketConsumer.as_asgi(), "/ws/market/")
        communicator.scope["user"] = user

        connected, _ = await communicator.connect()
        self.assertTrue(connected)

        market_id = await create_provider_market()
        await communicator.send_json_to({"action": "subscribe", "market_id": str(market_id)})
        response = await communicator.receive_json_from()

        self.assertEqual(response, {"type": "subscribed", "market_id": str(market_id)})
        await communicator.disconnect()

    async def test_anonymous_user_is_rejected(self):
        communicator = WebsocketCommunicator(MarketConsumer.as_asgi(), "/ws/market/")
        communicator.scope["user"] = AnonymousUser()

        connected, code = await communicator.connect()

        self.assertFalse(connected)
        self.assertEqual(code, 4401)

    @patch("apps.market.consumers.get_async_redis_client")
    async def test_v1_accepts_jwt_and_sends_snapshot_with_sequence(self, get_redis_client):
        user = await User.objects.acreate(email="v1@example.com")
        market_id = await create_provider_market()
        get_redis_client.return_value = FakeAsyncRedis(
            {
                "market_id": str(market_id),
                "price": "70000",
                "timestamp": "2026-10-01T12:00:00+00:00",
                "sequence": "123-0",
                "stale": "false",
            }
        )
        communicator = WebsocketCommunicator(MarketV1Consumer.as_asgi(), "/ws/v1/market/")

        connected, _ = await communicator.connect()
        self.assertTrue(connected)
        await communicator.send_json_to(
            {
                "v": 1,
                "id": "auth-1",
                "type": "auth",
                "data": {"access_token": str(AccessToken.for_user(user))},
            }
        )
        accepted = await communicator.receive_json_from()
        self.assertEqual(accepted["type"], "auth.accepted")

        await communicator.send_json_to(
            {
                "v": 1,
                "id": "subscribe-1",
                "type": "market.subscribe",
                "data": {"market_ids": [str(market_id)]},
            }
        )
        snapshot = await communicator.receive_json_from()
        subscribed = await communicator.receive_json_from()

        self.assertEqual(snapshot["type"], "market.snapshot")
        self.assertEqual(snapshot["data"]["sequence"], "123-0")
        self.assertEqual(subscribed["type"], "market.subscribed")
        await communicator.disconnect()

    @patch("apps.market.consumers.get_async_redis_client")
    async def test_v1_anonymous_user_can_subscribe(self, get_redis_client):
        market_id = await create_provider_market()
        get_redis_client.return_value = FakeAsyncRedis(
            {"market_id": str(market_id), "price": "70000", "sequence": "123-0"}
        )
        communicator = WebsocketCommunicator(MarketV1Consumer.as_asgi(), "/ws/v1/market/")

        connected, _ = await communicator.connect()
        self.assertTrue(connected)
        await communicator.send_json_to(
            {
                "v": 1,
                "id": "subscribe-1",
                "type": "market.subscribe",
                "data": {"market_ids": [str(market_id)]},
            }
        )
        snapshot = await communicator.receive_json_from()
        subscribed = await communicator.receive_json_from()

        self.assertEqual(snapshot["type"], "market.snapshot")
        self.assertEqual(subscribed["type"], "market.subscribed")
        await communicator.disconnect()

    async def test_v1_rejects_deactivated_listing(self):
        market_id = await create_provider_market(is_active=False)
        communicator = WebsocketCommunicator(MarketV1Consumer.as_asgi(), "/ws/v1/market/")

        connected, _ = await communicator.connect()
        self.assertTrue(connected)
        await communicator.send_json_to(
            {
                "v": 1,
                "id": "subscribe-disabled",
                "type": "market.subscribe",
                "data": {"market_ids": [str(market_id)]},
            }
        )
        response = await communicator.receive_json_from()

        self.assertEqual(response["type"], "error")
        self.assertEqual(response["data"]["code"], "market_not_available")
        await communicator.disconnect()
