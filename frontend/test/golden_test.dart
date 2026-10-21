import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_radar/core/preferences/app_preferences.dart';
import 'package:market_radar/core/theme/app_theme.dart';
import 'package:market_radar/features/favorites/data/favorite_store.dart';
import 'package:market_radar/features/market/models/market.dart';
import 'package:market_radar/features/market/presentation/market_screen.dart';

const _btc = Market(
    id: 'btc',
    symbol: 'BTC-USDT',
    base: 'BTC',
    quote: 'USDT',
    name: 'Bitcoin',
    change24hPercent: '2.31',
    price: '65432.10',
    volume24h: '1500000');

Widget _screen(ThemeData theme) => ProviderScope(
      overrides: [
        preferenceStoreProvider.overrideWithValue(MemoryPreferenceStore(
          AppPreferences(onboardingComplete: true),
        )),
        favoriteStoreProvider.overrideWithValue(MemoryFavoriteStore()),
        marketsProvider.overrideWith((ref) async => [_btc]),
        marketOverviewProvider.overrideWith((ref) async => [_btc]),
        marketClockProvider
            .overrideWith((ref) => Stream.value(DateTime(2026, 10, 1, 12))),
        currencyConversionProvider.overrideWith((ref) async =>
            const CurrencyConversion(currency: DisplayCurrency.brl, rate: 1)),
        marketQuotesProvider.overrideWith((ref) => Stream.value({
              'btc': {
                'price': '65432.10',
                'change_24h_percent': '2.31',
                'volume_24h': '1500000',
                'timestamp': DateTime.now().toIso8601String(),
              },
            })),
      ],
      child: MaterialApp(
        theme: theme,
        home: const Scaffold(body: MarketScreen()),
      ),
    );

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('Mercado tema claro', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(_screen(AppTheme.light));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/market_light.png'));
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('Mercado tema escuro', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(_screen(AppTheme.dark));
    await tester.pumpAndSettle();
    await expectLater(
        find.byType(MaterialApp), matchesGoldenFile('goldens/market_dark.png'));
    await tester.binding.setSurfaceSize(null);
  });
}
