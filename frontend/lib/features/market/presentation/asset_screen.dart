import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../alerts/presentation/alerts_screen.dart';
import '../../favorites/data/favorite_store.dart';
import '../data/market_providers.dart';
import '../models/market.dart';
import 'market_widgets.dart';

class AssetScreen extends ConsumerStatefulWidget {
  const AssetScreen({required this.market, super.key});
  final Market market;
  @override
  ConsumerState<AssetScreen> createState() => _AssetScreenState();
}

class _AssetScreenState extends ConsumerState<AssetScreen> {
  var _period = ChartPeriod.day;
  var _mode = ChartMode.line;
  int? _selectedIndex;
  Future<void> _refresh() async {
    ref.invalidate(marketQuotesProvider);
    ref.invalidate(chartProvider((widget.market.id, _period)));
    try {
      await ref.read(chartProvider((widget.market.id, _period)).future);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final market = widget.market;
    final currency = ref.watch(displayCurrencyProvider);
    final favorites = ref.watch(favoriteIdsProvider);
    final isFavorite = favorites.valueOrNull?.contains(market.id) == true;
    final quotes = ref.watch(marketQuotesProvider);
    final liveQuote = ref.watch(marketLiveQuoteProvider(market.id));
    final conversion = ref.watch(currencyConversionProvider);
    final rawLiveQuote = liveQuote.asData?.value;
    final quote = rawLiveQuote != null && conversion.hasValue
        ? convertQuote(rawLiveQuote, conversion.requireValue.rate)
        : quotes.asData?.value[market.id];
    final sourceLabel = sourceLabelFor(market, quote);
    final originSymbol = originSymbolFor(market, quote);
    final now = ref.watch(marketClockProvider).asData?.value ?? DateTime.now();
    final candles = ref.watch(chartProvider((market.id, _period)));
    final items = candles.asData?.value ?? <Map<String, dynamic>>[];
    final values = closes(items);
    final selectedCandle =
        _selectedIndex != null && _selectedIndex! < items.length
            ? items[_selectedIndex!]
            : null;
    final fresh = quoteFresh(quote, now);
    final hasPrice = number(quote?['price']) != null;
    final time = DateTime.tryParse('${quote?['timestamp']}')?.toLocal();
    final highs = items.map((c) => number(c['high'])).whereType<double>();
    final lows = items.map((c) => number(c['low'])).whereType<double>();
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          CoinAvatar(market.base, size: 34),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(market.displayName,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
                Text('${market.base} / $currency',
                    style:
                        const TextStyle(fontSize: 11, color: AppTheme.muted)),
              ])),
        ]),
        actions: [
          IconButton(
            tooltip: isFavorite
                ? 'Remover dos favoritos'
                : 'Adicionar aos favoritos',
            onPressed: favorites.isLoading
                ? null
                : () =>
                    ref.read(favoriteIdsProvider.notifier).toggle(market.id),
            icon: Icon(
              isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
              color: isFavorite ? const Color(0xFFD57A08) : null,
            ),
          ),
          IconButton(
              tooltip: 'Atualizar dados',
              onPressed: _refresh,
              icon: const Icon(Icons.refresh_rounded))
        ],
      ),
      body: Center(
          child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
              children: [
                const Text('PREÇO DO ATIVO',
                    style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 1.2,
                        color: AppTheme.muted,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 10,
                    children: [
                      Text(
                          hasPrice
                              ? priceText(quote!['price'])
                              : quotes.isLoading
                                  ? 'Carregando…'
                                  : 'Indisponível',
                          style: numericStyle.copyWith(
                              fontSize: hasPrice ? 36 : 24,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -1)),
                      Text(currency,
                          style: const TextStyle(
                              color: AppTheme.muted, fontSize: 16)),
                    ]),
                const SizedBox(height: 12),
                Wrap(
                    spacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ChangeBadge(candleChange(items)),
                      Text('na janela de ${_period.label}',
                          style: const TextStyle(
                              color: AppTheme.muted, fontSize: 12)),
                    ]),
                const SizedBox(height: 14),
                Row(children: [
                  Icon(fresh ? Icons.check_circle_outline : Icons.schedule,
                      size: 14,
                      color: fresh ? AppTheme.positive : AppTheme.muted),
                  const SizedBox(width: 6),
                  Expanded(
                      child: Text(
                          hasPrice
                              ? '${fresh ? 'Preço atualizado' : 'Última cotação recebida'}${time == null ? '' : ' · ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}'}'
                              : 'Aguardando cotação de $sourceLabel',
                          style: const TextStyle(
                              color: AppTheme.muted, fontSize: 11))),
                ]),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _createAlert(market),
                    icon: const Icon(Icons.add_alert_outlined),
                    label: const Text('Criar alerta para este ativo'),
                  ),
                ),
                if (selectedCandle != null) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => _createAlert(
                        market,
                        initialPrice: number(selectedCandle['close']),
                      ),
                      icon: const Icon(Icons.add_alert),
                      label: Text(
                          'Criar alerta em ${priceText(selectedCandle['close'])} $currency'),
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                Card(
                    child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                const Expanded(
                                    child: Text('Evolução do preço',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w700))),
                                Text(currency,
                                    style: const TextStyle(
                                        color: AppTheme.muted, fontSize: 11)),
                                IconButton(
                                  tooltip: 'Abrir gráfico em tela cheia',
                                  onPressed: items.length < 2
                                      ? null
                                      : () => _openFullscreen(
                                          market, items, currency),
                                  icon: const Icon(Icons.fullscreen_rounded),
                                ),
                              ]),
                              const SizedBox(height: 12),
                              Wrap(spacing: 8, runSpacing: 8, children: [
                                for (final period in ChartPeriod.values)
                                  ChoiceChip(
                                      label: Text(period.label),
                                      selected: _period == period,
                                      showCheckmark: false,
                                      selectedColor: AppTheme.ink,
                                      side: const BorderSide(
                                          color: AppTheme.line),
                                      labelStyle: TextStyle(
                                          color: _period == period
                                              ? Colors.white
                                              : AppTheme.muted,
                                          fontWeight: FontWeight.w600),
                                      onSelected: (_) =>
                                          setState(() => _period = period)),
                              ]),
                              const SizedBox(height: 10),
                              SegmentedButton<ChartMode>(
                                segments: const [
                                  ButtonSegment(
                                      value: ChartMode.line,
                                      label: Text('Linha'),
                                      icon: Icon(Icons.show_chart)),
                                  ButtonSegment(
                                      value: ChartMode.candles,
                                      label: Text('Candles'),
                                      icon: Icon(Icons.candlestick_chart)),
                                ],
                                selected: {_mode},
                                onSelectionChanged: (value) =>
                                    setState(() => _mode = value.first),
                              ),
                              const SizedBox(height: 16),
                              if (candles.isLoading && items.isEmpty)
                                const SizedBox(
                                    height: 200,
                                    child: Center(
                                        child: CircularProgressIndicator()))
                              else if (candles.hasError && items.isEmpty)
                                AsyncStatePanel.unavailable(
                                  title: 'Histórico indisponível',
                                  description:
                                      'Não foi possível carregar o gráfico.',
                                  onRetry: _refresh,
                                  minHeight: 200,
                                )
                              else ...[
                                if (values.isNotEmpty)
                                  Text(
                                      'Máx. ${priceText(values.reduce(math.max))}',
                                      style: numericStyle.copyWith(
                                          fontSize: 10, color: AppTheme.muted)),
                                InteractivePriceChart(
                                  candles: items,
                                  mode: _mode,
                                  selectedIndex: _selectedIndex,
                                  onSelected: (index) =>
                                      setState(() => _selectedIndex = index),
                                  height: 220,
                                ),
                                if (values.isNotEmpty)
                                  Text(
                                      'Mín. ${priceText(values.reduce(math.min))}',
                                      style: numericStyle.copyWith(
                                          fontSize: 10, color: AppTheme.muted)),
                                const SizedBox(height: 12),
                                Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                          items.isEmpty
                                              ? ''
                                              : _candleTime(items.first),
                                          style: const TextStyle(
                                              fontSize: 10,
                                              color: AppTheme.muted)),
                                      Text(
                                          items.isEmpty
                                              ? ''
                                              : _candleTime(items.last),
                                          style: const TextStyle(
                                              fontSize: 10,
                                              color: AppTheme.muted)),
                                    ]),
                              ],
                              const SizedBox(height: 12),
                              Text(
                                  'Fechamentos em intervalos de ${_period.interval}. O candle atual pode estar em formação.',
                                  style: const TextStyle(
                                      fontSize: 11,
                                      height: 1.5,
                                      color: AppTheme.muted)),
                            ]))),
                const SizedBox(height: 26),
                Text('Resumo do período',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 14),
                Card(
                    child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(children: [
                          _stat(
                              'Máxima · ${_period.label}',
                              highs.isEmpty
                                  ? '—'
                                  : priceText(highs.reduce(math.max)),
                              currency),
                          const Divider(height: 26),
                          _stat(
                              'Mínima · ${_period.label}',
                              lows.isEmpty
                                  ? '—'
                                  : priceText(lows.reduce(math.min)),
                              currency),
                          const Divider(height: 26),
                          _stat('Volume · 24h',
                              compactText(quote?['volume_24h']), currency),
                        ]))),
                const SizedBox(height: 18),
                Text(
                    'Fonte: $sourceLabel · Par de origem $originSymbol. Valores exibidos em $currency; preço em tempo real e histórico podem ter horários diferentes.',
                    style: const TextStyle(
                        fontSize: 11, color: AppTheme.muted, height: 1.6)),
              ],
            )),
      )),
    );
  }

  Future<void> _createAlert(Market market, {double? initialPrice}) async {
    await showCreateAlert(
      context,
      ref,
      market: market,
      initialPrice: initialPrice,
    );
  }

  Future<void> _openFullscreen(
      Market market, List<Map<String, dynamic>> items, String currency) async {
    final result = await Navigator.of(context)
        .push<_FullscreenChartResult>(MaterialPageRoute(
      builder: (_) => _FullscreenChartScreen(
        market: market,
        candles: items,
        currency: currency,
        period: _period,
        mode: _mode,
        selectedIndex: _selectedIndex,
      ),
    ));
    if (result != null && mounted) {
      setState(() {
        _mode = result.mode;
        _selectedIndex = result.selectedIndex;
      });
    }
  }

  String _candleTime(Map<String, dynamic> candle) {
    final time = DateTime.tryParse('${candle['timestamp']}')?.toLocal();
    if (time == null) return '';
    final date =
        '${time.day.toString().padLeft(2, '0')}/${time.month.toString().padLeft(2, '0')}';
    if (_period == ChartPeriod.month || _period == ChartPeriod.week) {
      return date;
    }
    final hour = time.hour.toString().padLeft(2, '0');
    if (_period == ChartPeriod.day) return '$date ${hour}h';
    final minute = time.minute.toString().padLeft(2, '0');
    return '$date $hour:$minute';
  }

  Widget _stat(String label, String value, String unit) => Row(children: [
        Expanded(
            child: Text(label,
                style: const TextStyle(color: AppTheme.muted, fontSize: 13))),
        const SizedBox(width: 12),
        Flexible(
            child: Text('$value $unit',
                textAlign: TextAlign.right,
                style: numericStyle.copyWith(
                    fontSize: 13, fontWeight: FontWeight.w700))),
      ]);
}

