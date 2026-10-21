import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:market_radar/core/preferences/app_preferences.dart';
import 'package:market_radar/features/favorites/data/favorite_store.dart';
import 'package:market_radar/features/radar/presentation/radar_screen.dart';

Map<String, dynamic> item(String name, String symbol, String change) => {
      'market': {
        'id': symbol,
        'canonical_symbol': '$symbol-USDT',
        'base_asset': {'symbol': symbol, 'name': name},
        'quote_asset': {'symbol': 'USDT'}
      },
      'change_percent': change,
      'quote_volume': '1500000',
      'volatility_percent': '1.25',
    };

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('Radar separa altas de quedas e mostra unidade no volume',
      (tester) async {
    final positive = item('Bitcoin', 'BTC', '2.50');
    final negative = item('Ethereum', 'ETH', '-1.50');
    await tester.pumpWidget(ProviderScope(overrides: [
      preferenceStoreProvider.overrideWithValue(MemoryPreferenceStore()),
      favoriteStoreProvider.overrideWithValue(MemoryFavoriteStore()),
      radarProvider.overrideWith((ref) async => {
            'gainers': [positive, negative],
            'losers': [negative, positive],
            'volume': [positive],
            'volatility': [positive],
          }),
    ], child: const MaterialApp(home: Scaffold(body: RadarScreen()))));
    await tester.pumpAndSettle();
    expect(find.text('Maiores altas'), findsOneWidget);
    expect(find.text('Bitcoin'), findsOneWidget);
    expect(find.text('Ethereum'), findsNothing);
    expect(find.text('+2,50%'), findsOneWidget);
    await tester.tap(find.text('Quedas'));
    await tester.pumpAndSettle();
    expect(find.text('Bitcoin'), findsNothing);
    expect(find.text('Ethereum'), findsOneWidget);
    expect(find.text('-1,50%'), findsOneWidget);
    await tester.tap(find.text('Volume'));
    await tester.pumpAndSettle();
    expect(find.text('1,50 mi'), findsOneWidget);
    expect(find.text('BRL'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Radar vazio tem um estado claro sem repetir quatro erros',
      (tester) async {
    await tester.pumpWidget(ProviderScope(overrides: [
      preferenceStoreProvider.overrideWithValue(MemoryPreferenceStore()),
      favoriteStoreProvider.overrideWithValue(MemoryFavoriteStore()),
      radarProvider.overrideWith((ref) async => {}),
    ], child: const MaterialApp(home: Scaffold(body: RadarScreen()))));
    await tester.pumpAndSettle();
    expect(find.text('Nenhum movimento nesta categoria'), findsOneWidget);
  });
}
