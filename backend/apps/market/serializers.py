from rest_framework import serializers

from .models import Asset, Market


class AssetSerializer(serializers.ModelSerializer):
    class Meta:
        model = Asset
        fields = ("id", "symbol", "name", "slug", "asset_type")


class MarketSerializer(serializers.ModelSerializer):
    base_asset = AssetSerializer(read_only=True)
    quote_asset = AssetSerializer(read_only=True)

    class Meta:
        model = Market
        fields = ("id", "canonical_symbol", "base_asset", "quote_asset", "is_active")


class MarketOverviewSerializer(serializers.Serializer):
    market_id = serializers.UUIDField()
    provider_market_id = serializers.UUIDField(allow_null=True)
    asset_name = serializers.CharField()
    asset_symbol = serializers.CharField()
    canonical_symbol = serializers.CharField()
    provider = serializers.CharField()
    provider_name = serializers.CharField()
    provider_symbol = serializers.CharField()
    price = serializers.CharField(allow_null=True)
    change_24h_percent = serializers.CharField(allow_null=True)
    volume_24h = serializers.CharField(allow_null=True)
    timestamp = serializers.CharField(allow_null=True)
    provider_timestamp = serializers.CharField(allow_null=True)
    received_at = serializers.CharField(allow_null=True)
    stale = serializers.BooleanField(allow_null=True)
    source_status = serializers.ChoiceField(choices=("live", "stale", "unavailable"))
