import logging
from dataclasses import dataclass
from decimal import Decimal, InvalidOperation
from uuid import UUID

from asgiref.sync import async_to_sync
from django.shortcuts import get_object_or_404
from django.utils import timezone
from redis.exceptions import RedisError
from rest_framework import filters, generics, permissions
from rest_framework.exceptions import APIException, NotAuthenticated
from rest_framework.response import Response

from infrastructure.redis.client import get_redis_client
from infrastructure.redis.keys import market_state_key

from . import services
from .models import Market
from .pagination import MarketPagination
from .rates import get_currency_rates
from .serializers import MarketOverviewSerializer, MarketSerializer

logger = logging.getLogger(__name__)


class MarketDataUnavailable(APIException):
    status_code = 503
    default_detail = "Os dados de mercado estão temporariamente indisponíveis."
    default_code = "market_data_unavailable"


@dataclass(frozen=True, slots=True)
class RadarMetric:
    market: Market
    change_percent: Decimal
    quote_volume: Decimal
    volatility_percent: Decimal


def calculate_radar_metric(market: Market, candles) -> RadarMetric | None:
    if not candles or candles[0].open <= 0:
        return None
    change_percent = (candles[-1].close - candles[0].open) / candles[0].open * 100
    quote_volume = sum((candle.quote_volume for candle in candles), Decimal())
    ranges = [
        (candle.high - candle.low) / candle.open * 100 for candle in candles if candle.open > 0
    ]
    volatility_percent = sum(ranges, Decimal()) / len(ranges) if ranges else Decimal()
    return RadarMetric(market, change_percent, quote_volume, volatility_percent)


class MarketListView(generics.ListAPIView):
    serializer_class = MarketSerializer
    permission_classes = (permissions.AllowAny,)
    pagination_class = MarketPagination
    filter_backends = (filters.SearchFilter,)
    search_fields = (
        "canonical_symbol",
        "base_asset__symbol",
        "base_asset__name",
        "quote_asset__symbol",
    )
    guest_limit = 10

    def get_queryset(self):
        return Market.objects.filter(is_active=True).select_related("base_asset", "quote_asset")

    def list(self, request, *args, **kwargs):
        if request.user.is_authenticated:
            return super().list(request, *args, **kwargs)

        markets = self._rank_guest_markets(list(self.filter_queryset(self.get_queryset())))
        page = self.paginate_queryset(markets[: self.guest_limit])
        if page is not None:
            serializer = self.get_serializer(page, many=True)
            return self.get_paginated_response(serializer.data)
        return Response(self.get_serializer(markets[: self.guest_limit], many=True).data)

    @staticmethod
    def _rank_guest_markets(markets: "list[Market]") -> "list[Market]":
        volumes: dict[str, Decimal] = {}
        redis = None
        try:
            redis = get_redis_client()
            states = _read_market_states(
                redis, [market.id for market in markets], operation="guest_ranking"
            )
            for market in markets:
                raw_volume = states.get(str(market.id), {}).get("volume_24h")
                try:
                    volumes[str(market.id)] = Decimal(str(raw_volume))
                except (InvalidOperation, TypeError, ValueError):
                    volumes[str(market.id)] = Decimal()
        except RedisError:
            pass
        finally:
            if redis is not None:
                redis.close()
        return sorted(
            markets,
            key=lambda market: (-volumes.get(str(market.id), Decimal()), market.canonical_symbol),
        )


class MarketLookupView(generics.ListAPIView):
    serializer_class = MarketSerializer
    permission_classes = (permissions.AllowAny,)

    def get_queryset(self):
        raw_ids = self.request.query_params.get("ids", "")
        try:
            market_ids = [UUID(value) for value in raw_ids.split(",") if value][:100]
        except ValueError:
            market_ids = []
        return Market.objects.filter(is_active=True, id__in=market_ids).select_related(
            "base_asset", "quote_asset"
        )


