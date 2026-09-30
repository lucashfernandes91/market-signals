from uuid import UUID

PREFIX = "market-radar"


def market_state_key(market_id: UUID | str) -> str:
    return f"{PREFIX}:market:state:{market_id}"


def market_events_stream() -> str:
    return f"{PREFIX}:stream:market-events"


def notification_jobs_stream() -> str:
    return f"{PREFIX}:stream:notification-jobs"


def alerts_index_key(market_id: UUID | str) -> str:
    return f"{PREFIX}:alerts:index:{market_id}"


def dead_letter_stream() -> str:
    return f"{PREFIX}:stream:dead-letter"


def retry_key(group: str, message_id: str) -> str:
    return f"{PREFIX}:retry:{group}:{message_id}"
