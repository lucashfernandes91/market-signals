from decimal import Decimal

from django.test import SimpleTestCase

from apps.alerts.evaluator import evaluate_alert, evaluate_condition
from apps.alerts.models import Alert, AlertCondition


class AlertEvaluatorTests(SimpleTestCase):
    def condition(self, condition_type, operator, value):
        return AlertCondition(
            condition_type=condition_type,
            operator=operator,
            value_numeric=Decimal(value),
        )

    def test_price_above(self):
        condition = self.condition(
            AlertCondition.Type.PRICE_ABOVE,
            AlertCondition.Operator.GREATER_THAN,
            "70000",
        )

        self.assertTrue(evaluate_condition(condition, {"price": "70000.01"}))
        self.assertFalse(evaluate_condition(condition, {"price": "70000"}))

    def test_price_below(self):
        condition = self.condition(
            AlertCondition.Type.PRICE_BELOW,
            AlertCondition.Operator.LESS_THAN,
            "60000",
        )

        self.assertTrue(evaluate_condition(condition, {"price": "59999.99"}))
        self.assertFalse(evaluate_condition(condition, {"price": "60000"}))

    def test_and_requires_all_conditions(self):
        conditions = [
            self.condition(
                AlertCondition.Type.PRICE_ABOVE,
                AlertCondition.Operator.GREATER_THAN,
                "100",
            ),
            self.condition(
                AlertCondition.Type.VOLUME_CHANGE_PERCENT,
                AlertCondition.Operator.GREATER_THAN,
                "50",
            ),
        ]

        self.assertTrue(
            evaluate_alert(
                logic=Alert.Logic.AND,
                conditions=conditions,
                market_data={"price": "101", "volume_change_percent": "51"},
            )
        )
        self.assertFalse(
            evaluate_alert(
                logic=Alert.Logic.AND,
                conditions=conditions,
                market_data={"price": "101", "volume_change_percent": "49"},
            )
        )
