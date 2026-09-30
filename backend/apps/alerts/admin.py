from django.contrib import admin

from .models import Alert, AlertCondition, AlertEvent


class AlertConditionInline(admin.TabularInline):
    model = AlertCondition
    extra = 0


@admin.register(Alert)
class AlertAdmin(admin.ModelAdmin):
    list_display = ("name", "user", "market", "status", "last_triggered_at")
    list_filter = ("status", "logic")
    search_fields = ("name", "user__email", "market__canonical_symbol")
    inlines = (AlertConditionInline,)


@admin.register(AlertCondition)
class AlertConditionAdmin(admin.ModelAdmin):
    list_display = ("alert", "condition_type", "operator", "value_numeric", "position")
    list_filter = ("condition_type", "operator")


@admin.register(AlertEvent)
class AlertEventAdmin(admin.ModelAdmin):
    list_display = ("alert", "market", "triggered_at", "notification_status")
    list_filter = ("notification_status",)
    readonly_fields = ("created_at", "updated_at")
