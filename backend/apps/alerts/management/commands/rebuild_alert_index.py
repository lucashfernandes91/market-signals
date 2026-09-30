from django.core.management.base import BaseCommand

from apps.alerts.index import rebuild_alert_index


class Command(BaseCommand):
    help = "Reconstrói o índice Redis dos alertas ativos"

    def handle(self, *args, **options):
        count = rebuild_alert_index()
        self.stdout.write(self.style.SUCCESS(f"{count} alertas ativos indexados."))
