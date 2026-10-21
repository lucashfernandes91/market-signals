import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/navigation/app_navigator.dart';
import 'core/notifications/push_coordinator.dart';
import 'core/preferences/app_preferences.dart';
import 'core/session/session_controller.dart';
import 'core/theme/app_theme.dart';
import 'features/market/models/market.dart';
import 'features/market/presentation/asset_screen.dart';
import 'features/market/presentation/market_screen.dart';
import 'features/alerts/presentation/alerts_screen.dart';
import 'features/onboarding/presentation/onboarding_screen.dart';
import 'features/profile/presentation/profile_screen.dart';
import 'features/radar/presentation/radar_screen.dart';

class MarketRadarApp extends ConsumerWidget {
  const MarketRadarApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(sessionControllerProvider);
    final preferences = ref.watch(appPreferencesProvider).valueOrNull;
    return MaterialApp(
      title: 'Market Radar',
      debugShowCheckedModeBanner: false,
      navigatorKey: appNavigatorKey,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: preferences?.theme.mode ?? ThemeMode.system,
      home: const OnboardingGate(
        child: PushCoordinator(child: _HomeShell()),
      ),
      onGenerateRoute: (settings) {
        if (settings.name == '/asset' && settings.arguments is Market) {
          return MaterialPageRoute(
            builder: (_) => AssetScreen(market: settings.arguments! as Market),
          );
        }
        return null;
      },
    );
  }
}

class _HomeShell extends StatefulWidget {
  const _HomeShell();

  @override
  State<_HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<_HomeShell> {
  var _index = 0;

  final _screens = <Widget?>[
    const MarketScreen(),
    null,
    null,
    null,
  ];

  Widget _screen(int index) => switch (index) {
        0 => const MarketScreen(),
        1 => const AlertsScreen(),
        2 => const RadarScreen(),
        _ => const ProfileScreen(),
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
          child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: IndexedStack(
          index: _index,
          children: [
            for (final screen in _screens) screen ?? const SizedBox.shrink(),
          ],
        ),
      )),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() {
          _index = value;
          _screens[value] ??= _screen(value);
        }),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.show_chart), label: 'Mercado'),
          NavigationDestination(
              icon: Icon(Icons.notifications_none_rounded),
              selectedIcon: Icon(Icons.notifications_active_rounded),
              label: 'Alertas'),
          NavigationDestination(icon: Icon(Icons.radar), label: 'Radar'),
          NavigationDestination(
              icon: Icon(Icons.account_circle_outlined),
              selectedIcon: Icon(Icons.account_circle_rounded),
              label: 'Perfil'),
        ],
      ),
    );
  }
}
