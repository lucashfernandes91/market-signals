from django.urls import path

from .views import (
    MarketCandlesView,
    MarketDetailView,
    MarketListView,
    MarketLookupView,
    MarketOverviewView,
    MarketQuoteView,
    MarketRadarView,
    MarketRatesView,
)

app_name = "market"

urlpatterns = [
    path("radar/", MarketRadarView.as_view(), name="radar"),
    path("rates/", MarketRatesView.as_view(), name="rates"),
    path("lookup/", MarketLookupView.as_view(), name="lookup"),
    path("overview/", MarketOverviewView.as_view(), name="overview"),
    path("", MarketListView.as_view(), name="list"),
    path("<uuid:pk>/", MarketDetailView.as_view(), name="detail"),
    path("<uuid:pk>/quote/", MarketQuoteView.as_view(), name="quote"),
    path("<uuid:pk>/candles/", MarketCandlesView.as_view(), name="candles"),
]
