from django.conf import settings
from django.db import models

from apps.common.models import UUIDTimeStampedModel
from apps.market.models import Market


class Watchlist(UUIDTimeStampedModel):
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="watchlists",
    )
    name = models.CharField(max_length=80)
    is_default = models.BooleanField(default=False)

    class Meta:
        ordering = ("name",)
        constraints = [
            models.UniqueConstraint(
                fields=("user", "name"),
                name="watchlist_unique_name_per_user",
            ),
            models.UniqueConstraint(
                fields=("user",),
                condition=models.Q(is_default=True),
                name="watchlist_single_default_per_user",
            ),
        ]

    def __str__(self) -> str:
        return f"{self.user.email}: {self.name}"


class WatchlistItem(UUIDTimeStampedModel):
    watchlist = models.ForeignKey(Watchlist, on_delete=models.CASCADE, related_name="items")
    market = models.ForeignKey(Market, on_delete=models.CASCADE, related_name="watchlist_items")
    position = models.PositiveIntegerField(default=0)

    class Meta:
        ordering = ("position", "created_at")
        constraints = [
            models.UniqueConstraint(
                fields=("watchlist", "market"),
                name="watchlist_item_unique_market",
            )
        ]

    def __str__(self) -> str:
        return f"{self.watchlist}: {self.market}"
