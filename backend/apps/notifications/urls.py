from django.urls import path

from .views import DeviceDetailView, NotificationListView, NotificationOpenedView

app_name = "notifications"

urlpatterns = [
    path("devices/<str:device_id>/", DeviceDetailView.as_view(), name="device-detail"),
    path("notifications/", NotificationListView.as_view(), name="notification-list"),
    path(
        "notifications/<uuid:pk>/opened/",
        NotificationOpenedView.as_view(),
        name="notification-opened",
    ),
]
