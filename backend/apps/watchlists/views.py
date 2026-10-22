from django.db import transaction
from django.shortcuts import get_object_or_404
from rest_framework import status, viewsets
from rest_framework.decorators import action
from rest_framework.response import Response

from apps.market.models import Market

from .models import Watchlist, WatchlistItem
from .serializers import WatchlistSerializer


class WatchlistViewSet(viewsets.ModelViewSet):
    serializer_class = WatchlistSerializer

    def get_queryset(self):
        return Watchlist.objects.filter(user=self.request.user).prefetch_related(
            "items__market__base_asset", "items__market__quote_asset"
        )

    def perform_create(self, serializer):
        serializer.save(user=self.request.user)

    @action(detail=True, methods=("post",), url_path="items")
    def add_item(self, request, pk=None):
        market = get_object_or_404(
            Market.objects.filter(is_active=True),
            pk=request.data.get("market_id"),
        )
        position = request.data.get("position", 0)
        item, created = WatchlistItem.objects.get_or_create(
            watchlist=self.get_object(),
            market=market,
            defaults={"position": position},
        )
        if not created:
            return Response(
                {"detail": "O mercado já está na lista."},
                status=status.HTTP_409_CONFLICT,
            )
        return Response(WatchlistSerializer(self.get_object()).data, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=("post",), url_path="items/batch")
    @transaction.atomic
    def add_items_batch(self, request, pk=None):
        watchlist = self.get_object()
        market_ids = request.data.get("market_ids")
        if not isinstance(market_ids, list) or not market_ids or len(market_ids) > 100:
            return Response(
                {"detail": "market_ids deve conter entre 1 e 100 IDs."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        unique_ids = list(dict.fromkeys(str(market_id) for market_id in market_ids))
        markets = list(Market.objects.filter(is_active=True, id__in=unique_ids))
        if len(markets) != len(unique_ids):
            return Response(
                {"detail": "Um ou mais mercados não estão disponíveis."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        position = watchlist.items.count()
        for market in markets:
            WatchlistItem.objects.get_or_create(
                watchlist=watchlist,
                market=market,
                defaults={"position": position},
            )
            position += 1
        return Response(WatchlistSerializer(watchlist).data)

    @action(detail=True, methods=("post",), url_path="copy")
    @transaction.atomic
    def copy_watchlist(self, request, pk=None):
        source = self.get_object()
        name = str(request.data.get("name") or f"Cópia de {source.name}").strip()
        if not name or len(name) > 80:
            return Response(
                {"detail": "Informe um nome de lista válido."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if Watchlist.objects.filter(user=request.user, name=name).exists():
            return Response(
                {"detail": "Já existe uma lista com esse nome."},
                status=status.HTTP_409_CONFLICT,
            )
        copied = Watchlist.objects.create(user=request.user, name=name, is_default=False)
        WatchlistItem.objects.bulk_create(
            [
                WatchlistItem(
                    watchlist=copied,
                    market_id=item.market_id,
                    position=item.position,
                )
                for item in source.items.all()
            ]
        )
        return Response(WatchlistSerializer(copied).data, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=("delete",), url_path=r"items/(?P<market_id>[^/.]+)")
    def remove_item(self, request, market_id=None, pk=None):
        item = get_object_or_404(WatchlistItem, watchlist=self.get_object(), market_id=market_id)
        item.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)

    @action(detail=True, methods=("patch",), url_path="items/order")
    def order_items(self, request, pk=None):
        watchlist = self.get_object()
        market_ids = request.data.get("market_ids")
        if not isinstance(market_ids, list):
            return Response(
                {"detail": "market_ids deve ser uma lista."}, status=status.HTTP_400_BAD_REQUEST
            )
        items = {str(item.market_id): item for item in watchlist.items.all()}
        if set(market_ids) != set(items):
            return Response(
                {"detail": "A ordenação deve conter todos os mercados da lista."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        for position, market_id in enumerate(market_ids):
            items[market_id].position = position
        WatchlistItem.objects.bulk_update(items.values(), ["position"])
        return Response(WatchlistSerializer(self.get_object()).data)
