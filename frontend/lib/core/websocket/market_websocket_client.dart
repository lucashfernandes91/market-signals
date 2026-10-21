import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/app_config.dart';
import '../storage/token_storage.dart';

enum MarketConnectionStatus { connecting, live, degraded, offline }

class MarketWebSocketClient {
  MarketWebSocketClient({
    TokenStorage? tokenStorage,
    WebSocketChannel Function(Uri uri)? connect,
    Future<bool> Function()? refreshToken,
  })  : _tokens = tokenStorage ?? TokenStorage(),
        _connect = connect ?? WebSocketChannel.connect,
        _refreshToken = refreshToken;

  final TokenStorage _tokens;
  final WebSocketChannel Function(Uri uri) _connect;
  final Future<bool> Function()? _refreshToken;
  final _statusController =
      StreamController<MarketConnectionStatus>.broadcast();

  Stream<MarketConnectionStatus> get status => _statusController.stream;

  Stream<Map<String, dynamic>> quotes(Iterable<String> marketIds) async* {
    final ids = marketIds.toSet().toList(growable: false);
    if (ids.isEmpty) {
      return;
    }

    final lastSequences = <String, String>{};
    var retryDelay = const Duration(milliseconds: 500);
    var refreshAttempted = false;

    while (true) {
      final accessToken = await _tokens.readAccessToken();
      WebSocketChannel? channel;
      _statusController.add(MarketConnectionStatus.connecting);
      try {
        channel =
            _connect(Uri.parse('${AppConfig.websocketBaseUrl}/ws/v1/market/'));
        await channel.ready;
        if (accessToken == null || accessToken.isEmpty) {
          _send(channel, 'market.subscribe', {'market_ids': ids});
        } else {
          _send(channel, 'auth', {'access_token': accessToken});
        }

        var subscribed = accessToken == null || accessToken.isEmpty;
        await for (final message in channel.stream) {
          final envelope = _decode(message);
          if (envelope == null) {
            continue;
          }
          final type = envelope['type'];
          final data = envelope['data'];
          if (type == 'auth.accepted') {
            subscribed = true;
            refreshAttempted = false;
            _send(channel, 'market.subscribe', {'market_ids': ids});
            continue;
          }
          if (!subscribed ||
              (type != 'market.snapshot' && type != 'market.delta')) {
            continue;
          }
          if (data is! Map<String, dynamic>) {
            continue;
          }
          final marketId = data['market_id']?.toString();
          final sequence = data['sequence']?.toString();
          if (marketId == null) {
            continue;
          }
          if (sequence != null &&
              !_isNewer(sequence, lastSequences[marketId])) {
            continue;
          }
          if (sequence != null) {
            lastSequences[marketId] = sequence;
          }
          _statusController.add(MarketConnectionStatus.live);
          yield data;
        }
        _statusController.add(MarketConnectionStatus.degraded);
        retryDelay = const Duration(milliseconds: 500);
      } catch (_) {
        developer.log('Market WebSocket connection failed; retrying.',
            name: 'market.websocket');
        _statusController.add(MarketConnectionStatus.degraded);
      } finally {
        try {
          await channel?.sink.close();
        } catch (_) {}
      }

      if (accessToken != null &&
          accessToken.isNotEmpty &&
          _refreshToken != null &&
          !refreshAttempted) {
        refreshAttempted = true;
        try {
          if (!await _refreshToken()) {
            _statusController.add(MarketConnectionStatus.offline);
            return;
          }
        } catch (_) {
          developer.log('Market WebSocket token refresh failed.',
              name: 'market.websocket');
          _statusController.add(MarketConnectionStatus.offline);
          return;
        }
        retryDelay = const Duration(milliseconds: 500);
        continue;
      }

      await Future<void>.delayed(retryDelay);
      final nextMillis = (retryDelay.inMilliseconds * 2).clamp(500, 8000);
      retryDelay = Duration(milliseconds: nextMillis);
    }
  }

  Future<void> dispose() => _statusController.close();

  void _send(WebSocketChannel channel, String type, Map<String, dynamic> data) {
    channel.sink
        .add(jsonEncode({'v': 1, 'id': _newId(), 'type': type, 'data': data}));
  }

  Map<String, dynamic>? _decode(dynamic message) {
    if (message is! String) {
      return null;
    }
    try {
      final decoded = jsonDecode(message);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  bool _isNewer(String sequence, String? previous) {
    if (previous == null) {
      return true;
    }
    final currentParts = sequence.split('-');
    final previousParts = previous.split('-');
    if (currentParts.length != 2 || previousParts.length != 2) {
      return sequence != previous;
    }
    final currentMs = int.tryParse(currentParts[0]);
    final previousMs = int.tryParse(previousParts[0]);
    final currentOffset = int.tryParse(currentParts[1]);
    final previousOffset = int.tryParse(previousParts[1]);
    if (currentMs == null ||
        previousMs == null ||
        currentOffset == null ||
        previousOffset == null) {
      return sequence != previous;
    }
    return currentMs > previousMs ||
        (currentMs == previousMs && currentOffset > previousOffset);
  }

  String _newId() => DateTime.now().microsecondsSinceEpoch.toString();
}
