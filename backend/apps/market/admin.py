from django.contrib import admin

from .models import Asset, Market, ProviderMarket


@admin.register(Asset)
class AssetAdmin(admin.ModelAdmin):
    list_display = ("symbol", "name", "asset_type", "is_active")
    list_filter = ("asset_type", "is_active")
    search_fields = ("symbol", "name", "slug")


@admin.register(Market)
class MarketAdmin(admin.ModelAdmin):
    list_display = ("canonical_symbol", "base_asset", "quote_asset", "is_active")
    list_filter = ("is_active",)
    search_fields = ("canonical_symbol",)


@admin.register(ProviderMarket)
class ProviderMarketAdmin(admin.ModelAdmin):
    list_display = ("provider", "external_symbol", "market", "is_active")
    list_filter = ("provider", "is_active")
    search_fields = ("external_symbol", "market__canonical_symbol")
