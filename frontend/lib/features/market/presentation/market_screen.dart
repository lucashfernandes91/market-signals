import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/preferences/app_preferences.dart';
import '../../../core/session/session_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/presentation/auth_screen.dart';
import '../../favorites/data/favorite_store.dart';
import '../data/market_providers.dart';
import '../models/market.dart';
import 'market_widgets.dart';
export '../data/market_providers.dart';

class MarketScreen extends ConsumerStatefulWidget {
  const MarketScreen({super.key});
  @override
  ConsumerState<MarketScreen> createState() => _MarketScreenState();
}

class _MarketScreenState extends ConsumerState<MarketScreen> {
  var _filter = 'Todos';

  Future<void> _refresh() async {
    final favoriteIds = ref.read(favoriteIdsProvider).valueOrNull ?? <String>{};
    final favoriteIdsKey = (favoriteIds.toList()..sort()).join(',');
    ref.invalidate(currencyConversionProvider);
    ref.invalidate(marketQuotesProvider);
    ref.invalidate(marketOverviewProvider);
    ref.invalidate(marketsByIdsProvider(favoriteIdsKey));
    ref.invalidate(radarProvider);
    ref.invalidate(marketsProvider);
    try {
      if (_filter == 'Favoritos') {
        await ref.read(marketsByIdsProvider(favoriteIdsKey).future);
      } else {
        await ref.read(marketsProvider.future);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final markets = ref.watch(marketOverviewProvider);
    final quotes = ref.watch(marketQuotesProvider);
    final currency = ref.watch(displayCurrencyProvider);
    final layout =
        ref.watch(appPreferencesProvider).valueOrNull?.marketLayout ??
            MarketLayout.grid;
    final isAuthenticated =
        ref.watch(sessionControllerProvider).isAuthenticated;
    final favorites = ref.watch(favoriteIdsProvider);
    final favoriteIds = favorites.valueOrNull ?? <String>{};
    final favoriteIdsKey = (favoriteIds.toList()..sort()).join(',');
    final favoriteMarkets = _filter == 'Favoritos'
        ? ref.watch(marketsByIdsProvider(favoriteIdsKey))
        : null;
    final now = ref.watch(marketClockProvider).asData?.value ?? DateTime.now();
    final activeMarkets = favoriteMarkets ?? markets;
    final all = activeMarkets.asData?.value ?? <Market>[];
    final useLegacyHistory = _filter != 'Favoritos' &&
        all.isNotEmpty &&
        all.every((market) => market.change24hPercent == null);
    final history = useLegacyHistory
        ? <String, List<Map<String, dynamic>>>{
            for (final market in all)
              market.id: ref
                      .watch(chartProvider((market.id, ChartPeriod.day)))
                      .asData
                      ?.value ??
                  [],
          }
        : const <String, List<Map<String, dynamic>>>{};
    double? changeFor(Market market) =>
        number(quotes.asData?.value[market.id]?['change_24h_percent']) ??
        number(market.change24hPercent) ??
        candleChange(history[market.id] ?? const []);
    final items = all.where((m) {
      final change = changeFor(m);
      return switch (_filter) {
        'Todos' => true,
        'Favoritos' => favoriteIds.contains(m.id),
        'Em alta' => change != null && change > 0,
        _ => change != null && change < 0,
      };
    }).toList();
    final favoritesEmpty = _filter == 'Favoritos' &&
        !activeMarkets.isLoading &&
        !activeMarkets.hasError &&
        items.isEmpty;
    if (_filter == 'Em alta') {
      items.sort((a, b) => changeFor(b)!.compareTo(changeFor(a)!));
    } else if (_filter == 'Em queda') {
      items.sort((a, b) => changeFor(a)!.compareTo(changeFor(b)!));
    }
    return SafeArea(
        child: RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        key: const PageStorageKey('market-list'),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          MarketHeader(
              title: 'Mercado',
              subtitle: _filter == 'Favoritos'
                  ? 'Seus ativos salvos neste aparelho.'
                  : 'Top 10 por volume · 24 h',
              onRefresh: _refresh,
              showRefresh: false,
              trailingAction: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _MarketLayoutToggle(
                    value: layout,
                    onChanged: (value) => ref
                        .read(appPreferencesProvider.notifier)
                        .update(marketLayout: value)),
              )),
          if (!isAuthenticated)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: OutlinedButton.icon(
                onPressed: () => requireAccount(
                  context,
                  ref,
                  action: 'adicionar ativos ao Mercado',
                ),
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('Adicionar ativos'),
              ),
            ),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final filter in [
                  'Todos',
                  'Favoritos',
                  'Em alta',
                  'Em queda'
                ])
                  ChoiceChip(
                      label: Text(filter),
                      selected: filter == _filter,
                      showCheckmark: false,
                      selectedColor: AppTheme.accent.withValues(alpha: .09),
                      backgroundColor: Theme.of(context).colorScheme.surface,
                      side: BorderSide(
                          color: filter == _filter
                              ? Colors.transparent
                              : AppTheme.line),
                      labelStyle: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: filter == _filter
                              ? AppTheme.accent
                              : AppTheme.muted),
                      onSelected: (_) => setState(() => _filter = filter)),
              ])),
          if (_filter == 'Favoritos' && !favoritesEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
              child: FilledButton.icon(
                onPressed: _showFavoritePicker,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Adicionar favorito'),
              ),
            ),
          if (layout == MarketLayout.list)
            Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
                child: Row(children: [
                  const Expanded(
                      child: Text('ATIVO / FONTE',
                          style: TextStyle(
                              fontSize: 10,
                              letterSpacing: 1,
                              color: AppTheme.muted,
                              fontWeight: FontWeight.w700))),
                  Text('PREÇO / VAR. 24H',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 10,
                          letterSpacing: .8,
                          fontWeight: FontWeight.w700)),
                ])),
          if (activeMarkets.isLoading && all.isEmpty)
            const AsyncStatePanel.loading(label: 'Carregando ativos…'),
          if (activeMarkets.hasError && all.isEmpty)
            AsyncStatePanel.unavailable(
                title: _filter == 'Favoritos'
                    ? 'Não foi possível carregar seus favoritos'
                    : 'Não foi possível carregar o mercado',
                description: 'Confira a conexão e tente novamente.',
                onRetry: _refresh)
          else if (!activeMarkets.isLoading && items.isEmpty)
            AsyncStatePanel.empty(
              title: _filter == 'Favoritos'
                  ? 'Adicione seu primeiro favorito'
                  : all.isEmpty
                      ? 'Nenhum ativo disponível'
                      : 'Nenhum ativo encontrado',
              description: _filter == 'Favoritos'
                  ? 'Adicione qualquer par disponível ou toque na estrela na lista Todos.'
                  : _filter == 'Todos'
                      ? 'Tente buscar pelo nome ou símbolo da moeda.'
                      : 'Nenhum ativo com essa variação na janela analisada.',
              icon: _filter == 'Favoritos'
                  ? Icons.star_border_rounded
                  : Icons.inbox_outlined,
              actionLabel: _filter == 'Favoritos' ? 'Adicionar favorito' : null,
              actionIcon: _filter == 'Favoritos' ? Icons.add_rounded : null,
              onAction: _filter == 'Favoritos' ? _showFavoritePicker : null,
            ),
          if (items.isNotEmpty)
            Padding(
                padding: EdgeInsets.fromLTRB(
                    20, layout == MarketLayout.grid ? 6 : 0, 20, 0),
                child: layout == MarketLayout.grid
                    ? LayoutBuilder(
                        builder: (context, constraints) {
                          final textScale =
                              MediaQuery.textScalerOf(context).scale(1);
                          final columns =
                              constraints.maxWidth >= 320 && textScale <= 1.25
                                  ? 2
                                  : 1;
                          return GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: items.length,
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: columns,
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                              childAspectRatio: columns == 2 ? 1.57 : 1.9,
                            ),
                            itemBuilder: (context, i) => MarketGridCard(
                              market: items[i],
                              quote: quotes.asData?.value[items[i].id],
                              now: now,
                              loading: quotes.isLoading,
                              currency: currency,
                              isFavorite: favoriteIds.contains(items[i].id),
                              favoriteLoading: favorites.isLoading,
                              onFavorite: () => _toggleFavorite(items[i]),
                            ),
                          );
                        },
                      )
                    : Card(
                        child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: Column(children: [
                              for (var i = 0; i < items.length; i++) ...[
                                if (i > 0)
                                  const Divider(indent: 16, endIndent: 16),
                                MarketListRow(
                                    market: items[i],
                                    quote: quotes.asData?.value[items[i].id],
                                    history: history[items[i].id] ?? const [],
                                    now: now,
                                    loading: quotes.isLoading,
                                    currency: currency,
                                    isFavorite:
                                        favoriteIds.contains(items[i].id),
                                    favoriteLoading: favorites.isLoading,
                                    onFavorite: () =>
                                        _toggleFavorite(items[i])),
                              ],
                            ])),
                      )),
          Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
              child: Text(
                  '${_filter == 'Favoritos' ? 'Favoritos salvos neste aparelho.\n' : isAuthenticated ? '' : 'Visitante: 10 pares com maior volume transacionado em 24h.\n'}Valores convertidos para $currency.\nVariação de 24 h fornecida pelo mercado.',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 11,
                      height: 1.4))),
        ],
      ),
    ));
  }

  Future<void> _toggleFavorite(Market market) async {
    try {
      await ref.read(favoriteIdsProvider.notifier).toggle(market.id);
      if (mounted) {
        final selected =
            ref.read(favoriteIdsProvider).valueOrNull?.contains(market.id) ==
                true;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(selected
              ? '${market.displayName} adicionado aos favoritos.'
              : '${market.displayName} removido dos favoritos.'),
          duration: const Duration(seconds: 2),
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Não foi possível salvar o favorito neste aparelho.'),
        ));
      }
    }
  }

  Future<void> _showFavoritePicker() => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => const _FavoriteMarketPicker(),
      );
}

