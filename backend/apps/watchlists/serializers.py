from rest_framework import serializers

from apps.market.serializers import MarketSerializer

from .models import Watchlist, WatchlistItem


class WatchlistItemSerializer(serializers.ModelSerializer):
    market = MarketSerializer(read_only=True)

    class Meta:
        model = WatchlistItem
        fields = ("market", "position", "created_at")


class WatchlistSerializer(serializers.ModelSerializer):
    items = WatchlistItemSerializer(many=True, read_only=True)

    class Meta:
        model = Watchlist
        fields = ("id", "name", "is_default", "items", "created_at", "updated_at")
        read_only_fields = ("id", "items", "created_at", "updated_at")

    def validate_is_default(self, value):
        defaults = Watchlist.objects.filter(
            user=self.context["request"].user,
            is_default=True,
        )
        if self.instance is not None:
            defaults = defaults.exclude(pk=self.instance.pk)
        if value and defaults.exists():
            raise serializers.ValidationError("Já existe uma lista padrão.")
        return value