class MarketOverviewView(generics.GenericAPIView):
    permission_classes = (permissions.AllowAny,)

    def get(self, request):
        queryset = Market.objects.filter(is_active=True).select_related("base_asset", "quote_asset")
        raw_ids = request.query_params.get("ids")
        if raw_ids is None:
            markets = list(queryset.order_by("canonical_symbol"))
        else:
            try:
                requested_ids = [UUID(value) for value in raw_ids.split(",") if value][:100]
            except ValueError:
                requested_ids = []
            markets_by_id = {market.id: market for market in queryset.filter(id__in=requested_ids)}
            markets = [
                markets_by_id[market_id]
                for market_id in requested_ids
                if market_id in markets_by_id
            ]
        redis = None
        try:
            redis = get_redis_client()
            quotes = _read_market_states(
                redis, [market.id for market in markets], operation="overview"
            )
        except RedisError as exc:
            raise APIException("O resumo do mercado está temporariamente indisponível.") from exc
        finally:
            if redis is not None:
                redis.close()

        subscriptions = services.subscriptions_for_markets(markets)
        data = []
        for market, subscription in zip(markets, subscriptions, strict=True):
            quote = quotes[str(market.id)]
            origin = services.origin_for_subscription(subscription)
            source_status = _source_status(quote, subscription)
            data.append(
                {
                    "market_id": market.id,
                    "asset_name": market.base_asset.name,
                    "asset_symbol": market.base_asset.symbol,
                    "canonical_symbol": market.canonical_symbol,
                    "provider_market_id": quote.get("provider_market_id")
                    or origin["provider_market_id"],
                    "provider": quote.get("provider") or origin["provider"],
                    "provider_name": quote.get("provider_name") or origin["provider_name"],
                    "provider_symbol": quote.get("provider_symbol") or origin["provider_symbol"],
                    "price": quote.get("price"),
                    "change_24h_percent": quote.get("change_24h_percent"),
                    "volume_24h": quote.get("volume_24h"),
                    "timestamp": quote.get("timestamp"),
                    "provider_timestamp": quote.get("provider_timestamp") or quote.get("timestamp"),
                    "received_at": quote.get("received_at"),
                    "stale": _parse_bool(quote.get("stale")),
                    "source_status": source_status,
                }
            )
        return Response(MarketOverviewSerializer(data, many=True).data)


def _parse_bool(value):
    if value is None:
        return None
    return str(value).lower() == "true"


def _source_status(quote, subscription) -> str:
    if subscription.provider_market_id is None or subscription.provider_symbol is None:
        return "unavailable"
    if quote.get("source_status") in {"live", "stale", "unavailable"}:
        return quote["source_status"]
    if _parse_bool(quote.get("stale")):
        return "stale"
    return "live" if quote else "unavailable"


class MarketRatesView(generics.GenericAPIView):
    permission_classes = (permissions.AllowAny,)

    def get(self, request):
        try:
            rates = get_currency_rates()
        except (OSError, TimeoutError, ValueError) as exc:
            raise MarketDataUnavailable() from exc
        return Response(rates.as_dict())


class MarketDetailView(generics.RetrieveAPIView):
    serializer_class = MarketSerializer
    permission_classes = (permissions.AllowAny,)

    def get_queryset(self):
        return Market.objects.filter(is_active=True).select_related("base_asset", "quote_asset")


class MarketQuoteView(generics.GenericAPIView):
    permission_classes = (permissions.AllowAny,)

    def get(self, request, pk):
        market = get_object_or_404(Market.objects.filter(is_active=True), pk=pk)
        redis = None
        try:
            redis = get_redis_client()
            quote = redis.hgetall(market_state_key(market.id))
        except RedisError as exc:
            raise APIException("A cotação está temporariamente indisponível.") from exc
        finally:
            if redis is not None:
                redis.close()

        if not quote:
            raise MarketDataUnavailable()
        subscription = services.subscriptions_for_markets([market])[0]
        try:
            services.ensure_active_listing(subscription)
        except services.MarketSourceUnavailable as exc:
            raise MarketDataUnavailable() from exc
        return Response(
            {
                "market_id": str(market.id),
                **services.origin_for_subscription(subscription),
                **quote,
                "source_status": _source_status(quote, subscription),
            }
        )


class MarketCandlesView(generics.GenericAPIView):
    permission_classes = (permissions.AllowAny,)
    allowed_intervals = {"1m", "5m", "15m", "1h", "4h", "1d"}

    def get(self, request, pk):
        market = get_object_or_404(Market.objects.filter(is_active=True), pk=pk)
        interval = request.query_params.get("interval", "1h")
        if interval not in self.allowed_intervals:
            return Response({"detail": "Intervalo inválido."}, status=400)
        try:
            limit = min(max(int(request.query_params.get("limit", "200")), 1), 200)
        except ValueError:
            return Response({"detail": "limit inválido."}, status=400)
        subscription = services.subscriptions_for_markets([market])[0]
        try:
            candles = async_to_sync(services.fetch_candles)(
                subscription,
                interval=interval,
                limit=limit,
            )
        except (OSError, TimeoutError, ValueError, services.MarketSourceUnavailable) as exc:
            raise MarketDataUnavailable() from exc
        return Response(
            {
                "market_id": str(market.id),
                **services.origin_for_subscription(subscription),
                "interval": interval,
                "candles": [self._serialize_candle(candle) for candle in candles],
            }
        )

    @staticmethod
    def _serialize_candle(candle):
        return {
            "timestamp": candle.open_time.isoformat(),
            "open": str(candle.open),
            "high": str(candle.high),
            "low": str(candle.low),
            "close": str(candle.close),
            "volume": str(candle.volume),
            "quote_volume": str(candle.quote_volume),
            "trades": candle.trades,
        }


