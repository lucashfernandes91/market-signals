import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../network/api_client.dart';
import '../session/session_controller.dart';

enum DisplayCurrency {
  brl('BRL'),
  usd('USD');

  const DisplayCurrency(this.code);
  final String code;

  static DisplayCurrency parse(Object? value) => values.firstWhere(
        (item) => item.code == value,
        orElse: () => brl,
      );
}

enum ThemePreference {
  system('system'),
  light('light'),
  dark('dark');

  const ThemePreference(this.value);
  final String value;

  static ThemePreference parse(Object? value) => values.firstWhere(
        (item) => item.value == value,
        orElse: () => system,
      );

  ThemeMode get mode => switch (this) {
        system => ThemeMode.system,
        light => ThemeMode.light,
        dark => ThemeMode.dark,
      };
}

enum MonitoringProfile {
  conservative('conservative', 'Conservador'),
  trader('trader', 'Trader'),
  highVolatility('high_volatility', 'Alta volatilidade'),
  longTerm('long_term', 'Longo prazo'),
  custom('custom', 'Personalizado');

  const MonitoringProfile(this.value, this.label);
  final String value;
  final String label;

  static MonitoringProfile parse(Object? value) => values.firstWhere(
        (item) => item.value == value,
        orElse: () => conservative,
      );
}

enum MarketLayout {
  grid('grid'),
  list('list');

  const MarketLayout(this.value);
  final String value;

  static MarketLayout parse(Object? value) => values.firstWhere(
        (item) => item.value == value,
        orElse: () => grid,
      );
}

class AppPreferences {
  const AppPreferences({
    this.currency = DisplayCurrency.brl,
    this.theme = ThemePreference.system,
    this.monitoringProfile = MonitoringProfile.conservative,
    this.marketLayout = MarketLayout.grid,
    this.onboardingComplete = false,
  });

  final DisplayCurrency currency;
  final ThemePreference theme;
  final MonitoringProfile monitoringProfile;
  final MarketLayout marketLayout;
  final bool onboardingComplete;

  AppPreferences copyWith({
    DisplayCurrency? currency,
    ThemePreference? theme,
    MonitoringProfile? monitoringProfile,
    MarketLayout? marketLayout,
    bool? onboardingComplete,
  }) =>
      AppPreferences(
        currency: currency ?? this.currency,
        theme: theme ?? this.theme,
        monitoringProfile: monitoringProfile ?? this.monitoringProfile,
        marketLayout: marketLayout ?? this.marketLayout,
        onboardingComplete: onboardingComplete ?? this.onboardingComplete,
      );

  Map<String, dynamic> toJson() => {
        'fiat_currency': currency.code,
        'theme': theme.value,
        'monitoring_profile': monitoringProfile.value,
        'market_layout': marketLayout.value,
        'onboarding_complete': onboardingComplete,
      };

  factory AppPreferences.fromJson(Map<String, dynamic> json) => AppPreferences(
        currency: DisplayCurrency.parse(json['fiat_currency']),
        theme: ThemePreference.parse(json['theme']),
        monitoringProfile: MonitoringProfile.parse(json['monitoring_profile']),
        marketLayout: MarketLayout.parse(json['market_layout']),
        onboardingComplete: json['onboarding_complete'] == true,
      );
}

abstract interface class PreferenceStore {
  Future<AppPreferences> read();
  Future<void> write(AppPreferences preferences);
}

class SecurePreferenceStore implements PreferenceStore {
  SecurePreferenceStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'market_radar.preferences';
  final FlutterSecureStorage _storage;

  @override
  Future<AppPreferences> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return const AppPreferences();
    return AppPreferences.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  @override
  Future<void> write(AppPreferences preferences) => _storage.write(
        key: _key,
        value: jsonEncode(preferences.toJson()),
      );
}

class MemoryPreferenceStore implements PreferenceStore {
  MemoryPreferenceStore([AppPreferences? initial])
      : _preferences =
            initial ?? const AppPreferences(onboardingComplete: true);

  AppPreferences _preferences;

  @override
  Future<AppPreferences> read() async => _preferences;

  @override
  Future<void> write(AppPreferences preferences) async {
    _preferences = preferences;
  }
}

final preferenceStoreProvider = Provider<PreferenceStore>(
  (ref) => SecurePreferenceStore(),
);

final appPreferencesProvider =
    StateNotifierProvider<AppPreferencesController, AsyncValue<AppPreferences>>(
        (ref) {
  final authenticated = ref.watch(
    sessionControllerProvider.select((session) => session.isAuthenticated),
  );
  return AppPreferencesController(
    ref.watch(preferenceStoreProvider),
    ref.watch(apiClientProvider),
    authenticated: authenticated,
  );
});

class AppPreferencesController
    extends StateNotifier<AsyncValue<AppPreferences>> {
  AppPreferencesController(
    this._store,
    this._api, {
    required this.authenticated,
  }) : super(const AsyncLoading()) {
    _load();
  }

  final PreferenceStore _store;
  final ApiClient _api;
  final bool authenticated;

  Future<void> _load() async {
    var preferences = await _store.read();
    if (authenticated) {
      try {
        final remote =
            await _api.get('/auth/me/preferences/') as Map<String, dynamic>;
        preferences = AppPreferences.fromJson({
          ...remote,
          'market_layout': preferences.marketLayout.value,
          'onboarding_complete': preferences.onboardingComplete,
        });
        await _store.write(preferences);
      } catch (_) {}
    }
    state = AsyncData(preferences);
  }

  Future<void> update({
    DisplayCurrency? currency,
    ThemePreference? theme,
    MonitoringProfile? monitoringProfile,
    MarketLayout? marketLayout,
  }) async {
    final current = state.valueOrNull ?? await _store.read();
    final next = current.copyWith(
      currency: currency,
      theme: theme,
      monitoringProfile: monitoringProfile,
      marketLayout: marketLayout,
    );
    state = AsyncData(next);
    await _store.write(next);
    if (authenticated &&
        (currency != null || theme != null || monitoringProfile != null)) {
      await _api.patch('/auth/me/preferences/', {
        'fiat_currency': next.currency.code,
        'theme': next.theme.value,
        'monitoring_profile': next.monitoringProfile.value,
        'timezone': 'America/Sao_Paulo',
      });
    }
  }

  Future<void> completeOnboarding() async {
    final current = state.valueOrNull ?? await _store.read();
    final next = current.copyWith(onboardingComplete: true);
    state = AsyncData(next);
    await _store.write(next);
  }
}
