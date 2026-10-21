import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/session/session_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../market/data/market_providers.dart';
import '../../market/presentation/asset_screen.dart';
import '../../market/presentation/market_widgets.dart';

final notificationsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final raw = await ref.watch(apiClientProvider).get('/notifications/');
  final items = raw is List
      ? raw
      : (raw as Map<String, dynamic>)['results'] as List<dynamic>? ?? const [];
  return items.cast<Map<String, dynamic>>();
});

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(notificationsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificações'),
        actions: [
          IconButton(
            onPressed: () => ref.invalidate(notificationsProvider),
            tooltip: 'Atualizar notificações',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: notifications.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => AsyncStatePanel.unavailable(
          title: 'Histórico indisponível',
          description: 'Não foi possível carregar suas notificações.',
          onRetry: () => ref.invalidate(notificationsProvider),
        ),
        data: (items) {
          if (items.isEmpty) {
            return const Center(
              child: AsyncStatePanel.empty(
                title: 'Nenhuma notificação',
                description: 'Os alertas disparados aparecerão aqui.',
                icon: Icons.notifications_none_rounded,
              ),
            );
          }
          final groups = <String, List<Map<String, dynamic>>>{};
          for (final item in items) {
            final created =
                DateTime.tryParse('${item['created_at']}')?.toLocal();
            final label = _notificationDateLabel(created);
            groups.putIfAbsent(label, () => []).add(item);
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(notificationsProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
              children: [
                for (final group in groups.entries) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(2, 10, 2, 8),
                    child: Text(group.key,
                        style: const TextStyle(
                            color: AppTheme.muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ),
                  for (final notification in group.value)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _notificationCard(context, ref, notification),
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _notificationCard(
      BuildContext context, WidgetRef ref, Map<String, dynamic> notification) {
    final opened = notification['opened_at'] != null;
    final created =
        DateTime.tryParse('${notification['created_at']}')?.toLocal();
    final time = created == null
        ? ''
        : '${created.hour.toString().padLeft(2, '0')}:${created.minute.toString().padLeft(2, '0')}';
    return Card(
      child: ListTile(
        minTileHeight: 76,
        leading: Icon(
          opened ? Icons.mark_email_read : Icons.notifications,
          color: opened ? AppTheme.muted : AppTheme.accent,
        ),
        title: Text(notification['title']?.toString() ?? 'Notificação'),
        subtitle: Text(
            '${notification['body']?.toString() ?? ''}${time.isEmpty ? '' : ' · $time'}'),
        trailing: opened ? null : const Icon(Icons.circle, size: 10),
        onTap: () => _open(context, ref, notification),
      ),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref,
      Map<String, dynamic> notification) async {
    if (notification['opened_at'] == null) {
      await ref
          .read(apiClientProvider)
          .post('/notifications/${notification['id']}/opened/');
      ref.invalidate(notificationsProvider);
    }
    final rawPayload = notification['payload'];
    final payload = rawPayload is Map
        ? rawPayload.cast<String, dynamic>()
        : <String, dynamic>{};
    final marketId = payload['market_id']?.toString();
    if (marketId == null || marketId.isEmpty || !context.mounted) {
      if (context.mounted) {
        _showRecoverable(
            context, 'Esta notificação não tem um ativo de destino.');
      }
      return;
    }
    try {
      final markets =
          await ref.read(marketRepositoryProvider).lookup([marketId]);
      final market = markets.isEmpty ? null : markets.first;
      if (market != null && context.mounted) {
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => AssetScreen(market: market),
        ));
      } else if (context.mounted) {
        _showRecoverable(
            context, 'O ativo desta notificação não está mais disponível.');
      }
    } catch (_) {
      if (context.mounted) {
        _showRecoverable(
            context, 'Não foi possível abrir o ativo. Tente novamente.');
      }
    }
  }

  void _showRecoverable(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

String _notificationDateLabel(DateTime? date) {
  if (date == null) return 'Data desconhecida';
  final today = DateTime.now();
  final day = DateTime(date.year, date.month, date.day);
  final current = DateTime(today.year, today.month, today.day);
  final difference = current.difference(day).inDays;
  if (difference == 0) return 'Hoje';
  if (difference == 1) return 'Ontem';
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}
