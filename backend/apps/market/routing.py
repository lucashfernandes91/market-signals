from django.urls import path

from .consumers import MarketConsumer, MarketV1Consumer

websocket_urlpatterns = [
    path("ws/market/", MarketConsumer.as_asgi(), name="market-websocket"),
    path("ws/v1/market/", MarketV1Consumer.as_asgi(), name="market-websocket-v1"),
]
