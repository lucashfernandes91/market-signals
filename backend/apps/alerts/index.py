from collections import defaultdict

from apps.alerts.models import Alert
from infrastructure.redis.client import get_redis_client
from infrastructure.redis.keys import alerts_index_key


def rebuild_alert_index() -> int:
    grouped: dict[str, list[str]] = defaultdict(list)
    for alert_id, market_id in Alert.objects.filter(status=Alert.Status.ACTIVE).values_list(
        "id", "market_id"
    ):
        grouped[str(market_id)].append(str(alert_id))

    redis = get_redis_client()
    try:
        keys = list(redis.scan_iter(match=alerts_index_key("*")))
        with redis.pipeline(transaction=True) as pipe:
            if keys:
                pipe.delete(*keys)
            for market_id, alert_ids in grouped.items():
                pipe.sadd(alerts_index_key(market_id), *alert_ids)
            pipe.execute()
    finally:
        redis.close()
    return sum(map(len, grouped.values()))
