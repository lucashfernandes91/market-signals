import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/api_client.dart';
import '../session/session_controller.dart';
import '../storage/token_storage.dart';

const _firebaseOperationTimeout = Duration(seconds: 10);
const _firebaseInitializationTimeout = Duration(seconds: 12);

@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp().timeout(_firebaseOperationTimeout);
  } catch (_) {}
}

enum PushInitResult { ready, denied, unavailable }

final pushNotificationServiceProvider =
    Provider<PushNotificationService>((ref) {
  final service = PushNotificationService(
    ref.watch(apiClientProvider),
    tokenStorage: ref.watch(tokenStorageProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

class PushNotificationService {
  PushNotificationService(
    this._api, {
    TokenStorage? tokenStorage,
  }) : _tokens = tokenStorage ?? TokenStorage();

  final ApiClient _api;
  final TokenStorage _tokens;
  final _openedMessages = StreamController<RemoteMessage>.broadcast();
  final _foregroundMessages = StreamController<RemoteMessage>.broadcast();
  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  bool _firebaseReady = false;
  bool _listenersAttached = false;
  bool _initialMessageHandled = false;
  Future<PushInitResult>? _initialization;

  Stream<RemoteMessage> get openedMessages => _openedMessages.stream;
  Stream<RemoteMessage> get foregroundMessages => _foregroundMessages.stream;

  Future<PushInitResult> initialize() {
    final activeInitialization = _initialization;
    if (activeInitialization != null) return activeInitialization;

    final initialization = _initialize().timeout(
      _firebaseInitializationTimeout,
      onTimeout: () => PushInitResult.unavailable,
    );
    _initialization = initialization;
    initialization.whenComplete(() {
      if (identical(_initialization, initialization)) {
        _initialization = null;
      }
    });
    return initialization;
  }

  Future<PushInitResult> _initialize() async {
    try {
      if (!_firebaseReady) {
        await Firebase.initializeApp().timeout(_firebaseOperationTimeout);
        _firebaseReady = true;
      }
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging
          .requestPermission(
            alert: true,
            badge: true,
            sound: true,
          )
          .timeout(_firebaseOperationTimeout);
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return PushInitResult.denied;
      }
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
      final token =
          await messaging.getToken().timeout(_firebaseOperationTimeout);
      if (token != null) await _register(token);
      _attachListeners(messaging);
      if (!_initialMessageHandled) {
        _initialMessageHandled = true;
        final initialMessage = await messaging
            .getInitialMessage()
            .timeout(_firebaseOperationTimeout);
        if (initialMessage != null) await open(initialMessage);
      }
      return PushInitResult.ready;
    } catch (_) {
      return PushInitResult.unavailable;
    }
  }

  void _attachListeners(FirebaseMessaging messaging) {
    if (_listenersAttached) return;
    _listenersAttached = true;
    _tokenSubscription = messaging.onTokenRefresh.listen((token) async {
      try {
        await _register(token);
      } catch (_) {}
    });
    _openedSubscription = FirebaseMessaging.onMessageOpenedApp.listen(open);
    _foregroundSubscription =
        FirebaseMessaging.onMessage.listen(_foregroundMessages.add);
  }

  Future<void> open(RemoteMessage message) async {
    final notificationId = message.data['notification_id']?.toString();
    if (notificationId != null) {
      try {
        await _api.post('/notifications/$notificationId/opened/');
      } catch (_) {}
    }
    _openedMessages.add(message);
  }

  Future<void> unregister() async {
    final platform = _platform;
    final deviceId = 'fcm:$platform:${await _tokens.deviceId()}';
    try {
      await _api.delete('/devices/${Uri.encodeComponent(deviceId)}/');
    } catch (_) {}
  }

  Future<void> _register(String token) async {
    final platform = _platform;
    final deviceId = 'fcm:$platform:${await _tokens.deviceId()}';
    await _api.put('/devices/${Uri.encodeComponent(deviceId)}/', {
      'platform': platform,
      'provider': 'fcm',
      'token': token,
      'enabled': true,
    });
  }

  String get _platform => Platform.isIOS
      ? 'ios'
      : Platform.isAndroid
          ? 'android'
          : 'web';

  void dispose() {
    _tokenSubscription?.cancel();
    _openedSubscription?.cancel();
    _foregroundSubscription?.cancel();
    _openedMessages.close();
    _foregroundMessages.close();
  }
}
