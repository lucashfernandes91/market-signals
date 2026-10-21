from rest_framework import serializers

from .models import Device, Notification


class DeviceSerializer(serializers.ModelSerializer):
    class Meta:
        model = Device
        fields = ("device_id", "platform", "provider", "token", "enabled", "last_seen_at")
        read_only_fields = ("last_seen_at",)

    def validate_device_id(self, value):
        if not value.strip():
            raise serializers.ValidationError("Informe o identificador do dispositivo.")
        return value.strip()


class NotificationSerializer(serializers.ModelSerializer):
    class Meta:
        model = Notification
        fields = (
            "id",
            "type",
            "title",
            "body",
            "payload",
            "status",
            "sent_at",
            "opened_at",
            "created_at",
        )
        read_only_fields = fields
