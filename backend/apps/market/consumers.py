from uuid import UUID

from channels.generic.websocket import AsyncJsonWebsocketConsumer


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
