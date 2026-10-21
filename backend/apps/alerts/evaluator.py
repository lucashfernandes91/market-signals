from collections.abc import Iterable, Mapping, Sequence
from datetime import datetime
from decimal import Decimal, InvalidOperation

from .models import Alert, AlertCondition


def _compare(value: Decimal, operator: str, threshold: Decimal) -> bool:
    operations: dict[str, bool] = {
        AlertCondition.Operator.GREATER_THAN: value > threshold,
        AlertCondition.Operator.GREATER_THAN_OR_EQUAL: value >= threshold,
        AlertCondition.Operator.LESS_THAN: value < threshold,
        AlertCondition.Operator.LESS_THAN_OR_EQUAL: value <= threshold,
    }
    return operations.get(operator, False)


def _variation(
    *,
    field: str,
    current: Decimal,
    timestamp: datetime,
    window_seconds: int,
    history: Sequence[Mapping[str, str]],
) -> Decimal | None:
    cutoff = timestamp.timestamp() - window_seconds
    baseline = None
    for point in history:
        try:
            point_timestamp = datetime.fromisoformat(point["timestamp"]).timestamp()
            if point_timestamp <= cutoff:
                baseline = Decimal(point[field])
        except (KeyError, ValueError, InvalidOperation):
            continue
    if baseline in (None, 0):
        return None
    return (current - baseline) / baseline * 100


def observed_value_for_condition(
    condition: AlertCondition,
    market_data: Mapping[str, str],
    history: Sequence[Mapping[str, str]] = (),
) -> Decimal | None:
    field_by_type: dict[str, str] = {
        AlertCondition.Type.PRICE_ABOVE: "price",
        AlertCondition.Type.PRICE_BELOW: "price",
        AlertCondition.Type.PRICE_CHANGE_PERCENT: "price_change_percent",
        AlertCondition.Type.VOLUME_CHANGE_PERCENT: "volume_change_percent",
    }
    field = field_by_type.get(condition.condition_type)
    is_variation = condition.condition_type in (
        AlertCondition.Type.PRICE_CHANGE_PERCENT,
        AlertCondition.Type.VOLUME_CHANGE_PERCENT,
    )
    if field is None or (not is_variation and field not in market_data):
        return None

    try:
        if is_variation and field in market_data and "timestamp" not in market_data:
            return Decimal(market_data[field])
        observed_field = (
            "price"
            if condition.condition_type == AlertCondition.Type.PRICE_CHANGE_PERCENT
            else "volume_24h"
            if condition.condition_type == AlertCondition.Type.VOLUME_CHANGE_PERCENT
            else field
        )
        observed = Decimal(market_data[observed_field])
        if is_variation:
            timestamp = datetime.fromisoformat(market_data["timestamp"])
            observed = _variation(
                field="price"
                if condition.condition_type == AlertCondition.Type.PRICE_CHANGE_PERCENT
                else "volume_24h",
                current=observed,
                timestamp=timestamp,
                window_seconds=condition.window_seconds or 3600,
                history=history,
            )
            if observed is None:
                return None
    except (InvalidOperation, KeyError, TypeError, ValueError):
        return None
    return observed


def evaluate_condition(
    condition: AlertCondition,
    market_data: Mapping[str, str],
    history: Sequence[Mapping[str, str]] = (),
) -> bool:
    observed = observed_value_for_condition(condition, market_data, history)
    if observed is None:
        return False
    return _compare(observed, condition.operator, condition.value_numeric)


def evaluate_alert(
    *,
    logic: str,
    conditions: Iterable[AlertCondition],
    market_data: Mapping[str, str],
    history: Sequence[Mapping[str, str]] = (),
) -> bool:
    results = [evaluate_condition(condition, market_data, history) for condition in conditions]
    if not results:
        return False
    if logic == Alert.Logic.OR:
        return any(results)
    return all(results)
