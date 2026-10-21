from django.conf import settings
from django.db import models

from apps.common.models import UUIDTimeStampedModel
from apps.market.models import Market


class Watchlist(UUIDTimeStampedModel):
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="watchlists",
        verbose_name="usuário",
    )
    name = models.CharField("nome", max_length=80)
    is_default = models.BooleanField("padrão", default=False)

    class Meta:
        verbose_name = "lista de acompanhamento"
        verbose_name_plural = "listas de acompanhamento"
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
    watchlist = models.ForeignKey(
        Watchlist,
        on_delete=models.CASCADE,
        related_name="items",
        verbose_name="lista de acompanhamento",
    )
    market = models.ForeignKey(
        Market, on_delete=models.CASCADE, related_name="watchlist_items", verbose_name="mercado"
    )
    position = models.PositiveIntegerField("posição", default=0)

    class Meta:
        verbose_name = "item da lista de acompanhamento"
        verbose_name_plural = "itens das listas de acompanhamento"
        ordering = ("position", "created_at")
        constraints = [
            models.UniqueConstraint(
                fields=("watchlist", "market"),
                name="watchlist_item_unique_market",
            )
        ]

    def __str__(self) -> str:
        return f"{self.watchlist}: {self.market}"
