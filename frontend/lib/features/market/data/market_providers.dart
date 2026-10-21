import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/preferences/app_preferences.dart';
import '../../../core/session/session_controller.dart';
import '../../../core/websocket/market_websocket_client.dart';
import '../../favorites/data/favorite_store.dart';
import '../models/market.dart';
import 'market_repository.dart';

final marketRepositoryProvider = Provider<MarketRepository>(
  (ref) => MarketRepository(ref.watch(apiClientProvider)),
);

final marketWebSocketClientProvider = Provider<MarketWebSocketClient>(
  (ref) {
    final client = MarketWebSocketClient(
      tokenStorage: ref.watch(tokenStorageProvider),
      refreshToken: ref.watch(apiClientProvider).refreshAccessToken,
    );
    ref.onDispose(client.dispose);
    return client;
  },
);

final marketConnectionStatusProvider =
    StreamProvider.autoDispose<MarketConnectionStatus>((ref) {
  return ref.watch(marketWebSocketClientProvider).status;
});

final marketsProvider = FutureProvider<List<Market>>(
  (ref) => ref
      .watch(marketRepositoryProvider)
      .list()
      .timeout(const Duration(seconds: 12)),
);

final marketOverviewProvider = FutureProvider<List<Market>>((ref) async {
  final markets = await ref.watch(marketsProvider.future);
  try {
    final values = await Future.wait([
      ref.watch(marketRepositoryProvider).overview(
            markets.map((market) => market.id),
          ),
      ref.watch(currencyConversionProvider.future),
    ]);
    final overview = values[0] as List<Market>;
    final conversion = values[1] as CurrencyConversion;
    final ranked = overview
        .map((market) => convertMarket(market, conversion.rate))
        .toList();
    ranked.sort((a, b) {
      final aVolume = double.tryParse(a.volume24h ?? '') ?? -1;
      final bVolume = double.tryParse(b.volume24h ?? '') ?? -1;
      final byVolume = bVolume.compareTo(aVolume);
      return byVolume != 0 ? byVolume : a.symbol.compareTo(b.symbol);
    });
    return ranked.take(10).toList(growable: false);
  } catch (_) {
    return markets.take(10).toList(growable: false);
  }
});

final marketsByIdsProvider =
    FutureProvider.family<List<Market>, String>((ref, idsKey) async {
  final ids = idsKey.isEmpty ? const <String>[] : idsKey.split(',');
  try {
    return await ref.watch(marketRepositoryProvider).lookup(ids);
  } catch (_) {
    final markets = await ref.watch(marketsProvider.future);
    return markets.where((market) => ids.contains(market.id)).toList();
  }
});

class CurrencyConversion {
  const CurrencyConversion({required this.currency, required this.rate});
  final DisplayCurrency currency;
  final double rate;
}

final currencyConversionProvider =
    FutureProvider<CurrencyConversion>((ref) async {
  final preferenceState = ref.watch(appPreferencesProvider);
  final preferenceController = ref.watch(appPreferencesProvider.notifier);
  final preferences = preferenceState.valueOrNull ??
      (await preferenceController.stream.firstWhere((state) => state.hasValue))
          .requireValue;
  final data = await _loadRatesWithRetry(ref.watch(marketRepositoryProvider));
  final rates = data['rates'] as Map<String, dynamic>? ?? const {};
  final rate = double.tryParse('${rates[preferences.currency.code]}');
  if (rate == null || !rate.isFinite || rate <= 0) {
    throw const FormatException('Taxa de conversão inválida.');
  }
  return CurrencyConversion(currency: preferences.currency, rate: rate);
});

Future<Map<String, dynamic>> _loadRatesWithRetry(
  MarketRepository repository,
) async {
  Object? lastError;
  for (var attempt = 0; attempt < 3; attempt++) {
    try {
      return await repository.rates().timeout(const Duration(seconds: 15));
    } catch (error) {
      lastError = error;
      if (attempt < 2) {
        await Future<void>.delayed(Duration(milliseconds: 500 * (attempt + 1)));
      }
    }
  }
  throw lastError ?? StateError('Taxas de conversão indisponíveis.');
}

final displayCurrencyProvider = Provider<String>(
  (ref) =>
      ref.watch(appPreferencesProvider).valueOrNull?.currency.code ?? 'BRL',
);

final assetQuoteProvider = FutureProvider.family<Map<String, dynamic>, String>(
  (ref, id) async {
    final values = await Future.wait([
      ref.watch(marketRepositoryProvider).quote(id),
      ref.watch(currencyConversionProvider.future),
    ]).timeout(const Duration(seconds: 12));
    return convertQuote(
      values[0] as Map<String, dynamic>,
      (values[1] as CurrencyConversion).rate,
    );
  },
);

final assetCandlesProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, id) async {
  final values = await Future.wait([
    ref.watch(marketRepositoryProvider).candles(id),
    ref.watch(currencyConversionProvider.future),
  ]).timeout(const Duration(seconds: 15));
  return convertCandles(
    (values[0] as List).cast<Map<String, dynamic>>(),
    (values[1] as CurrencyConversion).rate,
  );
});

final marketLiveQuoteProvider =
    StreamProvider.autoDispose.family<Map<String, dynamic>, String>(
  (ref, id) => ref.watch(marketWebSocketClientProvider).quotes([id]),
);

final radarProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  return _loadRadar(ref, 'all');
});

final radarScopeProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, scope) async {
  return _loadRadar(ref, scope);
});

Future<Map<String, dynamic>> _loadRadar(Ref ref, String scope) async {
  final values = await Future.wait([
    ref.watch(marketRepositoryProvider).radar(scope: scope),
    ref.watch(currencyConversionProvider.future),
  ]).timeout(const Duration(seconds: 20));
  return convertRadar(
    values[0] as Map<String, dynamic>,
    (values[1] as CurrencyConversion).rate,
  );
}

