import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/preferences/app_preferences.dart';
import '../../../core/theme/app_theme.dart';
import '../../market/data/market_providers.dart';
import '../../onboarding/presentation/onboarding_screen.dart';

class PreferencesScreen extends ConsumerWidget {
  const PreferencesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(appPreferencesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Preferências')),
      body: preferences.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(
          child: Text('Não foi possível carregar as preferências.'),
        ),
        data: (data) => ListView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          children: [
            Text('EXIBIÇÃO', style: _sectionStyle(context)),
            const SizedBox(height: 10),
            Card(
              child: Column(children: [
                _PreferenceTile(
                  icon: Icons.payments_outlined,
                  title: 'Moeda',
                  value: data.currency.code,
                  onTap: () => _currency(context, ref, data.currency),
                ),
                const Divider(indent: 62),
                _PreferenceTile(
                  icon: Icons.contrast_rounded,
                  title: 'Tema',
                  value: switch (data.theme) {
                    ThemePreference.system => 'Sistema',
                    ThemePreference.light => 'Claro',
                    ThemePreference.dark => 'Escuro',
                  },
                  onTap: () => _theme(context, ref, data.theme),
                ),
              ]),
            ),
            const SizedBox(height: 24),
            Text('RADAR', style: _sectionStyle(context)),
            const SizedBox(height: 10),
            Card(
              child: _PreferenceTile(
                icon: Icons.tune_rounded,
                title: 'Perfil de monitoramento',
                value: data.monitoringProfile.label,
                onTap: () => _profile(context, ref, data.monitoringProfile),
              ),
            ),
            const SizedBox(height: 24),
            Card(
              child: _PreferenceTile(
                icon: Icons.auto_awesome_outlined,
                title: 'Rever configuração inicial',
                value: 'Onboarding opcional',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const OnboardingScreen(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  TextStyle _sectionStyle(BuildContext context) => TextStyle(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontSize: 11,
        letterSpacing: 1.2,
        fontWeight: FontWeight.w700,
      );

  Future<void> _currency(
    BuildContext context,
    WidgetRef ref,
    DisplayCurrency current,
  ) async {
    final value = await _choice<DisplayCurrency>(
      context,
      title: 'Moeda de exibição',
      current: current,
      values: DisplayCurrency.values,
      label: (item) => item == DisplayCurrency.brl
          ? 'Real brasileiro (BRL)'
          : 'Dólar americano (USD)',
    );
    if (value == null || value == current) return;
    if (!context.mounted) return;
    await _save(context, ref, currency: value);
    ref.invalidate(currencyConversionProvider);
    ref.invalidate(marketQuotesProvider);
    ref.invalidate(chartProvider);
    ref.invalidate(radarProvider);
    ref.invalidate(radarScopeProvider);
  }

  Future<void> _theme(
    BuildContext context,
    WidgetRef ref,
    ThemePreference current,
  ) async {
    final value = await _choice<ThemePreference>(
      context,
      title: 'Tema',
      current: current,
      values: ThemePreference.values,
      label: (item) => switch (item) {
        ThemePreference.system => 'Seguir o sistema',
        ThemePreference.light => 'Claro',
        ThemePreference.dark => 'Escuro',
      },
    );
    if (!context.mounted) return;
    if (value != null && value != current) {
      await _save(context, ref, theme: value);
    }
  }

  Future<void> _profile(
    BuildContext context,
    WidgetRef ref,
    MonitoringProfile current,
  ) async {
    final value = await _choice<MonitoringProfile>(
      context,
      title: 'Perfil de monitoramento',
      current: current,
      values: MonitoringProfile.values,
      label: (item) => item.label,
    );
    if (!context.mounted) return;
    if (value != null && value != current) {
      await _save(context, ref, monitoringProfile: value);
    }
  }

  Future<T?> _choice<T>(
    BuildContext context, {
    required String title,
    required T current,
    required List<T> values,
    required String Function(T) label,
  }) =>
      showDialog<T>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final value in values)
                ListTile(
                  minTileHeight: 52,
                  title: Text(label(value)),
                  trailing: value == current
                      ? const Icon(Icons.check_rounded, color: AppTheme.accent)
                      : null,
                  onTap: () => Navigator.pop(context, value),
                ),
            ],
          ),
        ),
      );

  Future<void> _save(
    BuildContext context,
    WidgetRef ref, {
    DisplayCurrency? currency,
    ThemePreference? theme,
    MonitoringProfile? monitoringProfile,
  }) async {
    try {
      await ref.read(appPreferencesProvider.notifier).update(
            currency: currency,
            theme: theme,
            monitoringProfile: monitoringProfile,
          );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível sincronizar: $error')),
        );
      }
    }
  }
}

class _PreferenceTile extends StatelessWidget {
  const _PreferenceTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        minTileHeight: 72,
        leading: Icon(icon, color: AppTheme.accent),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(value),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      );
}
