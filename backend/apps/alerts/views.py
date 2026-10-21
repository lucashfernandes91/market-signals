from django.shortcuts import get_object_or_404
from redis.exceptions import RedisError
from rest_framework import status, viewsets
from rest_framework.decorators import action
from rest_framework.response import Response

from apps.market.models import Market

from .index import rebuild_alert_index
from .models import Alert
from .serializers import AlertEventSerializer, AlertSerializer


class AlertViewSet(viewsets.ModelViewSet):
    serializer_class = AlertSerializer

    def get_queryset(self):
        return (
            Alert.objects.filter(user=self.request.user)
            .select_related("market__base_asset", "market__quote_asset")
            .prefetch_related("conditions")
        )

    def perform_create(self, serializer):
        market = get_object_or_404(
            Market.objects.filter(is_active=True),
            pk=serializer.validated_data["market_id"],
        )
        serializer.save(market_id=market.id)
        self._refresh_index()

    def perform_update(self, serializer):
        serializer.save()
        self._refresh_index()

    def perform_destroy(self, instance):
        super().perform_destroy(instance)
        self._refresh_index()

    def _refresh_index(self):
        try:
            rebuild_alert_index()
        except RedisError:
            return None

    @action(detail=True, methods=("post",))
    def pause(self, request, pk=None):
        alert = self.get_object()
        alert.status = Alert.Status.PAUSED
        alert.save(update_fields=("status", "updated_at"))
        self._refresh_index()
        return Response(AlertSerializer(alert).data)

    @action(detail=True, methods=("post",))
    def resume(self, request, pk=None):
        alert = self.get_object()
        alert.status = Alert.Status.ACTIVE
        alert.save(update_fields=("status", "updated_at"))
        self._refresh_index()
        return Response(AlertSerializer(alert).data)

    @action(detail=True, methods=("get",))
    def events(self, request, pk=None):
        events = self.get_object().events.all()
        return Response(AlertEventSerializer(events, many=True).data, status=status.HTTP_200_OK)