final marketClockProvider = StreamProvider<DateTime>((ref) async* {
  yield DateTime.now();
  yield* Stream.periodic(const Duration(seconds: 5), (_) => DateTime.now());
});

final marketQuotesProvider =
    StreamProvider.autoDispose<Map<String, Map<String, dynamic>>>((ref) {
  final repository = ref.watch(marketRepositoryProvider);
  final socket = ref.watch(marketWebSocketClientProvider);
  final markets = ref.watch(marketsProvider.future);
  final favoriteIds = ref.watch(favoriteIdsProvider).valueOrNull ?? <String>{};
  final conversion = ref.watch(currencyConversionProvider.future);
  final controller = StreamController<Map<String, Map<String, dynamic>>>();
  final latest = <String, Map<String, dynamic>>{};
  StreamSubscription<Map<String, dynamic>>? subscription;
  Timer? timer;
  var disposed = false;
  var fetching = false;
  var rate = 1.0;

  void receive(String id, Map<String, dynamic> quote) {
    if (disposed) return;
    final incoming = DateTime.tryParse('${quote['timestamp']}');
    final previous = DateTime.tryParse('${latest[id]?['timestamp']}');
    if (incoming != null && previous != null && incoming.isBefore(previous)) {
      return;
    }
    latest[id] = convertQuote(quote, rate);
    controller.add(Map.of(latest));
  }

  Future<void> poll(List<Market> items) async {
    if (fetching || disposed) return;
    fetching = true;
    await Future.wait(items.map((market) async {
      try {
        receive(
          market.id,
          await repository
              .quote(market.id)
              .timeout(const Duration(seconds: 10)),
        );
      } catch (_) {}
    }));
    fetching = false;
    if (!disposed) controller.add(Map.of(latest));
  }

  Future<void> start() async {
    try {
      final values = await Future.wait([markets, conversion]);
      final items = values[0] as List<Market>;
      final subscribedIds = {
        ...items.map((market) => market.id),
        ...favoriteIds,
      };
      rate = (values[1] as CurrencyConversion).rate;
      if (disposed) return;
      subscription = socket.quotes(subscribedIds).listen(
            (quote) => receive('${quote['market_id']}', quote),
            onError: (Object _) {},
          );
      timer = Timer.periodic(const Duration(seconds: 15), (_) => poll(items));
      await poll(items);
    } catch (error, trace) {
      if (!disposed) controller.addError(error, trace);
    }
  }

  ref.onDispose(() {
    disposed = true;
    timer?.cancel();
    subscription?.cancel();
    controller.close();
  });
  unawaited(start());
  return controller.stream;
});

enum ChartPeriod {
  hour('1h', '5m', 12),
  fourHours('4h', '15m', 16),
  day('24h', '1h', 24),
  week('7d', '4h', 42),
  month('30d', '1d', 30);

  const ChartPeriod(this.label, this.interval, this.count);
  final String label;
  final String interval;
  final int count;
}

final chartProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, (String, ChartPeriod)>(
        (ref, request) async {
  final refresh = Timer(const Duration(minutes: 1), ref.invalidateSelf);
  ref.onDispose(refresh.cancel);
  final values = await Future.wait([
    ref.watch(marketRepositoryProvider).candles(
          request.$1,
          interval: request.$2.interval,
          limit: request.$2.count,
        ),
    ref.watch(currencyConversionProvider.future),
  ]).timeout(const Duration(seconds: 15));
  return convertCandles(
    (values[0] as List).cast<Map<String, dynamic>>(),
    (values[1] as CurrencyConversion).rate,
  );
});

Map<String, dynamic> convertQuote(
  Map<String, dynamic> quote,
  double rate,
) =>
    {
      ...quote,
      if (quote['price'] != null)
        'price': multiplyCurrency(quote['price'], rate),
      if (quote['volume_24h'] != null)
        'volume_24h': multiplyCurrency(quote['volume_24h'], rate),
    };

List<Map<String, dynamic>> convertCandles(
  List<Map<String, dynamic>> candles,
  double rate,
) =>
    candles
        .map((candle) => {
              ...candle,
              for (final key in [
                'open',
                'high',
                'low',
                'close',
                'quote_volume'
              ])
                if (candle[key] != null)
                  key: multiplyCurrency(candle[key], rate),
            })
        .toList();

Map<String, dynamic> convertRadar(
  Map<String, dynamic> radar,
  double rate,
) =>
    {
      ...radar,
      for (final key in ['gainers', 'losers', 'volume', 'volatility'])
        key: ((radar[key] as List<dynamic>?) ?? const []).map((raw) {
          final item = raw as Map<String, dynamic>;
          return {
            ...item,
            if (item['quote_volume'] != null)
              'quote_volume': multiplyCurrency(item['quote_volume'], rate),
          };
        }).toList(),
    };

String multiplyCurrency(dynamic value, double rate) {
  final parsed = double.tryParse('$value');
  if (parsed == null || !parsed.isFinite) return '$value';
  return (parsed * rate).toString();
}

Market convertMarket(Market market, double rate) => Market(
      id: market.id,
      symbol: market.symbol,
      base: market.base,
      quote: market.quote,
      name: market.name,
      provider: market.provider,
      providerName: market.providerName,
      providerSymbol: market.providerSymbol,
      sourceStatus: market.sourceStatus,
      price: market.price == null ? null : multiplyCurrency(market.price, rate),
      change24hPercent: market.change24hPercent,
      volume24h: market.volume24h == null
          ? null
          : multiplyCurrency(market.volume24h, rate),
      timestamp: market.timestamp,
      stale: market.stale,
    );
