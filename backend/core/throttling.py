import re

from django.core.exceptions import ImproperlyConfigured
from rest_framework.throttling import AnonRateThrottle, SimpleRateThrottle, UserRateThrottle
from rest_framework_simplejwt.exceptions import TokenError
from rest_framework_simplejwt.tokens import RefreshToken


class AuthenticatedApiRateThrottle(UserRateThrottle):
    scope = "authenticated_api"


class ExtendedRateThrottleMixin:
    def parse_rate(self, rate: str | None) -> tuple[int | None, int | None]:
        if rate is None:
            return None, None

        match = re.fullmatch(
            r"(?P<count>\d+)\s*/\s*(?:(?P<interval>\d+)\s*)?"
            r"(?P<unit>seconds?|secs?|s|minutes?|mins?|m|hours?|hrs?|h|days?|d)",
            rate.strip(),
            re.IGNORECASE,
        )
        if match is None:
            raise ImproperlyConfigured(f"Invalid throttle rate: {rate!r}")

        unit_seconds = {"s": 1, "m": 60, "h": 3600, "d": 86400}
        interval = int(match.group("interval") or 1)
        duration = interval * unit_seconds[match.group("unit")[0].lower()]
        return int(match.group("count")), duration


class LoginRateThrottle(ExtendedRateThrottleMixin, AnonRateThrottle):
    scope = "login"


class RefreshRateThrottle(ExtendedRateThrottleMixin, SimpleRateThrottle):
    scope = "refresh"

    def get_cache_key(self, request, view):
        refresh = request.data.get("refresh") if isinstance(request.data, dict) else None
        if isinstance(refresh, str) and refresh:
            try:
                user_id = RefreshToken(refresh)["user_id"]
            except (TokenError, KeyError):
                user_id = None
            if user_id:
                return self.cache_format % {"scope": self.scope, "ident": user_id}
        return self.cache_format % {"scope": self.scope, "ident": self.get_ident(request)}