class _FavoriteMarketPicker extends ConsumerStatefulWidget {
  const _FavoriteMarketPicker();

  @override
  ConsumerState<_FavoriteMarketPicker> createState() =>
      _FavoriteMarketPickerState();
}

class _FavoriteMarketPickerState extends ConsumerState<_FavoriteMarketPicker> {
  final _searchController = TextEditingController();
  final _updatingIds = <String>{};
  var _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final markets = ref.watch(marketsProvider);
    final favorites = ref.watch(favoriteIdsProvider);
    final favoriteIds = favorites.valueOrNull ?? <String>{};
    final normalizedQuery = _query.trim().toLowerCase();
    final items = (markets.valueOrNull ?? <Market>[]).where((market) {
      if (normalizedQuery.isEmpty) return true;
      return market.symbol.toLowerCase().contains(normalizedQuery) ||
          market.displayName.toLowerCase().contains(normalizedQuery) ||
          market.base.toLowerCase().contains(normalizedQuery) ||
          market.quote.toLowerCase().contains(normalizedQuery) ||
          (market.providerSymbol?.toLowerCase().contains(normalizedQuery) ??
              false);
    }).toList()
      ..sort((a, b) {
        final favoriteOrder = (favoriteIds.contains(b.id) ? 1 : 0)
            .compareTo(favoriteIds.contains(a.id) ? 1 : 0);
        return favoriteOrder != 0
            ? favoriteOrder
            : a.symbol.compareTo(b.symbol);
      });

