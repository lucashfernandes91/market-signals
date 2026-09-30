from collections.abc import Iterable, Mapping
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


def evaluate_condition(condition: AlertCondition, market_data: Mapping[str, str]) -> bool:
    field_by_type: dict[str, str] = {
        AlertCondition.Type.PRICE_ABOVE: "price",
        AlertCondition.Type.PRICE_BELOW: "price",
        AlertCondition.Type.PRICE_CHANGE_PERCENT: "price_change_percent",
        AlertCondition.Type.VOLUME_CHANGE_PERCENT: "volume_change_percent",
    }
    field = field_by_type.get(condition.condition_type)
    if field is None or field not in market_data:
        return False

    try:
        observed = Decimal(market_data[field])
    except (InvalidOperation, TypeError):
        return False
    return _compare(observed, condition.operator, condition.value_numeric)


def evaluate_alert(
    *,
    logic: str,
    conditions: Iterable[AlertCondition],
    market_data: Mapping[str, str],
) -> bool:
    results = [evaluate_condition(condition, market_data) for condition in conditions]
    if not results:
        return False
    if logic == Alert.Logic.OR:
        return any(results)
    return all(results)
