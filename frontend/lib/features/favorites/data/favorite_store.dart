import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/network/api_client.dart';
import '../../../core/session/session_controller.dart';

abstract interface class FavoriteStore {
  Future<Set<String>> read();
  Future<void> write(Set<String> marketIds);
}

class SecureFavoriteStore implements FavoriteStore {
  SecureFavoriteStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'market_radar.local_favorites';
  final FlutterSecureStorage _storage;

  @override
  Future<Set<String>> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return <String>{};
    final decoded = jsonDecode(raw);
    return decoded is List
        ? decoded.map((item) => item.toString()).toSet()
        : <String>{};
  }

  @override
  Future<void> write(Set<String> marketIds) => _storage.write(
        key: _key,
        value: jsonEncode(marketIds.toList()..sort()),
      );
}

class MemoryFavoriteStore implements FavoriteStore {
  MemoryFavoriteStore([Set<String>? initial]) : _items = {...?initial};
  Set<String> _items;

  @override
  Future<Set<String>> read() async => Set.of(_items);

  @override
  Future<void> write(Set<String> marketIds) async {
    _items = Set.of(marketIds);
  }
}

final favoriteStoreProvider =
    Provider<FavoriteStore>((ref) => SecureFavoriteStore());

final favoriteIdsProvider =
    StateNotifierProvider<FavoriteController, AsyncValue<Set<String>>>((ref) {
  return FavoriteController(ref.watch(favoriteStoreProvider));
});

class FavoriteController extends StateNotifier<AsyncValue<Set<String>>> {
  FavoriteController(this._store) : super(const AsyncLoading()) {
    _load();
  }

  final FavoriteStore _store;

  Future<void> _load() async {
    state = await AsyncValue.guard(_store.read);
  }

  Future<void> toggle(String marketId) async {
    final previous = Set<String>.of(state.valueOrNull ?? <String>{});
    final next = Set<String>.of(previous);
    next.contains(marketId) ? next.remove(marketId) : next.add(marketId);
    state = AsyncData(next);
    try {
      await _store.write(next);
    } catch (error, trace) {
      state = AsyncData(previous);
      Error.throwWithStackTrace(error, trace);
    }
  }

  Future<void> replace(Set<String> marketIds) async {
    final next = Set<String>.of(marketIds);
    await _store.write(next);
    state = AsyncData(next);
  }
}

class FavoriteSyncResult {
  const FavoriteSyncResult({required this.marketIds, required this.uploaded});
  final Set<String> marketIds;
  int get localCount => marketIds.length;
  final int uploaded;
}

class FavoriteSyncService {
  const FavoriteSyncService(this._api);
  final ApiClient _api;

  Future<FavoriteSyncResult> sync(Set<String> local) async {
    final raw = await _api.get('/watchlists/');
    final lists = (raw is List
            ? raw
            : (raw as Map<String, dynamic>)['results'] as List<dynamic>? ??
                const [])
        .cast<Map<String, dynamic>>();
    Map<String, dynamic>? target;
    for (final list in lists) {
      if (list['is_default'] == true) {
        target = list;
        break;
      }
    }
    target ??= await _api.post('/watchlists/', {
      'name': 'Favoritos',
      'is_default': true,
    }) as Map<String, dynamic>;
    final entries = (target['items'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    final remote = entries
        .map((entry) => (entry['market'] as Map<String, dynamic>?)?['id'])
        .whereType<String>()
        .toSet();
    var uploaded = 0;
    for (final marketId in local.difference(remote)) {
      await _api.post('/watchlists/${target['id']}/items/', {
        'market_id': marketId,
        'position': remote.length + uploaded,
      });
      uploaded++;
    }
    return FavoriteSyncResult(
      marketIds: {...local, ...remote},
      uploaded: uploaded,
    );
  }
}

final favoriteSyncServiceProvider = Provider<FavoriteSyncService>(
  (ref) => FavoriteSyncService(ref.watch(apiClientProvider)),
);

Future<FavoriteSyncResult> syncFavorites(WidgetRef ref) async {
  final local =
      Set<String>.of(ref.read(favoriteIdsProvider).valueOrNull ?? <String>{});
  final result = await ref.read(favoriteSyncServiceProvider).sync(local);
  await ref.read(favoriteIdsProvider.notifier).replace(result.marketIds);
  return result;
}
