from rest_framework import serializers

from apps.market.serializers import MarketSerializer

from .models import Alert, AlertCondition, AlertEvent


class AlertConditionSerializer(serializers.ModelSerializer):
    class Meta:
        model = AlertCondition
        fields = ("id", "condition_type", "operator", "value_numeric", "window_seconds", "position")
        read_only_fields = ("id",)


class AlertEventSerializer(serializers.ModelSerializer):
    class Meta:
        model = AlertEvent
        fields = ("id", "observed_value", "context", "triggered_at", "notification_status")


class AlertSerializer(serializers.ModelSerializer):
    market = MarketSerializer(read_only=True)
    market_id = serializers.UUIDField(write_only=True)
    conditions = AlertConditionSerializer(many=True)

    class Meta:
        model = Alert
        fields = (
            "id",
            "market",
            "market_id",
            "name",
            "status",
            "logic",
            "cooldown_seconds",
            "last_triggered_at",
            "conditions",
            "created_at",
            "updated_at",
        )
        read_only_fields = ("id", "market", "last_triggered_at", "created_at", "updated_at")

    def validate(self, attrs):
        conditions = attrs.get("conditions")
        if self.instance is None and not conditions:
            raise serializers.ValidationError({"conditions": "Informe ao menos uma condição."})
        for condition in conditions or []:
            condition_type = condition.get("condition_type")
            window_seconds = condition.get("window_seconds")
            if condition_type in {
                AlertCondition.Type.PRICE_CHANGE_PERCENT,
                AlertCondition.Type.VOLUME_CHANGE_PERCENT,
            } and (window_seconds is None or window_seconds <= 0):
                raise serializers.ValidationError(
                    {"conditions": "Condições percentuais exigem uma janela positiva."}
                )
            if (
                condition_type
                in {
                    AlertCondition.Type.PRICE_ABOVE,
                    AlertCondition.Type.PRICE_BELOW,
                }
                and window_seconds is not None
            ):
                raise serializers.ValidationError(
                    {"conditions": "Condições de preço não aceitam janela."}
                )
        return attrs

    def create(self, validated_data):
        conditions = validated_data.pop("conditions")
        market_id = validated_data.pop("market_id")
        alert = Alert.objects.create(
            user=self.context["request"].user,
            market_id=market_id,
            **validated_data,
        )
        AlertCondition.objects.bulk_create(
            [AlertCondition(alert=alert, **condition) for condition in conditions]
        )
        return alert

    def update(self, instance, validated_data):
        conditions = validated_data.pop("conditions", None)
        validated_data.pop("market_id", None)
        for field, value in validated_data.items():
            setattr(instance, field, value)
        instance.save()
        if conditions is not None:
            instance.conditions.all().delete()
            AlertCondition.objects.bulk_create(
                [AlertCondition(alert=instance, **condition) for condition in conditions]
            )
        return instance
