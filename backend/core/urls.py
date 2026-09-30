from django.contrib import admin
from django.urls import include, path

from core.views import live, ready, status

urlpatterns = [
    path("admin/", admin.site.urls),
    path("health/live/", live, name="health-live"),
    path("health/ready/", ready, name="health-ready"),
    path("api/v1/status/", status, name="api-status"),
    path("api/v1/auth/", include("apps.users.urls")),
]