def _read_market_states(redis, market_ids, *, operation="market_state"):
    keys = [market_state_key(market_id) for market_id in market_ids]
    pipeline_factory = getattr(redis, "pipeline", None)
    if callable(pipeline_factory):
        try:
            pipeline = pipeline_factory(transaction=False)
            for key in keys:
                pipeline.hgetall(key)
            states = pipeline.execute()
            if isinstance(states, (list, tuple)) and len(states) == len(keys):
                logger.info(
                    "market_state_batch_read",
                    extra={
                        "operation": operation,
                        "market_count": len(keys),
                        "batched": True,
                    },
                )
                return {
                    str(market_id): state
                    for market_id, state in zip(market_ids, states, strict=True)
                }
        except (AttributeError, TypeError, RedisError):
            pass
    logger.info(
        "market_state_batch_read",
        extra={"operation": operation, "market_count": len(keys), "batched": False},
    )
    return {str(market_id): redis.hgetall(market_state_key(market_id)) for market_id in market_ids}


class MarketRadarView(generics.GenericAPIView):
    permission_classes = (permissions.AllowAny,)
    default_limit = 5
    candles_per_market = 24

    def get(self, request):
        try:
            limit = min(max(int(request.query_params.get("limit", self.default_limit)), 1), 20)
        except ValueError:
            return Response({"detail": "limit inválido."}, status=400)

        markets, scope = self._markets(request)
        subscriptions = services.subscriptions_for_markets(markets)
        metrics, failed_markets = async_to_sync(self._load_metrics)(markets, subscriptions)
        return Response(
            {
                "updated_at": timezone.now().isoformat(),
                "scope": scope,
                "gainers": self._serialize(metrics, "change_percent", reverse=True, limit=limit),
                "losers": self._serialize(metrics, "change_percent", reverse=False, limit=limit),
                "volume": self._serialize(metrics, "quote_volume", reverse=True, limit=limit),
                "volatility": self._serialize(
                    metrics, "volatility_percent", reverse=True, limit=limit
                ),
                "source_status": "unavailable"
                if markets and len(failed_markets) == len(markets)
                else "live",
            }
        )

    def _markets(self, request) -> tuple[list[Market], dict[str, str]]:
        queryset = Market.objects.filter(is_active=True).select_related("base_asset", "quote_asset")
        watchlist_id = request.query_params.get("watchlist_id")
        if watchlist_id:
            if not request.user.is_authenticated:
                raise NotAuthenticated("Entre para usar uma watchlist no Radar.")
            watchlist = get_object_or_404(
                request.user.watchlists.prefetch_related("items"), pk=watchlist_id
            )
            market_ids = watchlist.items.values_list("market_id", flat=True)
            return list(queryset.filter(id__in=market_ids)), {
                "type": "watchlist",
                "id": str(watchlist.id),
                "name": watchlist.name,
            }

        raw_ids = request.query_params.get("market_ids", "")
        if raw_ids:
            try:
                market_ids = [UUID(value) for value in raw_ids.split(",") if value][:100]
            except ValueError:
                return [], {"type": "selection", "name": "Seleção inválida"}
            return list(queryset.filter(id__in=market_ids)), {
                "type": "selection",
                "name": "Favoritos locais",
            }
        return list(queryset), {"type": "all", "name": "Todo o mercado"}

    async def _load_metrics(
        self,
        markets: list[Market],
        subscriptions,
    ) -> tuple[list[RadarMetric], list[Market]]:
        try:
            candles_by_market = await services.fetch_candles_for_subscriptions(
                subscriptions,
                interval="1h",
                limit=self.candles_per_market,
            )
        except services.MarketSourceUnavailable:
            return [], markets
        metrics = []
        failed_markets = []
        for market, candles in zip(markets, candles_by_market, strict=True):
            if isinstance(candles, Exception):
                failed_markets.append(market)
            elif (metric := calculate_radar_metric(market, candles)) is not None:
                metrics.append(metric)
        return metrics, failed_markets

    @staticmethod
    def _serialize(
        metrics: list[RadarMetric], field: str, *, reverse: bool, limit: int
    ) -> list[dict]:
        return [
            {
                "market": MarketSerializer(metric.market).data,
                "change_percent": str(metric.change_percent),
                "quote_volume": str(metric.quote_volume),
                "volatility_percent": str(metric.volatility_percent),
            }
            for metric in sorted(
                metrics, key=lambda metric: getattr(metric, field), reverse=reverse
            )[:limit]
        ]
