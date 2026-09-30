import json
import logging
import os
from datetime import UTC, datetime

from .middleware import request_id


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        data = {
            "timestamp": datetime.now(UTC).isoformat(),
            "level": record.levelname,
            "service": os.environ.get("SERVICE_NAME", "web"),
            "event": record.getMessage(),
            "request_id": request_id.get(),
        }
        for name in ("method", "path", "status", "duration_ms", "market_id", "alert_id"):
            value = getattr(record, name, None)
            if value is not None:
                data[name] = value
        if record.exc_info:
            data["exception"] = self.formatException(record.exc_info)
        return json.dumps(data, ensure_ascii=False)
