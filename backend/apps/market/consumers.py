from collections import deque
from datetime import UTC, datetime
from time import monotonic
from uuid import UUID, uuid4

from channels.db import database_sync_to_async
from channels.generic.websocket import AsyncJsonWebsocketConsumer
from rest_framework_simplejwt.authentication import JWTAuthentication
from rest_framework_simplejwt.exceptions import InvalidToken, TokenError

from infrastructure.redis.client import get_async_redis_client
from infrastructure.redis.keys import market_state_key

from .models import ProviderMarket
from .providers.registry import get_configured_provider_code


@database_sync_to_async
def active_market_ids(market_ids: list[str]) -> set[str]:
    return {
        str(market_id)
        for market_id in ProviderMarket.objects.filter(
            provider=get_configured_provider_code(),
            market_id__in=market_ids,
            is_active=True,
            market__is_active=True,
        ).values_list("market_id", flat=True)
    }


class MarketConsumer(AsyncJsonWebsocketConsumer):
    async def connect(self):
        if self.scope["user"].is_anonymous:
            await self.close(code=4401)
            return
        self.market_groups: set[str] = set()
        await self.accept()

    async def disconnect(self, close_code):
        for group_name in self.market_groups:
            await self.channel_layer.group_discard(group_name, self.channel_name)

    async def receive_json(self, content, **kwargs):
        action = content.get("action")
        market_id = content.get("market_id")

        try:
            normalized_market_id = str(UUID(str(market_id)))
        except (TypeError, ValueError):
            await self.send_json({"type": "error", "code": "invalid_market_id"})
            return

        group_name = f"market.{normalized_market_id}"
        if action == "subscribe":
            await self.channel_layer.group_add(group_name, self.channel_name)
            self.market_groups.add(group_name)
            await self.send_json({"type": "subscribed", "market_id": normalized_market_id})
            return

        if action == "unsubscribe":
            await self.channel_layer.group_discard(group_name, self.channel_name)
            self.market_groups.discard(group_name)
            await self.send_json({"type": "unsubscribed", "market_id": normalized_market_id})
            return

        await self.send_json({"type": "error", "code": "unsupported_action"})

    async def market_update(self, event):
        await self.send_json({"type": "market.update", "data": event["data"]})


class MarketV1Consumer(AsyncJsonWebsocketConsumer):
    max_markets = 50
    max_commands_per_minute = 30

    async def connect(self):
        self.user = None
        self.market_groups: set[str] = set()
        self.command_timestamps = deque()
        await self.accept()

    async def disconnect(self, close_code):
        for group_name in self.market_groups:
            await self.channel_layer.group_discard(group_name, self.channel_name)

    async def receive_json(self, content, **kwargs):
        message_id = content.get("id")
        message_type = content.get("type")
        if message_type not in {"ping", "auth"} and not self._can_receive_command():
            await self._error(message_id, "command_rate_limited")
            return
        if content.get("v") != 1:
            await self._error(message_id, "unsupported_version")
            return
        if message_type == "ping":
            await self._send("pong", {}, message_id)
            return
        if message_type == "auth":
            await self._authenticate(content.get("data", {}).get("access_token"), message_id)
            return
        if message_type == "market.subscribe":
            await self._subscribe(content.get("data", {}).get("market_ids"), message_id)
            return
        if message_type == "market.unsubscribe":
            await self._unsubscribe(content.get("data", {}).get("market_ids"), message_id)
            return
        await self._error(message_id, "unsupported_type")

    async def _authenticate(self, access_token, message_id):
        try:
            token = JWTAuthentication().get_validated_token(access_token)
            self.user = await database_sync_to_async(JWTAuthentication().get_user)(token)
        except (InvalidToken, TokenError, TypeError):
            await self._error(message_id, "invalid_token")
            await self.close(code=4401)
            return
        expires_at = datetime.fromtimestamp(token["exp"], UTC).isoformat().replace("+00:00", "Z")
        await self._send(
            "auth.accepted", {"user_id": str(self.user.id), "expires_at": expires_at}, message_id
        )

    async def _subscribe(self, market_ids, message_id):
        if not isinstance(market_ids, list) or len(market_ids) > self.max_markets:
            await self._error(message_id, "invalid_market_ids")
            return
        normalized = []
        for market_id in market_ids:
            try:
                value = str(UUID(str(market_id)))
            except (TypeError, ValueError):
                await self._error(message_id, "invalid_market_id")
                return
            if value not in normalized:
                normalized.append(value)
        if set(normalized) != await active_market_ids(normalized):
            await self._error(message_id, "market_not_available")
            return
        redis = get_async_redis_client()
        try:
            for market_id in normalized:
                await self.channel_layer.group_add(f"market.{market_id}", self.channel_name)
                self.market_groups.add(f"market.{market_id}")
                snapshot = await redis.hgetall(market_state_key(market_id))
                await self._send("market.snapshot", {"market_id": market_id, **snapshot})
        finally:
            await redis.aclose()
        await self._send("market.subscribed", {"market_ids": normalized}, message_id)

    async def _unsubscribe(self, market_ids, message_id):
        if not isinstance(market_ids, list):
            await self._error(message_id, "invalid_market_ids")
            return
        normalized = []
        for market_id in market_ids:
            try:
                value = str(UUID(str(market_id)))
            except (TypeError, ValueError):
                await self._error(message_id, "invalid_market_id")
                return
            await self.channel_layer.group_discard(f"market.{value}", self.channel_name)
            self.market_groups.discard(f"market.{value}")
            normalized.append(value)
        await self._send("market.unsubscribed", {"market_ids": normalized}, message_id)

    async def market_update(self, event):
        await self._send("market.delta", event["data"])

    async def _send(self, message_type, data, message_id=None):
        await self.send_json(
            {"v": 1, "id": message_id or str(uuid4()), "type": message_type, "data": data}
        )

    async def _error(self, message_id, code):
        await self._send("error", {"code": code}, message_id)

    def _can_receive_command(self):
        now = monotonic()
        while self.command_timestamps and now - self.command_timestamps[0] >= 60:
            self.command_timestamps.popleft()
        if len(self.command_timestamps) >= self.max_commands_per_minute:
            return False
        self.command_timestamps.append(now)
        return True
