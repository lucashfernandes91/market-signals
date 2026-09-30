import logging
import re
import time
import uuid
from contextvars import ContextVar

request_id: ContextVar[str] = ContextVar("request_id", default="-")
logger = logging.getLogger(__name__)
VALID_REQUEST_ID = re.compile(r"^[A-Za-z0-9._-]{1,128}$")


class RequestIdMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        supplied = request.headers.get("X-Request-ID", "")
        current_id = supplied if VALID_REQUEST_ID.fullmatch(supplied) else uuid.uuid4().hex
        token = request_id.set(current_id)
        started = time.perf_counter()
        try:
            response = self.get_response(request)
            response["X-Request-ID"] = current_id
            logger.info(
                "http.request",
                extra={
                    "method": request.method,
                    "path": request.path,
                    "status": response.status_code,
                    "duration_ms": round((time.perf_counter() - started) * 1000, 2),
                },
            )
            return response
        finally:
            request_id.reset(token)
