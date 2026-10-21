import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/preferences/app_preferences.dart';
import '../../../core/theme/app_theme.dart';

class OnboardingGate extends ConsumerWidget {
  const OnboardingGate({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(appPreferencesProvider);
    return preferences.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => child,
      data: (data) =>
          data.onboardingComplete ? child : const OnboardingScreen(),
    );
  }
}

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  var _currency = DisplayCurrency.brl;
  var _profile = MonitoringProfile.conservative;
  var _saving = false;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          actions: [
            TextButton(
              onPressed: _saving ? null : _skip,
              child: const Text('Agora não'),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
              children: [
                Container(
                  width: 58,
                  height: 58,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: .1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.radar_rounded,
                      color: AppTheme.accent, size: 30),
                ),
                const SizedBox(height: 24),
                Text('Seu Radar, do seu jeito',
                    style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 10),
                Text(
                  'Escolha como deseja acompanhar o mercado. Você pode alterar tudo depois.',
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(height: 1.5),
                ),
                const SizedBox(height: 30),
                Text('Moeda de exibição',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                SegmentedButton<DisplayCurrency>(
                  segments: const [
                    ButtonSegment(
                        value: DisplayCurrency.brl, label: Text('Real (BRL)')),
                    ButtonSegment(
                        value: DisplayCurrency.usd, label: Text('Dólar (USD)')),
                  ],
                  selected: {_currency},
                  onSelectionChanged: (value) =>
                      setState(() => _currency = value.first),
                ),
                const SizedBox(height: 24),
                DropdownButtonFormField<MonitoringProfile>(
                  initialValue: _profile,
                  decoration: const InputDecoration(
                      labelText: 'Perfil de monitoramento'),
                  items: [
                    for (final profile in MonitoringProfile.values
                        .where((item) => item != MonitoringProfile.custom))
                      DropdownMenuItem(
                        value: profile,
                        child: Text(profile.label),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => _profile = value ?? _profile),
                ),
                const SizedBox(height: 30),
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Começar'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(appPreferencesProvider.notifier).update(
            currency: _currency,
            monitoringProfile: _profile,
          );
      await ref.read(appPreferencesProvider.notifier).completeOnboarding();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível salvar: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _skip() =>
      ref.read(appPreferencesProvider.notifier).completeOnboarding();
}