    return FractionallySizedBox(
      heightFactor: .92,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Adicionar favoritos',
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 3),
                      const Text(
                        'Escolha os pares que quer acompanhar.',
                        style: TextStyle(color: AppTheme.muted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Fechar',
                  onPressed: () => Navigator.of(context).pop(),
                  constraints:
                      const BoxConstraints.tightFor(width: 48, height: 48),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                labelText: 'Buscar par',
                hintText: 'Ex.: BTC, ETH ou USDT',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Limpar busca',
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 6),
            child: Text(
              markets.isLoading
                  ? 'CARREGANDO PARES'
                  : '${items.length} ${items.length == 1 ? 'PAR DISPONÍVEL' : 'PARES DISPONÍVEIS'}',
              style: const TextStyle(
                color: AppTheme.muted,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
          ),
          Expanded(
            child: markets.isLoading
                ? const Center(child: CircularProgressIndicator())
                : markets.hasError
                    ? AsyncStatePanel.unavailable(
                        title: 'Não foi possível carregar os pares',
                        description: 'Confira a conexão e tente novamente.',
                        onRetry: () => ref.invalidate(marketsProvider),
                      )
                    : items.isEmpty
                        ? const AsyncStatePanel.empty(
                            title: 'Nenhum par encontrado',
                            description:
                                'Tente buscar por outro nome ou símbolo.',
                          )
                        : ListView.separated(
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                            itemCount: items.length,
                            separatorBuilder: (_, __) =>
                                const Divider(indent: 64, endIndent: 12),
                            itemBuilder: (context, index) {
                              final market = items[index];
                              final selected = favoriteIds.contains(market.id);
                              final updating = _updatingIds.contains(market.id);
                              return ListTile(
                                minTileHeight: 60,
                                leading: CoinAvatar(market.base, size: 36),
                                title: Text('${market.base} / ${market.quote}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                                subtitle: Text(
                                  market.displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onTap: updating ? null : () => _toggle(market),
                                trailing: IconButton(
                                  tooltip: selected
                                      ? 'Remover dos favoritos'
                                      : 'Adicionar aos favoritos',
                                  onPressed:
                                      updating ? null : () => _toggle(market),
                                  constraints: const BoxConstraints.tightFor(
                                      width: 48, height: 48),
                                  icon: updating
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2),
                                        )
                                      : Icon(
                                          selected
                                              ? Icons.star_rounded
                                              : Icons.star_border_rounded,
                                          color: selected
                                              ? const Color(0xFFD57A08)
                                              : AppTheme.muted,
                                        ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggle(Market market) async {
    setState(() => _updatingIds.add(market.id));
    try {
      await ref.read(favoriteIdsProvider.notifier).toggle(market.id);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Não foi possível atualizar seus favoritos.'),
        ));
      }
    } finally {
      if (mounted) setState(() => _updatingIds.remove(market.id));
    }
  }
}

class _MarketLayoutToggle extends StatelessWidget {
  const _MarketLayoutToggle({required this.value, required this.onChanged});

  final MarketLayout value;
  final ValueChanged<MarketLayout> onChanged;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border.all(color: AppTheme.line),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _button(
              MarketLayout.grid, Icons.grid_view_rounded, 'Exibir em grade'),
          _button(
              MarketLayout.list, Icons.view_list_rounded, 'Exibir em lista'),
        ]),
      );

  Widget _button(MarketLayout layout, IconData icon, String tooltip) =>
      IconButton(
        tooltip: tooltip,
        onPressed: value == layout ? null : () => onChanged(layout),
        constraints: const BoxConstraints.tightFor(width: 44, height: 44),
        style: IconButton.styleFrom(
          disabledBackgroundColor: AppTheme.accent.withValues(alpha: .10),
          disabledForegroundColor: AppTheme.accent,
          foregroundColor: AppTheme.muted,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
        ),
        icon: Icon(icon, size: 22),
      );
}

class MarketGridCard extends StatelessWidget {
  const MarketGridCard({
    required this.market,
    required this.quote,
    required this.now,
    required this.loading,
    required this.currency,
    required this.isFavorite,
    required this.onFavorite,
    this.favoriteLoading = false,
    super.key,
  });

