from rest_framework.routers import DefaultRouter

from .views import WatchlistViewSet

app_name = "watchlists"

router = DefaultRouter()
router.register("", WatchlistViewSet, basename="watchlist")

urlpatterns = router.urls
