import asyncio
import gzip
import json
import os
import random
from collections.abc import AsyncIterator, Sequence
from datetime import UTC, datetime
from decimal import Decimal
from urllib.parse import urlencode
from urllib.request import Request, urlopen

from .base import MarketProvider
from .models import MarketCandle, MarketQuote, MarketSubscription, ProviderCatalogMarket


class BinanceMarketProvider(MarketProvider):
    code = "binance"
    display_name = "Binance"
    rest_endpoint = "https://data-api.binance.vision/api/v3"
    websocket_endpoint = "wss://stream.binance.com:9443/stream"
    allowed_intervals = {"1m", "3m", "5m", "15m", "30m", "1h", "2h", "4h", "6h", "8h", "12h", "1d"}

    def __init__(
        self,
        interval_seconds: float = 0.25,
        stale_after_seconds: int = 15,
        request_timeout_seconds: float | None = None,
        catalog_timeout_seconds: float | None = None,
    ) -> None:
        self.interval_seconds = interval_seconds
        self.stale_after_seconds = stale_after_seconds
        self.catalog_endpoint = os.environ.get(
            "BINANCE_CATALOG_ENDPOINT", "https://api.binance.com/api/v3"
        ).rstrip("/")
        self.request_timeout_seconds = request_timeout_seconds or self._timeout_from_environment(
            "BINANCE_REQUEST_TIMEOUT_SECONDS", 10
        )
        self.catalog_timeout_seconds = catalog_timeout_seconds or self._timeout_from_environment(
            "BINANCE_CATALOG_TIMEOUT_SECONDS", 120
        )

    async def fetch_catalog(self) -> list[ProviderCatalogMarket]:
        params = {
            "permissions": "SPOT",
            "showPermissionSets": "false",
            "symbolStatus": "TRADING",
        }
        payload = await asyncio.to_thread(
            self._fetch_json,
            f"{self.catalog_endpoint}/exchangeInfo?{urlencode(params)}",
            self.catalog_timeout_seconds,
        )
        return [self._normalize_catalog_market(item) for item in payload.get("symbols", [])]

    async def fetch_candles(
        self,
        market: MarketSubscription,
        *,
        interval: str,
        limit: int,
    ) -> list[MarketCandle]:
        if interval not in self.allowed_intervals:
            raise ValueError(f"Unsupported Binance interval: {interval}")
        bounded_limit = min(max(limit, 1), 1000)
        params = {"symbol": self._symbol(market), "interval": interval, "limit": bounded_limit}
        payload = await asyncio.to_thread(
            self._fetch_json, f"{self.rest_endpoint}/klines?{urlencode(params)}"
        )
        return [self._normalize_candle(market, interval, row) for row in payload]

    async def fetch_spot_price(self, symbol: str) -> Decimal:
        params = {"symbol": symbol.replace("-", "").upper()}
        payload = await asyncio.to_thread(
            self._fetch_json, f"{self.rest_endpoint}/ticker/price?{urlencode(params)}"
        )
        return Decimal(payload["price"])

    async def fetch_spot_prices(self, symbols: Sequence[str]) -> dict[str, Decimal]:
        normalized = [symbol.replace("-", "").upper() for symbol in symbols]
        params = {"symbols": json.dumps(normalized, separators=(",", ":"))}
        payload = await asyncio.to_thread(
            self._fetch_json, f"{self.rest_endpoint}/ticker/price?{urlencode(params)}"
        )
        return {item["symbol"]: Decimal(item["price"]) for item in payload}

    async def stream_quotes(
        self,
        markets: Sequence[MarketSubscription],
    ) -> AsyncIterator[MarketQuote]:
        if not markets:
            return
        import websockets

        streams = "/".join(f"{self._symbol(market).lower()}@ticker" for market in markets)
        url = f"{self.websocket_endpoint}?streams={streams}"
        backoff = 1.0
        while True:
            try:
                async with websockets.connect(url, ping_interval=20, ping_timeout=20) as socket:
                    backoff = 1.0
                    pending: dict[str, MarketQuote] = {}
                    last_emitted: dict[str, float] = {}
                    loop = asyncio.get_running_loop()
                    subscriptions = {self._symbol(market): market for market in markets}
                    async for raw in socket:
                        message = json.loads(raw)
                        ticker = message.get("data", message)
                        symbol = ticker.get("s", "")
                        market = subscriptions.get(symbol)
                        if market is None or ticker.get("e") != "24hrTicker":
                            continue
                        pending[symbol] = self._normalize_ticker(market, ticker)
                        now = loop.time()
                        if now - last_emitted.get(symbol, 0.0) < self.interval_seconds:
                            continue
                        last_emitted[symbol] = now
                        yield pending.pop(symbol)
            except (OSError, TimeoutError, websockets.WebSocketException):
                await asyncio.sleep(backoff + random.uniform(0, 0.5))
                backoff = min(backoff * 2, 30)

    def _fetch_json(self, url: str, timeout_seconds: float | None = None):
        request = Request(
            url,
            headers={
                "Accept": "application/json",
                "Accept-Encoding": "gzip",
                "User-Agent": "MarketRadar/0.1",
            },
        )
        with urlopen(request, timeout=timeout_seconds or self.request_timeout_seconds) as response:
            if response.headers.get("Content-Encoding") == "gzip":
                with gzip.GzipFile(fileobj=response) as compressed:
                    return json.load(compressed)
            return json.load(response)

    @staticmethod
    def _timeout_from_environment(name: str, default: float) -> float:
        raw_value = os.environ.get(name, str(default))
        try:
            value = float(raw_value)
        except ValueError as exc:
            raise ValueError(f"{name} deve ser um número.") from exc
        if value <= 0:
            raise ValueError(f"{name} deve ser maior que zero.")
        return value

    def _normalize_ticker(self, market: MarketSubscription, payload: dict) -> MarketQuote:
        timestamp = datetime.fromtimestamp(int(payload["E"]) / 1000, UTC)
        stale = (datetime.now(UTC) - timestamp).total_seconds() > self.stale_after_seconds
        return MarketQuote(
            market_id=market.market_id,
            symbol=market.symbol,
            price=Decimal(payload["c"]),
            volume_24h=Decimal(payload["q"]),
            timestamp=timestamp,
            change_24h_percent=Decimal(payload.get("P", "0")),
            stale=stale,
            provider=self.code,
            provider_name=self.display_name,
            provider_symbol=self._symbol(market),
            provider_market_id=market.provider_market_id,
        )

    def _normalize_candle(
        self, market: MarketSubscription, interval: str, row: list
    ) -> MarketCandle:
        return MarketCandle(
            market_id=market.market_id,
            symbol=market.symbol,
            interval=interval,
            open_time=datetime.fromtimestamp(int(row[0]) / 1000, UTC),
            close_time=datetime.fromtimestamp(int(row[6]) / 1000, UTC),
            open=Decimal(row[1]),
            high=Decimal(row[2]),
            low=Decimal(row[3]),
            close=Decimal(row[4]),
            volume=Decimal(row[5]),
            quote_volume=Decimal(row[7]),
            trades=int(row[8]),
        )

    @staticmethod
    def _symbol(market: MarketSubscription) -> str:
        return (market.provider_symbol or market.symbol).replace("-", "").upper()

    @staticmethod
    def _normalize_catalog_market(payload: dict) -> ProviderCatalogMarket:
        return ProviderCatalogMarket(
            external_symbol=payload["symbol"],
            base_symbol=payload["baseAsset"],
            quote_symbol=payload["quoteAsset"],
            status=payload["status"],
            base_precision=payload.get("baseAssetPrecision"),
            quote_precision=payload.get("quotePrecision"),
            metadata={
                "order_types": payload.get("orderTypes", []),
                "quote_order_qty_market_allowed": payload.get("quoteOrderQtyMarketAllowed", False),
            },
        )
