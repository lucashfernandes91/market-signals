import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_radar/features/alerts/presentation/alerts_screen.dart';
import 'package:market_radar/features/notifications/presentation/notifications_screen.dart';
import 'package:market_radar/features/watchlists/presentation/watchlists_screen.dart';

void main() {
  testWidgets('Alertas visitante mostra CTA sem abrir autenticação',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: AlertsScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Alertas precisam de uma conta'), findsOneWidget);
    expect(find.text('Entrar ou criar conta'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Notificações vazias têm estado estável', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        notificationsProvider.overrideWith((ref) async => const []),
      ],
      child: const MaterialApp(home: NotificationsScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Nenhuma notificação'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Watchlists vazias têm estado estável', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        watchlistsProvider.overrideWith((ref) async => const []),
      ],
      child: const MaterialApp(home: WatchlistsScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Crie sua primeira lista'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Criar lista'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
