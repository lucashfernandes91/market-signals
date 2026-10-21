import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/session/session_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../market/presentation/market_screen.dart';
import '../../market/presentation/market_widgets.dart';

final watchlistsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final raw = await ref.watch(apiClientProvider).get('/watchlists/');
  final items = raw is List
      ? raw
      : (raw as Map<String, dynamic>)['results'] as List<dynamic>? ?? const [];
  return items.cast<Map<String, dynamic>>();
});

class WatchlistsScreen extends ConsumerWidget {
  const WatchlistsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lists = ref.watch(watchlistsProvider);
    final hasLists = lists.asData?.value.isNotEmpty ?? false;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Listas sincronizadas'),
        actions: [
          IconButton(
            onPressed: () => ref.invalidate(watchlistsProvider),
            tooltip: 'Atualizar listas',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: hasLists
          ? FloatingActionButton.extended(
              onPressed: () => _editWatchlist(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('Nova lista'),
            )
          : null,
      body: lists.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => AsyncStatePanel.unavailable(
          title: 'Listas indisponíveis',
          description: 'Não foi possível atualizar suas listas.',
          onRetry: () => ref.invalidate(watchlistsProvider),
        ),
        data: (items) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(watchlistsProvider),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 96),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Row(children: [
                  Icon(Icons.drag_indicator_rounded, color: AppTheme.accent),
                  SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Ordem personalizada',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                        SizedBox(height: 3),
                        Text('Arraste os ativos para organizar cada lista.',
                            style: TextStyle(
                                color: AppTheme.muted,
                                fontSize: 12,
                                height: 1.4)),
                      ],
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 18),
              if (items.isEmpty)
                AsyncStatePanel.empty(
                  title: 'Crie sua primeira lista',
                  description:
                      'Crie uma lista ou sincronize seus favoritos locais.',
                  icon: Icons.playlist_add_rounded,
                  actionLabel: 'Criar lista',
                  actionIcon: Icons.add_rounded,
                  onAction: () => _editWatchlist(context, ref),
                )
              else
                for (final item in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _WatchlistCard(
                      key: ValueKey(item['id']),
                      watchlist: item,
                      onEdit: () =>
                          _editWatchlist(context, ref, watchlist: item),
                      onDelete: () => _deleteWatchlist(context, ref, item),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteWatchlist(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> watchlist,
  ) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Excluir esta lista?'),
            content: const Text(
                'Os favoritos locais deste aparelho não serão apagados.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Excluir'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    await ref.read(apiClientProvider).delete('/watchlists/${watchlist['id']}/');
    ref.invalidate(watchlistsProvider);
  }

  Future<void> _editWatchlist(
    BuildContext context,
    WidgetRef ref, {
    Map<String, dynamic>? watchlist,
  }) async {
    final draft = await showDialog<_WatchlistDraft>(
      context: context,
      builder: (_) => _WatchlistEditor(watchlist: watchlist),
    );
    if (draft == null) return;
    try {
      final body = {'name': draft.name, 'is_default': draft.isDefault};
      if (watchlist == null) {
        await ref.read(apiClientProvider).post('/watchlists/', body);
      } else {
        await ref
            .read(apiClientProvider)
            .patch('/watchlists/${watchlist['id']}/', body);
      }
      ref.invalidate(watchlistsProvider);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    }
  }
}

class _WatchlistCard extends ConsumerStatefulWidget {
  const _WatchlistCard({
    required this.watchlist,
    required this.onEdit,
    required this.onDelete,
    super.key,
  });

  final Map<String, dynamic> watchlist;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  ConsumerState<_WatchlistCard> createState() => _WatchlistCardState();
}

class _WatchlistCardState extends ConsumerState<_WatchlistCard> {
  late List<Map<String, dynamic>> _items = _readItems();
  var _savingOrder = false;

  List<Map<String, dynamic>> _readItems() =>
      (widget.watchlist['items'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>()
          .toList();

  @override
  void didUpdateWidget(covariant _WatchlistCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_savingOrder) _items = _readItems();
  }

  @override
  Widget build(BuildContext context) => Card(
        child: ExpansionTile(
          initiallyExpanded: true,
          leading: Icon(
            widget.watchlist['is_default'] == true
                ? Icons.star_rounded
                : Icons.list_alt_rounded,
            color: AppTheme.accent,
          ),
          title: Text('${widget.watchlist['name']}',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(
              '${_items.length} ${_items.length == 1 ? 'ativo' : 'ativos'}'),
          trailing: PopupMenuButton<_WatchlistAction>(
            onSelected: (action) => switch (action) {
              _WatchlistAction.edit => widget.onEdit(),
              _WatchlistAction.copy => _copyWatchlist(),
              _WatchlistAction.delete => widget.onDelete(),
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                  value: _WatchlistAction.edit, child: Text('Editar')),
              PopupMenuItem(
                  value: _WatchlistAction.copy, child: Text('Copiar lista')),
              PopupMenuItem(
                  value: _WatchlistAction.delete, child: Text('Excluir')),
            ],
          ),
          children: [
            if (_items.isEmpty)
              const ListTile(title: Text('Adicione ativos a esta lista.'))
            else
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: _items.length,
                onReorderItem: _savingOrder ? (_, __) {} : _reorder,
                itemBuilder: (context, index) {
                  final entry = _items[index];
                  final market = entry['market'] as Map<String, dynamic>?;
                  return ListTile(
                    key: ValueKey(market?['id'] ?? index),
                    leading: ReorderableDragStartListener(
                      index: index,
                      child: const SizedBox(
                        width: 48,
                        height: 48,
                        child: Icon(Icons.drag_handle_rounded),
                      ),
                    ),
                    title: Text('${market?['canonical_symbol'] ?? '-'}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      tooltip: 'Remover ativo',
                      onPressed: () => _removeMarket(entry),
                    ),
                  );
                },
              ),
            ListTile(
              minTileHeight: 56,
              leading:
                  const Icon(Icons.add_circle_outline, color: AppTheme.accent),
              title: const Text('Adicionar ativo'),
              onTap: _addMarket,
            ),
          ],
        ),
      );

  Future<void> _reorder(int oldIndex, int newIndex) async {
    final previous = List<Map<String, dynamic>>.of(_items);
    setState(() {
      _items.insert(newIndex, _items.removeAt(oldIndex));
      _savingOrder = true;
    });
    try {
      await ref.read(apiClientProvider).patch(
        '/watchlists/${widget.watchlist['id']}/items/order/',
        {
          'market_ids': [
            for (final entry in _items)
              '${(entry['market'] as Map<String, dynamic>)['id']}',
          ],
        },
      );
      ref.invalidate(watchlistsProvider);
    } catch (error) {
      if (mounted) {
        setState(() => _items = previous);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível salvar a ordem: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingOrder = false);
    }
  }

  Future<void> _addMarket() async {
    final markets = await ref.read(marketsProvider.future);
    if (!mounted) return;
    final existing = _items
        .map((entry) => (entry['market'] as Map<String, dynamic>?)?['id'])
        .toSet();
    final available =
        markets.where((market) => !existing.contains(market.id)).toList();
    final selected = await showDialog<Set<String>>(
      context: context,
      builder: (context) {
        var query = '';
        final selectedIds = <String>{};
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filtered = available.where((market) {
              final haystack =
                  '${market.displayName} ${market.base} ${market.symbol}'
                      .toLowerCase();
              return haystack.contains(query.trim().toLowerCase());
            });
            return AlertDialog(
              title: const Text('Adicionar ativos'),
              content: SizedBox(
                width: 380,
                height: 420,
                child: Column(children: [
                  TextField(
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Buscar por nome ou símbolo',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                    onChanged: (value) => setDialogState(() => query = value),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final market in filtered)
                          CheckboxListTile(
                            value: selectedIds.contains(market.id),
                            title: Text(market.displayName),
                            subtitle: Text(market.symbol),
                            onChanged: (checked) => setDialogState(() {
                              checked == true
                                  ? selectedIds.add(market.id)
                                  : selectedIds.remove(market.id);
                            }),
                          ),
                      ],
                    ),
                  ),
                ]),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: selectedIds.isEmpty
                      ? null
                      : () => Navigator.pop(context, Set.of(selectedIds)),
                  child: const Text('Adicionar'),
                ),
              ],
            );
          },
        );
      },
    );
    if (selected == null || selected.isEmpty) return;
    try {
      await ref.read(apiClientProvider).post(
        '/watchlists/${widget.watchlist['id']}/items/batch/',
        {'market_ids': selected.toList()},
      );
      for (final marketId in selected) {
        _items.add({
          'market': {'id': marketId},
          'position': _items.length,
        });
      }
      ref.invalidate(watchlistsProvider);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    }
  }

  Future<void> _removeMarket(Map<String, dynamic> entry) async {
    final market = entry['market'] as Map<String, dynamic>?;
    if (market == null) return;
    final marketId = '${market['id']}';
    final position = entry['position'] as int? ?? _items.length;
    try {
      await ref.read(apiClientProvider).delete(
            '/watchlists/${widget.watchlist['id']}/items/${market['id']}/',
          );
      ref.invalidate(watchlistsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Ativo removido da lista.'),
          action: SnackBarAction(
            label: 'Desfazer',
            onPressed: () => _restoreMarket(marketId, position),
          ),
        ));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    }
  }

  Future<void> _restoreMarket(String marketId, int position) async {
    try {
      await ref.read(apiClientProvider).post(
        '/watchlists/${widget.watchlist['id']}/items/',
        {'market_id': marketId, 'position': position},
      );
      ref.invalidate(watchlistsProvider);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível desfazer: $error')),
        );
      }
    }
  }

  Future<void> _copyWatchlist() async {
    final draft = await showDialog<_WatchlistDraft>(
      context: context,
      builder: (_) => _WatchlistEditor(
        watchlist: {'name': 'Cópia de ${widget.watchlist['name']}'},
      ),
    );
    if (draft == null) return;
    try {
      await ref.read(apiClientProvider).post(
        '/watchlists/${widget.watchlist['id']}/copy/',
        {'name': draft.name},
      );
      ref.invalidate(watchlistsProvider);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }
}

enum _WatchlistAction { edit, copy, delete }

class _WatchlistDraft {
  const _WatchlistDraft({required this.name, required this.isDefault});
  final String name;
  final bool isDefault;
}

class _WatchlistEditor extends StatefulWidget {
  const _WatchlistEditor({this.watchlist});
  final Map<String, dynamic>? watchlist;

  @override
  State<_WatchlistEditor> createState() => _WatchlistEditorState();
}

class _WatchlistEditorState extends State<_WatchlistEditor> {
  late final TextEditingController _name = TextEditingController(
    text: widget.watchlist?['name']?.toString() ?? '',
  );
  late bool _isDefault = widget.watchlist?['is_default'] == true;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(
            widget.watchlist == null ? 'Nova watchlist' : 'Editar watchlist'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Nome'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _isDefault,
              onChanged: (value) => setState(() => _isDefault = value),
              title: const Text('Lista padrão'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final name = _name.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(
                  context,
                  _WatchlistDraft(name: name, isDefault: _isDefault),
                );
              }
            },
            child: const Text('Salvar'),
          ),
        ],
      );
}
