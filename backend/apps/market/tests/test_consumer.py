from uuid import uuid4

from channels.testing import WebsocketCommunicator
from django.contrib.auth.models import AnonymousUser
from django.test import TransactionTestCase, override_settings

from apps.market.consumers import MarketConsumer
from apps.users.models import User

TEST_CHANNEL_LAYERS = {"default": {"BACKEND": "channels.layers.InMemoryChannelLayer"}}


@override_settings(CHANNEL_LAYERS=TEST_CHANNEL_LAYERS)
class MarketConsumerTests(TransactionTestCase):
    async def test_authenticated_user_can_subscribe(self):
        user = await User.objects.acreate(email="ws@example.com")
        communicator = WebsocketCommunicator(MarketConsumer.as_asgi(), "/ws/market/")
        communicator.scope["user"] = user

        connected, _ = await communicator.connect()
        self.assertTrue(connected)

        market_id = uuid4()
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
