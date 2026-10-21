import '../../../core/network/api_client.dart';
import '../models/market.dart';

final class MarketRepository {
  const MarketRepository(this._api);
  final ApiClient _api;

  Future<List<Market>> list({String search = ''}) async {
    final markets = <Market>[];
    var page = 1;
    while (true) {
      final query = Uri(queryParameters: {
        'page': '$page',
        'page_size': '100',
        if (search.trim().isNotEmpty) 'search': search.trim(),
      }).query;
      final raw = await _api.get('/markets/?$query');
      if (raw is List) {
        markets.addAll(
            raw.map((item) => Market.fromJson(item as Map<String, dynamic>)));
        break;
      }
      final data = raw as Map<String, dynamic>;
      final results = data['results'] as List<dynamic>? ?? const [];
      markets.addAll(
          results.map((item) => Market.fromJson(item as Map<String, dynamic>)));
      if (data['next'] == null) break;
      page++;
    }
    return markets;
  }

  Future<Map<String, dynamic>> quote(String id) async =>
      await _api.get('/markets/$id/quote/') as Map<String, dynamic>;

  Future<List<Market>> lookup(Iterable<String> ids) async {
    final values = ids.toSet().toList(growable: false);
    if (values.isEmpty) return [];
    final query = Uri(queryParameters: {'ids': values.join(',')}).query;
    final raw = await _api.get('/markets/lookup/?$query') as List<dynamic>;
    return raw
        .map((item) => Market.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<Market>> overview(Iterable<String> ids) async {
    final values = ids.toSet().toList(growable: false);
    if (values.isEmpty) return [];
    final query = Uri(queryParameters: {'ids': values.join(',')}).query;
    final raw = await _api.get('/markets/overview/?$query') as List<dynamic>;
    return raw
        .map((item) => Market.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<Map<String, dynamic>>> candles(String id,
      {int limit = 24, String interval = '1h'}) async {
    final data =
        await _api.get('/markets/$id/candles/?interval=$interval&limit=$limit')
            as Map<String, dynamic>;
    return (data['candles'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> radar({String scope = 'all'}) async {
    final query = <String, String>{};
    if (scope.startsWith('watchlist:')) {
      query['watchlist_id'] = scope.substring('watchlist:'.length);
    } else if (scope.startsWith('markets:')) {
      query['market_ids'] = scope.substring('markets:'.length);
    }
    final suffix = query.isEmpty ? '' : '?${Uri(queryParameters: query).query}';
    return await _api.get('/markets/radar/$suffix') as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> rates() async =>
      await _api.get('/markets/rates/') as Map<String, dynamic>;
}