class _FullscreenChartResult {
  const _FullscreenChartResult(this.mode, this.selectedIndex);
  final ChartMode mode;
  final int? selectedIndex;
}

class _FullscreenChartScreen extends ConsumerStatefulWidget {
  const _FullscreenChartScreen({
    required this.market,
    required this.candles,
    required this.currency,
    required this.period,
    required this.mode,
    required this.selectedIndex,
  });

  final Market market;
  final List<Map<String, dynamic>> candles;
  final String currency;
  final ChartPeriod period;
  final ChartMode mode;
  final int? selectedIndex;

  @override
  ConsumerState<_FullscreenChartScreen> createState() =>
      _FullscreenChartScreenState();
}

class _FullscreenChartScreenState
    extends ConsumerState<_FullscreenChartScreen> {
  late var _mode = widget.mode;
  late int? _selectedIndex = widget.selectedIndex;

  @override
  Widget build(BuildContext context) {
    final selected =
        _selectedIndex != null && _selectedIndex! < widget.candles.length
            ? widget.candles[_selectedIndex!]
            : null;
    final result = _FullscreenChartResult(_mode, _selectedIndex);
    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(result);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('${widget.market.displayName} · ${widget.period.label}'),
          leading:
              BackButton(onPressed: () => Navigator.of(context).pop(result)),
          actions: [
            IconButton(
              tooltip: 'Criar alerta no ponto selecionado',
              onPressed: selected == null
                  ? null
                  : () => showCreateAlert(
                        context,
                        ref,
                        market: widget.market,
                        initialPrice: number(selected['close']),
                      ),
              icon: const Icon(Icons.add_alert_outlined),
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
          child: Column(
            children: [
              SegmentedButton<ChartMode>(
                segments: const [
                  ButtonSegment(
                      value: ChartMode.line,
                      label: Text('Linha'),
                      icon: Icon(Icons.show_chart)),
                  ButtonSegment(
                      value: ChartMode.candles,
                      label: Text('Candles'),
                      icon: Icon(Icons.candlestick_chart)),
                ],
                selected: {_mode},
                onSelectionChanged: (value) =>
                    setState(() => _mode = value.first),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: InteractivePriceChart(
                  candles: widget.candles,
                  mode: _mode,
                  selectedIndex: _selectedIndex,
                  onSelected: (index) => setState(() => _selectedIndex = index),
                  height: double.infinity,
                ),
              ),
              if (selected != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    'Preço selecionado: ${priceText(selected['close'])} ${widget.currency}',
                    style: numericStyle.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
