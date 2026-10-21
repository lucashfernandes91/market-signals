import asyncio
import time

from django.core.management.base import BaseCommand, CommandError

from apps.market.catalog import CatalogPolicy, fetch_configured_catalog, sync_catalog


class Command(BaseCommand):
    help = "Sincroniza o catálogo de pares ativos da Binance"

    def add_arguments(self, parser):
        parser.add_argument("--loop", action="store_true")
        parser.add_argument("--interval", type=int, default=300)

    def handle(self, *args, **options):
        if options["loop"] and options["interval"] < 10:
            raise CommandError("--interval deve ser de pelo menos 10 segundos.")
        while True:
            provider, catalog = asyncio.run(fetch_configured_catalog())
            result = sync_catalog(
                provider=provider,
                catalog=catalog,
                policy=CatalogPolicy.from_environment(),
            )
            self.stdout.write(
                self.style.SUCCESS(
                    "Catálogo sincronizado: "
                    f"{result.allowed}/{result.discovered} pares permitidos; "
                    f"{result.provider_markets_created} novos; "
                    f"{result.deactivated} desativados."
                )
            )
            if not options["loop"]:
                return
            time.sleep(options["interval"])
