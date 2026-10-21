import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/session/session_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/presentation/auth_screen.dart';
import '../../market/models/market.dart';
import '../../market/presentation/market_screen.dart';
import '../../market/presentation/market_widgets.dart';
import '../../profile/presentation/profile_screen.dart';
import '../../watchlists/presentation/watchlists_screen.dart';
import '../data/favorite_store.dart';

class FavoritesScreen extends ConsumerStatefulWidget {
  const FavoritesScreen({super.key});

  @override
  ConsumerState<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends ConsumerState<FavoritesScreen> {
  var _syncing = false;

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(displayCurrencyProvider);
    final favorites = ref.watch(favoriteIdsProvider);
    final favoriteIds = favorites.valueOrNull ?? <String>{};
    final idsKey = (favoriteIds.toList()..sort()).join(',');
    final lookup = ref.watch(marketsByIdsProvider(idsKey));
    final items = lookup.valueOrNull ?? <Market>[];
    final quotes = ref.watch(marketQuotesProvider);
    final now = ref.watch(marketClockProvider).valueOrNull ?? DateTime.now();
    final authenticated = ref.watch(sessionControllerProvider).isAuthenticated;
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          key: const PageStorageKey('favorites'),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            MarketHeader(
              title: 'Favoritos',
              subtitle: 'Sua seleção fica salva neste aparelho.',
              onProfile: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              ),
              onRefresh: _refresh,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF0FF),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(children: [
                  const Icon(Icons.cloud_sync_outlined, color: AppTheme.accent),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          authenticated
                              ? 'Sincronização disponível'
                              : 'Conta opcional',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          authenticated
                              ? 'Envie seus favoritos para sua lista padrão.'
                              : 'Entre somente para usar estes favoritos em outros aparelhos.',
                          style: const TextStyle(
                              color: AppTheme.muted, fontSize: 12, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _syncing ? null : _sync,
                    child: _syncing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(authenticated ? 'Sincronizar' : 'Entrar'),
                  ),
                ]),
              ),
            ),
            if (lookup.isLoading || favorites.isLoading)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (lookup.hasError || favorites.hasError)
              AsyncStatePanel.unavailable(
                title: 'Não foi possível carregar seus favoritos',
                description:
                    'Tente novamente. Seus dados locais não serão apagados.',
                onRetry: _refresh,
              )
            else if (items.isEmpty)
              const AsyncStatePanel.empty(
                title: 'Nenhum favorito ainda',
                description:
                    'Na tela Mercado, toque na estrela de uma moeda para encontrá-la aqui.',
                icon: Icons.star_border_rounded,
              )
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(26, 2, 26, 10),
                child: Row(children: [
                  Text(
                      '${items.length} ${items.length == 1 ? 'ATIVO' : 'ATIVOS'}',
                      style: const TextStyle(
                          fontSize: 10,
                          letterSpacing: 1,
                          color: AppTheme.muted,
                          fontWeight: FontWeight.w700)),
                  const Spacer(),
                  const Text('PREÇO / VAR. 24H',
                      style: TextStyle(
                          fontSize: 10,
                          letterSpacing: .8,
                          color: AppTheme.muted,
                          fontWeight: FontWeight.w700)),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Card(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Column(children: [
                      for (var index = 0; index < items.length; index++) ...[
                        if (index > 0) const Divider(indent: 16, endIndent: 16),
                        MarketListRow(
                          market: items[index],
                          quote: quotes.valueOrNull?[items[index].id],
                          history: const [],
                          now: now,
                          loading: quotes.isLoading,
                          currency: currency,
                          isFavorite: true,
                          onFavorite: () => _remove(items[index]),
                        ),
                      ],
                    ]),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(26, 16, 26, 28),
                child: Text(
                  'Favoritos locais continuam disponíveis mesmo sem conexão com uma conta.',
                  style: TextStyle(
                      color: AppTheme.muted, fontSize: 11, height: 1.5),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _refresh() async {
    final ids = ref.read(favoriteIdsProvider).valueOrNull ?? <String>{};
    final idsKey = (ids.toList()..sort()).join(',');
    ref.invalidate(marketsByIdsProvider(idsKey));
    ref.invalidate(marketQuotesProvider);
    try {
      await ref.read(marketsByIdsProvider(idsKey).future);
    } catch (_) {}
  }

  Future<void> _remove(Market market) async {
    await ref.read(favoriteIdsProvider.notifier).toggle(market.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${market.displayName} removido dos favoritos.'),
        action: SnackBarAction(
          label: 'Desfazer',
          onPressed: () =>
              ref.read(favoriteIdsProvider.notifier).toggle(market.id),
        ),
      ));
    }
  }

  Future<void> _sync() async {
    final ready = await requireAccount(
      context,
      ref,
      action: 'sincronizar seus favoritos',
    );
    if (!ready || !mounted) return;
    setState(() => _syncing = true);
    try {
      final result = await syncFavorites(ref);
      ref.invalidate(watchlistsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(result.uploaded == 0
              ? '${result.localCount} favoritos já estão sincronizados.'
              : '${result.uploaded} favoritos sincronizados com sua conta.'),
        ));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Não foi possível sincronizar: $error'),
        ));
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }
}
