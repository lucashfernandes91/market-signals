from django.contrib import admin
from django.urls import include, path

from core.views import live, ready, status

admin.site.site_header = "Administração do Market Radar"
admin.site.site_title = "Market Radar | Administração"
admin.site.index_title = "Painel de administração"

urlpatterns = [
    path("admin/", admin.site.urls),
    path("health/live/", live, name="health-live"),
    path("health/ready/", ready, name="health-ready"),
    path("api/v1/status/", status, name="api-status"),
    path("api/v1/auth/", include("apps.users.urls")),
    path("api/v1/markets/", include("apps.market.urls")),
    path("api/v1/watchlists/", include("apps.watchlists.urls")),
    path("api/v1/alerts/", include("apps.alerts.urls")),
    path("api/v1/", include("apps.notifications.urls")),
]
