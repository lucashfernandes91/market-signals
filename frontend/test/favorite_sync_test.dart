import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:market_radar/core/network/api_client.dart';
import 'package:market_radar/core/storage/token_storage.dart';
import 'package:market_radar/features/favorites/data/favorite_store.dart';

void main() {
  test('sincronização cria lista padrão e envia favoritos ausentes', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final requests = <String>[];
    final client = MockClient((request) async {
      requests.add('${request.method} ${request.url.path}');
      if (request.method == 'GET') return http.Response('[]', 200);
      if (request.url.path == '/api/v1/watchlists/') {
        return http.Response(
          jsonEncode({
            'id': 'list-1',
            'name': 'Favoritos',
            'is_default': true,
            'items': [],
          }),
          201,
        );
      }
      return http.Response('{}', 201);
    });
    final api = ApiClient(
      client: client,
      tokenStorage: TokenStorage(const FlutterSecureStorage()),
    );

    final result = await FavoriteSyncService(api).sync({'btc', 'eth'});

    expect(result.marketIds, {'btc', 'eth'});
    expect(result.uploaded, 2);
    expect(requests.first, 'GET /api/v1/watchlists/');
    expect(requests, contains('POST /api/v1/watchlists/'));
    expect(
      requests
          .where((item) => item == 'POST /api/v1/watchlists/list-1/items/')
          .length,
      2,
    );
  });
}
