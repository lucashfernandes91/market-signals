import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_radar/app.dart';
import 'package:market_radar/core/preferences/app_preferences.dart';
import 'package:market_radar/features/favorites/data/favorite_store.dart';
import 'package:market_radar/features/market/data/market_providers.dart';
import 'package:market_radar/features/market/models/market.dart';
import 'package:market_radar/features/market/presentation/market_widgets.dart';
import 'package:market_radar/features/market/presentation/market_screen.dart'
    show MarketScreen;

const btc = Market(
    id: 'btc', symbol: 'BTC-USDT', base: 'BTC', quote: 'USDT', name: 'Bitcoin');
const eth = Market(
    id: 'eth',
    symbol: 'ETH-USDT',
    base: 'ETH',
    quote: 'USDT',
    name: 'Ethereum');
final now = DateTime.utc(2026, 10, 1, 12);
List<Map<String, dynamic>> candles(bool rising) => [
      {
        'timestamp': '2026-09-30T12:00:00Z',
        'open': '100',
        'close': '100',
        'high': '110',
        'low': '90'
      },
      {
        'timestamp': '2026-10-01T11:00:00Z',
        'open': '100',
        'close': rising ? '105' : '95',
        'high': '110',
        'low': '90'
      },
    ];

Widget app({
  bool emptyQuotes = false,
  double scale = 1,
  bool onboardingComplete = true,
  double currencyRate = 1,
  Map<String, dynamic>? liveQuote,
}) =>
    ProviderScope(
      overrides: [
        preferenceStoreProvider.overrideWithValue(MemoryPreferenceStore(
          AppPreferences(onboardingComplete: onboardingComplete),
        )),
        favoriteStoreProvider.overrideWithValue(MemoryFavoriteStore()),
        currencyConversionProvider.overrideWith((ref) async =>
            CurrencyConversion(
                currency: DisplayCurrency.brl, rate: currencyRate)),
        marketsProvider.overrideWith((ref) async => [btc, eth]),
        marketClockProvider.overrideWith((ref) => Stream.value(now)),
        marketQuotesProvider.overrideWith((ref) => Stream.value(emptyQuotes
            ? {}
            : {
                'btc': {
                  'price': '65432.10',
                  'timestamp': now.toIso8601String(),
                  'volume_24h': '1500000'
                },
                'eth': {
                  'price': '2500.25',
                  'timestamp':
                      now.subtract(const Duration(minutes: 2)).toIso8601String()
                },
              })),
        chartProvider
            .overrideWith((ref, request) async => candles(request.$1 == 'btc')),
        if (liveQuote != null)
          marketLiveQuoteProvider
              .overrideWith((ref, id) => Stream.value(liveQuote)),
        radarProvider.overrideWith((ref) async =>
            {'gainers': [], 'losers': [], 'volume': [], 'volatility': []}),
      ],
      child: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: const MarketRadarApp()),
    );

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('preço aparece na grade; filtro usa a moeda escolhida',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('R\$ 65.432,10'), findsOneWidget);
    expect(find.text('R\$ 2.500,25'), findsOneWidget);
    expect(find.byTooltip('Última cotação recebida está desatualizada'),
        findsOneWidget);
    await tester.tap(find.text('Em queda'));
    await tester.pumpAndSettle();
    expect(find.text('Bitcoin'), findsNothing);
    expect(find.text('Ethereum'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('abre detalhe, troca período e retorna à lista sem login',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bitcoin'));
    await tester.pumpAndSettle();
    expect(find.text('PREÇO DO ATIVO'), findsOneWidget);
    expect(find.text('65.432,10'), findsOneWidget);
    expect(find.text('Evolução do preço'), findsOneWidget);
    expect(find.text('1h'), findsOneWidget);
    expect(find.text('4h'), findsOneWidget);
    await tester.tap(find.text('1h'));
    await tester.pumpAndSettle();
    expect(find.text('na janela de 1h'), findsOneWidget);
    expect(find.textContaining('intervalos de 5m'), findsOneWidget);
    await tester.tap(find.text('4h'));
    await tester.pumpAndSettle();
    expect(find.text('na janela de 4h'), findsOneWidget);
    expect(find.textContaining('intervalos de 15m'), findsOneWidget);
    await tester.tap(find.text('7d'));
    await tester.pumpAndSettle();
    expect(find.text('na janela de 7d'), findsOneWidget);
    expect(find.textContaining('intervalos de 4h'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Top 10 por volume · 24 h'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('detalhe converte a cotação ao vivo para a moeda escolhida',
      (tester) async {
    await tester.pumpWidget(app(
      currencyRate: 5,
      liveQuote: {
        'price': '65432.10',
        'volume_24h': '1500000',
        'timestamp': now.toIso8601String(),
      },
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bitcoin'));
    await tester.pumpAndSettle();

    expect(find.text('327.160,50'), findsOneWidget);
    expect(find.text('BRL'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('gráfico alterna linha e candles e abre em tela cheia',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bitcoin'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Candles'));
    await tester.pumpAndSettle();
    expect(find.text('Candles'), findsOneWidget);
    await tester.tap(find.byTooltip('Abrir gráfico em tela cheia'));
    await tester.pumpAndSettle();
    expect(find.text('Bitcoin · 24h'), findsOneWidget);
    expect(find.byTooltip('Abrir gráfico em tela cheia'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Evolução do preço'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('não inventa preço quando não existe cotação', (tester) async {
    await tester.pumpWidget(app(emptyQuotes: true));
    await tester.pumpAndSettle();
    expect(find.text('Indisponível'), findsWidgets);
    expect(find.text('0,00'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('layout comporta tela estreita e fonte ampliada', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
        overrides: [
          marketsProvider.overrideWith((ref) async => [btc, eth]),
          preferenceStoreProvider.overrideWithValue(MemoryPreferenceStore()),
          favoriteStoreProvider.overrideWithValue(MemoryFavoriteStore()),
          marketClockProvider.overrideWith((ref) => Stream.value(now)),
          marketQuotesProvider.overrideWith((ref) => Stream.value({
                'btc': {'price': '65432.10', 'timestamp': now.toIso8601String()}
              })),
          chartProvider.overrideWith((ref, request) async => candles(true)),
          radarProvider.overrideWith((ref) async => {}),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!),
          home: const Scaffold(body: _MarketOnly()),
        )));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  test('formatação e frescor não transformam ausência em zero', () {
    expect(priceText(null), '—');
    expect(priceText('NaN'), '—');
    expect(priceText('0.005'), '0,00500000');
    expect(
        quoteFresh(
            {'price': '100', 'timestamp': now.toIso8601String(), 'stale': true},
            now),
        isFalse);
    expect(
        quoteFresh({
          'price': '100',
          'timestamp': now.toIso8601String(),
          'source_status': 'unavailable',
        }, now),
        isFalse);
  });

  testWidgets('estado indisponível padronizado permite tentar novamente',
      (tester) async {
    var retries = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AsyncStatePanel.unavailable(
          title: 'Mercado indisponível',
          description: 'Tente novamente em instantes.',
          onRetry: () => retries++,
        ),
      ),
    ));

    expect(find.text('Mercado indisponível'), findsOneWidget);
    await tester.tap(find.text('Tentar novamente'));
    expect(retries, 1);
  });

  testWidgets('estado assíncrono permanece centralizado em coluna alinhada',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AsyncStatePanel.unavailable(
                  title: 'Histórico indisponível',
                  description: 'Não foi possível carregar o gráfico.',
                  onRetry: _noop,
                  minHeight: 200,
                ),
              ],
            ),
          ),
        ),
      ),
    ));

    final panel = find.byType(AsyncStatePanel);
    final centerX = tester.getCenter(panel).dx;
    expect(tester.getSize(panel).width, 300);
    expect(tester.getCenter(find.byIcon(Icons.cloud_off_outlined)).dx, centerX);
    expect(tester.getCenter(find.text('Histórico indisponível')).dx, centerX);
    expect(
      tester.getCenter(find.text('Não foi possível carregar o gráfico.')).dx,
      centerX,
    );
  });

  testWidgets('estado vazio oferece uma única ação primária acessível',
      (tester) async {
    var actions = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AsyncStatePanel.empty(
          title: 'Crie seu primeiro item',
          description: 'Adicione um item para começar.',
          actionLabel: 'Criar item',
          actionIcon: Icons.add_rounded,
          onAction: () => actions++,
        ),
      ),
    ));

    final action = find.widgetWithText(FilledButton, 'Criar item');
    expect(action, findsOneWidget);
    expect(tester.getSize(action).height, greaterThanOrEqualTo(48));
    await tester.tap(action);
    expect(actions, 1);
  });

  test('modelo usa a fonte da API e mantém fallback neutro', () {
    final sourced = Market.fromJson({
      'market_id': 'btc',
      'canonical_symbol': 'BTC-USDT',
      'asset_symbol': 'BTC',
      'provider': 'exchange_x',
      'provider_name': 'Exchange X',
      'provider_symbol': 'BTCUSDT',
      'source_status': 'live',
    });

    expect(sourced.sourceLabel, 'Exchange X');
    expect(originSymbolFor(sourced), 'BTCUSDT');
    expect(
        sourceLabelFor(const Market(
            id: 'eth', symbol: 'ETH-USDT', base: 'ETH', quote: 'USDT')),
        'Fonte não identificada');
  });

  testWidgets('detalhe exibe a fonte e o símbolo recebidos da API',
      (tester) async {
    await tester.pumpWidget(app(liveQuote: {
      'price': '65432.10',
      'volume_24h': '1500000',
      'timestamp': now.toIso8601String(),
      'provider_name': 'Exchange X',
      'provider_symbol': 'BTCUSDT',
      'source_status': 'live',
    }));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bitcoin'));
    await tester.pumpAndSettle();

    final source =
        find.textContaining('Fonte: Exchange X · Par de origem BTCUSDT.');
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -1200));
    await tester.pumpAndSettle();
    expect(source, findsOneWidget);
  });

  testWidgets('favorito local funciona sem conta e aparece no filtro Favoritos',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Adicionar aos favoritos').first);
    await tester.pump();
    expect(find.byTooltip('Remover dos favoritos'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Favoritos'));
    await tester.pumpAndSettle();
    expect(find.text('Seus ativos salvos neste aparelho.'), findsOneWidget);
    expect(find.text('Bitcoin'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Favoritos vazio mostra somente a ação contextual',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, 'Favoritos'));
    await tester.pumpAndSettle();

    expect(find.text('Adicione seu primeiro favorito'), findsOneWidget);
    expect(find.text('Adicionar favorito'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Adicionar favorito'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('criar alerta solicita conta somente no momento da ação',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Bitcoin'));
    await tester.pumpAndSettle();
    expect(find.text('Entrar na sua conta'), findsNothing);
    await tester.tap(find.text('Criar alerta para este ativo'));
    await tester.pumpAndSettle();
    expect(find.text('Novo alerta'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), 'Bitcoin acima');
    await tester.enterText(find.byType(TextField).at(1), '460000');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(find.text('Entrar na sua conta'), findsOneWidget);
    expect(find.textContaining('O mercado continua disponível sem cadastro.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Perfil visitante não força cadastro ao abrir', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Perfil'),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Você está usando como visitante'), findsOneWidget);
    expect(find.text('Entrar ou criar conta'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('navegação principal respeita a ordem da Fase 2 e touch target',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('Mercado'), findsWidgets);
    final navigation = find.byType(NavigationBar);
    for (final label in ['Mercado', 'Alertas', 'Radar', 'Perfil']) {
      expect(find.descendant(of: navigation, matching: find.text(label)),
          findsOneWidget);
    }
    expect(find.descendant(of: navigation, matching: find.text('Favoritos')),
        findsNothing);
    expect(find.widgetWithText(ChoiceChip, 'Favoritos'), findsOneWidget);
    expect(find.byTooltip('Atualizar dados'), findsNothing);
    expect(find.byTooltip('Exibir em grade'), findsOneWidget);
    expect(find.byTooltip('Exibir em lista'), findsOneWidget);
    for (final tooltip in ['Exibir em grade', 'Exibir em lista']) {
      final toggle = find.byTooltip(tooltip);
      expect(tester.getSize(toggle).width, greaterThanOrEqualTo(44));
      expect(tester.getSize(toggle).height, greaterThanOrEqualTo(44));
    }
    expect(find.byTooltip('Abrir perfil'), findsNothing);
    final favoriteButton = find.byTooltip('Adicionar aos favoritos').first;
    expect(tester.getSize(favoriteButton).width, greaterThanOrEqualTo(48));
    expect(tester.getSize(favoriteButton).height, greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);
  });

  testWidgets('onboarding é curto e pode ser ignorado', (tester) async {
    await tester.pumpWidget(app(onboardingComplete: false));
    await tester.pumpAndSettle();

    expect(find.text('Seu Radar, do seu jeito'), findsOneWidget);
    await tester.tap(find.text('Agora não'));
    await tester.pumpAndSettle();

    expect(find.text('Mercado'), findsWidgets);
    expect(find.text('Seu Radar, do seu jeito'), findsNothing);
  });

  test('conversão aplica a taxa sem alterar ausência de preço', () {
    expect(convertQuote({'price': '10', 'volume_24h': '20'}, 5.0), {
      'price': '50.0',
      'volume_24h': '100.0',
    });
    expect(convertQuote({'status': 'unavailable'}, 5.0), {
      'status': 'unavailable',
    });
  });

  test('resumo do mercado converte preço e volume sem alterar variação', () {
    const market = Market(
      id: 'btc',
      symbol: 'BTC-USDT',
      base: 'BTC',
      quote: 'USDT',
      price: '10',
      volume24h: '20',
      change24hPercent: '3.5',
    );

    final converted = convertMarket(market, 5.0);

    expect(converted.price, '50.0');
    expect(converted.volume24h, '100.0');
    expect(converted.change24hPercent, '3.5');
  });
}

void _noop() {}

class _MarketOnly extends StatelessWidget {
  const _MarketOnly();
  @override
  Widget build(BuildContext context) => const MarketScreen();
}