  final Market market;
  final Map<String, dynamic>? quote;
  final DateTime now;
  final bool loading;
  final String currency;
  final bool isFavorite;
  final bool favoriteLoading;
  final VoidCallback onFavorite;

  @override
  Widget build(BuildContext context) {
    final effectiveQuote = quote ??
        {
          if (market.price != null) 'price': market.price,
          if (market.change24hPercent != null)
            'change_24h_percent': market.change24hPercent,
          if (market.volume24h != null) 'volume_24h': market.volume24h,
          if (market.timestamp != null)
            'timestamp': market.timestamp!.toIso8601String(),
          if (market.stale != null) 'stale': market.stale,
        };
    final price = number(effectiveQuote['price']);
    final change = number(effectiveQuote['change_24h_percent']);
    final volume = effectiveQuote['volume_24h'] ?? market.volume24h;
    final fresh = quoteFresh(effectiveQuote, now);
    final priceLabel = price == null
        ? loading
            ? 'Carregando…'
            : 'Indisponível'
        : '${currency == 'BRL' ? 'R\$' : 'US\$'} ${priceText(price)}';
    final quoteSymbol = market.quote.isEmpty ? 'USDT' : market.quote;

    return Semantics(
      button: true,
      label:
          '${market.displayName}, $priceLabel, variação ${percentText(change)}, volume de 24 horas ${compactText(volume)}',
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () =>
              Navigator.of(context).pushNamed('/asset', arguments: market),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(children: [
                  CoinAvatar(market.base, size: 32),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${market.base} / $quoteSymbol',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(market.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: AppTheme.muted,
                                fontSize: 10,
                                fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: isFavorite
                        ? 'Remover dos favoritos'
                        : 'Adicionar aos favoritos',
                    onPressed: favoriteLoading ? null : onFavorite,
                    constraints:
                        const BoxConstraints.tightFor(width: 48, height: 48),
                    padding: EdgeInsets.zero,
                    iconSize: 23,
                    icon: Icon(
                      isFavorite
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      color:
                          isFavorite ? const Color(0xFFD57A08) : AppTheme.muted,
                    ),
                  ),
                ]),
                const SizedBox(height: 2.2),
                Row(children: [
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(priceLabel,
                          maxLines: 1,
                          style: numericStyle.copyWith(
                              fontSize: price == null ? 12 : 16,
                              fontWeight: FontWeight.w800)),
                    ),
                  ),
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 72,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: ChangeBadge(change, compact: true),
                    ),
                  ),
                ]),
                const SizedBox(height: 1.2),
                Row(children: [
                  Expanded(
                    child: Text('Vol. 24 h  ${compactText(volume)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 10, color: AppTheme.muted)),
                  ),
                  if (price != null && !fresh)
                    const Tooltip(
                      message: 'Última cotação recebida está desatualizada',
                      child: Icon(Icons.schedule_rounded,
                          size: 17, color: Color(0xFF936000)),
                    ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MarketListRow extends StatelessWidget {
  const MarketListRow(
      {required this.market,
      required this.quote,
      required this.history,
      required this.now,
      required this.loading,
      required this.currency,
      required this.isFavorite,
      required this.onFavorite,
      this.favoriteLoading = false,
      super.key});
  final Market market;
  final Map<String, dynamic>? quote;
  final List<Map<String, dynamic>> history;
  final DateTime now;
  final bool loading;
  final String currency;
  final bool isFavorite;
  final bool favoriteLoading;
  final VoidCallback onFavorite;
  @override
  Widget build(BuildContext context) {
    final effectiveQuote = quote ??
        {
          if (market.price != null) 'price': market.price,
          if (market.change24hPercent != null)
            'change_24h_percent': market.change24hPercent,
          if (market.timestamp != null)
            'timestamp': market.timestamp!.toIso8601String(),
          if (market.stale != null) 'stale': market.stale,
        };
    final change = number(effectiveQuote['change_24h_percent']);
    final hasPrice = number(effectiveQuote['price']) != null;
    final fresh = quoteFresh(effectiveQuote, now);
    return InkWell(
      onTap: () => Navigator.of(context).pushNamed('/asset', arguments: market),
      child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CoinAvatar(market.base, size: 36),
              const SizedBox(width: 10),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(market.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text('${market.base} · ${market.sourceLabel}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11, color: AppTheme.muted)),
                  ])),
              const SizedBox(width: 8),
              Flexible(
                  fit: FlexFit.tight,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                            hasPrice
                                ? priceText(effectiveQuote['price'])
                                : loading
                                    ? 'Carregando…'
                                    : 'Indisponível',
                            style: numericStyle.copyWith(
                                fontSize: hasPrice ? 17 : 12,
                                fontWeight: FontWeight.w700),
                            textAlign: TextAlign.end),
                        const SizedBox(height: 3),
                        Text(currency,
                            style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: AppTheme.muted)),
                      ])),
            ]),
            const SizedBox(height: 2),
            Row(children: [
              SizedBox(
                  width: 78,
                  child: Text(
                      'Vol. ${compactText(effectiveQuote['volume_24h'] ?? market.volume24h)}',
                      style: const TextStyle(
                          fontSize: 10, color: AppTheme.muted))),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(
                      hasPrice
                          ? fresh
                              ? 'Cotação atual'
                              : 'Última cotação'
                          : 'Aguardando preço',
                      style: TextStyle(
                          fontSize: 10,
                          color: hasPrice && !fresh
                              ? const Color(0xFF936000)
                              : AppTheme.muted))),
              IconButton(
                tooltip: isFavorite
                    ? 'Remover dos favoritos'
                    : 'Adicionar aos favoritos',
                onPressed: favoriteLoading ? null : onFavorite,
                constraints:
                    const BoxConstraints.tightFor(width: 48, height: 48),
                icon: Icon(
                  isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                  color: isFavorite ? const Color(0xFFD57A08) : AppTheme.muted,
                ),
              ),
              ChangeBadge(change),
            ]),
          ])),
    );
  }
}
