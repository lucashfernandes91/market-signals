import 'dart:async';
import 'dart:developer' as developer;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/market/data/market_providers.dart';
import '../../features/market/presentation/asset_screen.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../navigation/app_navigator.dart';
import '../session/session_controller.dart';
import 'push_notification_service.dart';

enum PushStatus { idle, initializing, ready, denied, unavailable }

const _pushInitializationTimeout = Duration(seconds: 15);

final pushStatusProvider = StateProvider<PushStatus>((ref) => PushStatus.idle);

class PushCoordinator extends ConsumerStatefulWidget {
  const PushCoordinator({required this.child, super.key});
  final Widget child;

  @override
  ConsumerState<PushCoordinator> createState() => _PushCoordinatorState();
}

class _PushCoordinatorState extends ConsumerState<PushCoordinator> {
  StreamSubscription<RemoteMessage>? _openedSubscription;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  ProviderSubscription<SessionState>? _sessionSubscription;

  @override
  void initState() {
    super.initState();
    final service = ref.read(pushNotificationServiceProvider);
    _openedSubscription = service.openedMessages.listen(_navigateFromMessage);
    _foregroundSubscription =
        service.foregroundMessages.listen(_showForegroundMessage);
    _sessionSubscription = ref.listenManual<SessionState>(
      sessionControllerProvider,
      (_, session) {
        if (session.isAuthenticated) Future<void>(_initialize);
      },
      fireImmediately: true,
    );
  }

  Future<void> _initialize() async {
    if (ref.read(pushStatusProvider) == PushStatus.initializing) return;
    ref.read(pushStatusProvider.notifier).state = PushStatus.initializing;
    final timeout = Timer(_pushInitializationTimeout, () {
      if (!mounted || ref.read(pushStatusProvider) != PushStatus.initializing) {
        return;
      }
      ref.read(pushStatusProvider.notifier).state = PushStatus.unavailable;
    });
    final result = await ref.read(pushNotificationServiceProvider).initialize();
    timeout.cancel();
    if (!mounted) return;
    ref.read(pushStatusProvider.notifier).state = switch (result) {
      PushInitResult.ready => PushStatus.ready,
      PushInitResult.denied => PushStatus.denied,
      PushInitResult.unavailable => PushStatus.unavailable,
    };
  }

  void _showForegroundMessage(RemoteMessage message) {
    if (!mounted) return;
    ref.invalidate(notificationsProvider);
    final title = message.notification?.title ?? 'Novo alerta';
    final body = message.notification?.body ?? 'Uma condição foi atingida.';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(body),
          ],
        ),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: 'Abrir',
          onPressed: () =>
              ref.read(pushNotificationServiceProvider).open(message),
        ),
      ));
  }

  Future<void> _navigateFromMessage(RemoteMessage message) async {
    ref.invalidate(notificationsProvider);
    final navigator = appNavigatorKey.currentState;
    if (navigator == null) return;
    final marketId = message.data['market_id']?.toString();
    if (marketId != null) {
      try {
        final markets =
            await ref.read(marketRepositoryProvider).lookup([marketId]);
        final market = markets.isEmpty ? null : markets.first;
        if (market != null) {
          await navigator.push(MaterialPageRoute(
            builder: (_) => AssetScreen(market: market),
          ));
          return;
        }
      } catch (_) {
        developer.log('Notification destination could not be opened.',
            name: 'notifications.navigation');
      }
    }
    await navigator.push(MaterialPageRoute(
      builder: (_) => const NotificationsScreen(),
    ));
  }

  @override
  void dispose() {
    _openedSubscription?.cancel();
    _foregroundSubscription?.cancel();
    _sessionSubscription?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
