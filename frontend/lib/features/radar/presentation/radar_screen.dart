import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../market/data/market_providers.dart';
import '../../market/models/market.dart';
import '../../market/presentation/market_widgets.dart';
import '../../favorites/data/favorite_store.dart';
import '../../watchlists/presentation/watchlists_screen.dart';
import '../../../core/session/session_controller.dart';
export '../../market/data/market_providers.dart' show radarProvider;

class RadarScreen extends ConsumerStatefulWidget {
  const RadarScreen({super.key});
  @override
  ConsumerState<RadarScreen> createState() => _RadarScreenState();
}

class _RadarScreenState extends ConsumerState<RadarScreen> {
  var _category = 0;
  var _scope = 'all';
  static const categories = ['Altas', 'Quedas', 'Volume', 'Volatilidade'];
  static const keys = ['gainers', 'losers', 'volume', 'volatility'];
  static const titles = [
    'Maiores altas',
    'Maiores quedas',
    'Maior volume',
    'Maior volatilidade'
  ];
  Future<void> _refresh() async {
    if (_scope == 'all') {
      ref.invalidate(radarProvider);
    } else {
      ref.invalidate(radarScopeProvider(_scope));
    }
    try {
      await ref.read(_scope == 'all'
          ? radarProvider.future
          : radarScopeProvider(_scope).future);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final radar =
        ref.watch(_scope == 'all' ? radarProvider : radarScopeProvider(_scope));
    final currency = ref.watch(displayCurrencyProvider);
    final favorites = ref.watch(favoriteIdsProvider).valueOrNull ?? <String>{};
    final favoriteIds = favorites.toList()..sort();
    final authenticated = ref.watch(sessionControllerProvider).isAuthenticated;
    final watchlists = authenticated
        ? ref.watch(watchlistsProvider).valueOrNull ?? <Map<String, dynamic>>[]
        : <Map<String, dynamic>>[];
    final data = radar.asData?.value;
    final raw = (data?[keys[_category]] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    final items = raw.where((item) {
      final change = number(item['change_percent']);
      return _category > 1 ||
          (change != null && (_category == 0 ? change > 0 : change < 0));
    }).toList();
    final updated = DateTime.tryParse('${data?['updated_at']}')?.toLocal();
    return SafeArea(
        child: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                MarketHeader(
                    title: 'Radar',
                    subtitle: 'Encontre os movimentos do mercado.',
                    onRefresh: _refresh,
                    showRefresh: false),
                Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                          color: const Color(0xFFEAF0FF),
                          borderRadius: BorderRadius.circular(20)),
                      child: Row(children: [
                        const Icon(Icons.radar_rounded,
                            size: 38, color: AppTheme.accent),
                        const SizedBox(width: 16),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              const Text('Além do preço',
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 5),
                              const Text(
                                  'Altas, quedas e atividade nos pares acompanhados.',
                                  style: TextStyle(
                                      color: AppTheme.muted,
                                      fontSize: 13,
                                      height: 1.5)),
                              const SizedBox(height: 10),
                              Text(
                                  updated == null
                                      ? 'Janela de 24h'
                                      : 'Janela de 24h · atualizado ${updated.hour.toString().padLeft(2, '0')}:${updated.minute.toString().padLeft(2, '0')}',
                                  style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.accent)),
                            ])),
                      ]),
                    )),
                const SizedBox(height: 20),
                SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(children: [
                      _scopeChip('Todo mercado', 'all'),
                      if (favorites.isNotEmpty)
                        _scopeChip(
                          'Favoritos',
                          'markets:${favoriteIds.join(',')}',
                        ),
                      for (final list in watchlists)
                        _scopeChip(
                            '${list['name']}', 'watchlist:${list['id']}'),
                    ])),
                const SizedBox(height: 14),
                SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(children: [
                      for (var i = 0; i < categories.length; i++)
                        Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                                label: Text(categories[i]),
                                selected: _category == i,
                                showCheckmark: false,
                                selectedColor: AppTheme.ink,
                                backgroundColor: Colors.white,
                                labelStyle: TextStyle(
                                    color: _category == i
                                        ? Colors.white
                                        : AppTheme.muted,
                                    fontWeight: FontWeight.w600),
                                side: const BorderSide(color: AppTheme.line),
                                onSelected: (_) =>
                                    setState(() => _category = i))),
                    ])),
                Padding(
                    padding: const EdgeInsets.fromLTRB(24, 22, 24, 12),
                    child: Text(titles[_category],
                        style: Theme.of(context).textTheme.titleLarge)),
                if (radar.isLoading && data == null)
                  const AsyncStatePanel.loading(label: 'Atualizando o radar…')
                else if (radar.hasError && data == null)
                  AsyncStatePanel.unavailable(
                      title: 'Radar indisponível',
                      description: 'Não foi possível atualizar os movimentos.',
                      onRetry: _refresh)
                else if (items.isEmpty)
                  const AsyncStatePanel.empty(
                      title: 'Nenhum movimento nesta categoria',
                      description:
                          'Dados indisponíveis ou nenhum ativo atende ao filtro nesta janela.')
                else
                  Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Card(
                          child: Column(children: [
                        for (var i = 0; i < items.length; i++) ...[
                          if (i > 0) const Divider(indent: 16, endIndent: 16),
                          _rankRow(context, items[i], i, currency),
                        ],
                      ]))),
                Padding(
                    padding: const EdgeInsets.all(26),
                    child: Text(
                        _category == 3
                            ? 'Volatilidade: média da amplitude de cada candle de 1h em relação à abertura. Quanto maior, mais amplo foi o movimento.'
                            : _category == 2
                                ? 'Volume negociado na moeda de cotação de cada par. Valores de moedas diferentes não são diretamente comparáveis.'
                                : 'Ranking dos pares acompanhados, calculado com os últimos 24 candles de 1h. Toque em um ativo para explorar.',
                        style: const TextStyle(
                            fontSize: 12, color: AppTheme.muted, height: 1.6))),
              ],
            )));
  }

  Widget _scopeChip(String label, String value) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: FilterChip(
          label: Text(label),
          selected: _scope == value,
          showCheckmark: false,
          onSelected: (_) => setState(() => _scope = value),
        ),
      );

  Widget _rankRow(BuildContext context, Map<String, dynamic> item, int index,
      String currency) {
    final market =
        Market.fromJson(item['market'] as Map<String, dynamic>? ?? {});
    final metric = _category == 2
        ? compactText(item['quote_volume'])
        : _category == 3
            ? '${priceText(item['volatility_percent'])}%'
            : null;
    return InkWell(
      onTap: market.id == 'null'
          ? null
          : () => Navigator.of(context).pushNamed('/asset', arguments: market),
      child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Row(children: [
            Text('${index + 1}'.padLeft(2, '0'),
                style:
                    numericStyle.copyWith(fontSize: 11, color: AppTheme.muted)),
            const SizedBox(width: 12),
            CoinAvatar(market.base, size: 36),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(
                      market.displayName.isEmpty
                          ? market.symbol
                          : market.displayName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text(market.displaySymbol(currency),
                      style:
                          const TextStyle(fontSize: 11, color: AppTheme.muted)),
                ])),
            if (metric == null)
              ChangeBadge(number(item['change_percent']))
            else
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(metric,
                    style: numericStyle.copyWith(fontWeight: FontWeight.w700)),
                if (_category == 2)
                  Text(currency,
                      style:
                          const TextStyle(fontSize: 10, color: AppTheme.muted)),
              ]),
          ])),
    );
  }
}
