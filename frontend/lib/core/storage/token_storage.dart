import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStorage {
  TokenStorage([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  static const _accessKey = 'market_radar.access_token';
  static const _refreshKey = 'market_radar.refresh_token';
  static const _accountKey = 'market_radar.account_id';
  static const _deviceIdKey = 'market_radar.device_id';
  final FlutterSecureStorage _storage;

  Future<String?> readAccessToken() => _storage.read(key: _accessKey);
  Future<String?> readRefreshToken() => _storage.read(key: _refreshKey);
  Future<bool> onboardingDone() async {
    final accountId = await _storage.read(key: _accountKey);
    if (accountId == null) return false;
    return (await _storage.read(key: _onboardingKey(accountId))) == 'true';
  }

  Future<void> markOnboardingDone() async {
    final accountId = await _storage.read(key: _accountKey);
    if (accountId != null) {
      await _storage.write(key: _onboardingKey(accountId), value: 'true');
    }
  }

  Future<String> deviceId() async {
    final current = await _storage.read(key: _deviceIdKey);
    if (current != null) return current;
    final random = Random.secure();
    final value =
        List.generate(32, (_) => random.nextInt(16).toRadixString(16)).join();
    await _storage.write(key: _deviceIdKey, value: value);
    return value;
  }

  Future<void> saveTokens({
    required String access,
    required String refresh,
    String? accountId,
  }) async {
    await Future.wait([
      _storage.write(key: _accessKey, value: access),
      _storage.write(key: _refreshKey, value: refresh),
      if (accountId != null)
        _storage.write(key: _accountKey, value: accountId.toLowerCase()),
    ]);
  }

  Future<void> clear() async {
    await Future.wait([
      _storage.delete(key: _accessKey),
      _storage.delete(key: _refreshKey),
      _storage.delete(key: _accountKey),
    ]);
  }

  String _onboardingKey(String accountId) =>
      'market_radar.onboarding_done.$accountId';
}
