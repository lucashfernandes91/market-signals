from django.contrib import admin

from .models import Device, Notification


@admin.register(Device)
class DeviceAdmin(admin.ModelAdmin):
    list_display = ("user", "platform", "provider", "enabled", "last_seen_at")
    list_filter = ("platform", "provider", "enabled")
    search_fields = ("user__email", "device_id", "token")


@admin.register(Notification)
class NotificationAdmin(admin.ModelAdmin):
    list_display = ("title", "user", "type", "status", "sent_at", "opened_at")
    list_filter = ("type", "status")
    search_fields = ("title", "user__email")
    readonly_fields = ("created_at", "updated_at")
