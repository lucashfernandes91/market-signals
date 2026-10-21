import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/session/session_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/notifications/push_coordinator.dart';
import '../../../core/notifications/push_notification_service.dart';
import '../../alerts/presentation/alerts_screen.dart';
import '../../auth/presentation/auth_screen.dart';
import '../../market/presentation/market_widgets.dart';
import '../../notifications/presentation/notifications_screen.dart';
import '../../watchlists/presentation/watchlists_screen.dart';
import 'preferences_screen.dart';

final currentUserProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  return await ref.watch(apiClientProvider).get('/auth/me/')
      as Map<String, dynamic>;
});

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    if (session.isLoading) {
      return Scaffold(
        body: SafeArea(
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [
              MarketHeader(
                title: 'Perfil',
                subtitle: 'Sua conta e preferências.',
                onRefresh: _noop,
                showRefresh: false,
              ),
              AsyncStatePanel.loading(label: 'Carregando perfil…'),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            if (session.isAuthenticated) {
              ref.invalidate(currentUserProvider);
              await ref.read(currentUserProvider.future);
            }
          },
          child: ListView(
            key: const PageStorageKey('profile'),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              MarketHeader(
                title: 'Perfil',
                subtitle: session.isAuthenticated
                    ? 'Sua conta e preferências.'
                    : 'Use o Radar livremente. A conta é opcional.',
                onRefresh: () {},
                showRefresh: false,
              ),
              if (session.isAuthenticated)
                _AuthenticatedProfile(user: ref.watch(currentUserProvider))
              else
                const _GuestProfile(),
            ],
          ),
        ),
      ),
    );
  }
}

void _noop() {}

class _GuestProfile extends ConsumerWidget {
  const _GuestProfile();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        child: Column(children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppTheme.accent.withValues(alpha: .09),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.person_outline,
                          color: AppTheme.accent),
                    ),
                    const SizedBox(height: 18),
                    Text('Você está usando como visitante',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    const Text(
                      'Seus favoritos ficam neste aparelho. Entre somente quando quiser sincronizar listas ou criar alertas.',
                      style: TextStyle(color: AppTheme.muted, height: 1.55),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => requireAccount(
                          context,
                          ref,
                          action: 'sincronizar favoritos e usar alertas',
                        ),
                        icon: const Icon(Icons.login),
                        label: const Text('Entrar ou criar conta'),
                      ),
                    ),
                  ]),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: _ProfileAction(
              icon: Icons.tune_rounded,
              title: 'Preferências',
              subtitle: 'Moeda, tema e perfil do Radar',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PreferencesScreen()),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const _BenefitRow(
            icon: Icons.star_outline_rounded,
            title: 'Favoritos locais',
            description: 'Continuam disponíveis sem conta.',
          ),
          const _BenefitRow(
            icon: Icons.sync_rounded,
            title: 'Listas sincronizadas',
            description: 'Acompanhe a mesma seleção em outros aparelhos.',
          ),
          const _BenefitRow(
            icon: Icons.notifications_none_rounded,
            title: 'Alertas',
            description: 'Receba avisos quando suas condições forem atingidas.',
          ),
        ]),
      );
}

class _AuthenticatedProfile extends ConsumerWidget {
  const _AuthenticatedProfile({required this.user});
  final AsyncValue<Map<String, dynamic>> user;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        child: Column(children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: .09),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.person, color: AppTheme.accent),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: user.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (_, __) => const Text('Conta conectada'),
                    data: (data) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Conta conectada',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text('${data['email'] ?? ''}',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppTheme.muted)),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppTheme.positive.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('Ativa',
                      style: TextStyle(
                          color: AppTheme.positive,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 18),
          _PushStatusCard(status: ref.watch(pushStatusProvider)),
          const SizedBox(height: 18),
          Card(
            child: Column(children: [
              _ProfileAction(
                icon: Icons.tune_rounded,
                title: 'Preferências',
                subtitle: 'Moeda, tema e perfil do Radar',
                onTap: () => _open(context, const PreferencesScreen()),
              ),
              const Divider(indent: 62),
              _ProfileAction(
                icon: Icons.playlist_add_check_rounded,
                title: 'Listas sincronizadas',
                subtitle: 'Crie e organize suas watchlists',
                onTap: () => _open(context, const WatchlistsScreen()),
              ),
              const Divider(indent: 62),
              _ProfileAction(
                icon: Icons.history_rounded,
                title: 'Histórico de notificações',
                subtitle: 'Veja os alertas que já dispararam',
                onTap: () => _open(context, const NotificationsScreen()),
              ),
            ]),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                await ref.read(pushNotificationServiceProvider).unregister();
                await ref.read(sessionControllerProvider.notifier).logout();
                ref.invalidate(currentUserProvider);
                ref.invalidate(watchlistsProvider);
                ref.invalidate(alertsProvider);
              },
              icon: const Icon(Icons.logout),
              label: const Text('Sair da conta'),
            ),
          ),
        ]),
      );

  Future<void> _open(BuildContext context, Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
}

class _PushStatusCard extends ConsumerWidget {
  const _PushStatusCard({required this.status});
  final PushStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ready = status == PushStatus.ready;
    final title = switch (status) {
      PushStatus.ready => 'Notificações ativas',
      PushStatus.denied => 'Permissão de notificação bloqueada',
      PushStatus.unavailable => 'Firebase ainda não configurado',
      PushStatus.initializing => 'Ativando notificações…',
      PushStatus.idle => 'Notificações pendentes',
    };
    final description = switch (status) {
      PushStatus.ready => 'Este aparelho receberá seus alertas.',
      PushStatus.denied => 'Libere a permissão nas configurações do Android.',
      PushStatus.unavailable =>
        'Adicione a configuração Firebase para registrar este aparelho.',
      _ => 'Aguarde enquanto verificamos este aparelho.',
    };
    return Card(
      child: ListTile(
        minTileHeight: 76,
        leading: Icon(
          ready ? Icons.notifications_active : Icons.notifications_off_outlined,
          color: ready ? AppTheme.positive : AppTheme.muted,
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(description),
        trailing: status == PushStatus.unavailable || status == PushStatus.idle
            ? IconButton(
                tooltip: 'Tentar ativar notificações',
                onPressed: () async {
                  ref.read(pushStatusProvider.notifier).state =
                      PushStatus.initializing;
                  final result = await ref
                      .read(pushNotificationServiceProvider)
                      .initialize();
                  ref.read(pushStatusProvider.notifier).state =
                      switch (result) {
                    PushInitResult.ready => PushStatus.ready,
                    PushInitResult.denied => PushStatus.denied,
                    PushInitResult.unavailable => PushStatus.unavailable,
                  };
                },
                icon: const Icon(Icons.refresh_rounded),
              )
            : null,
      ),
    );
  }
}

class _BenefitRow extends StatelessWidget {
  const _BenefitRow({
    required this.icon,
    required this.title,
    required this.description,
  });
  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Row(children: [
          Icon(icon, color: AppTheme.accent),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(description,
                  style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
            ],
          )),
        ]),
      );
}

class _ProfileAction extends StatelessWidget {
  const _ProfileAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        minTileHeight: 72,
        leading: Icon(icon, color: AppTheme.accent),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      );
}
