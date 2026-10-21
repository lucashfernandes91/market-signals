import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../storage/token_storage.dart';

class ApiException implements Exception {
  const ApiException(this.statusCode, this.message);
  final int statusCode;
  final String message;
  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({TokenStorage? tokenStorage, http.Client? client})
      : _tokens = tokenStorage ?? TokenStorage(),
        _client = client ?? http.Client();
  final TokenStorage _tokens;
  final http.Client _client;
  Future<bool>? _refreshInFlight;
  static const _requestTimeout = Duration(seconds: 10);

  Future<dynamic> get(String path) async =>
      _decode(await _request('GET', path));
  Future<dynamic> post(String path, [Map<String, dynamic>? body]) async =>
      _decode(await _request('POST', path, body: body));
  Future<dynamic> patch(String path, [Map<String, dynamic>? body]) async =>
      _decode(await _request('PATCH', path, body: body));
  Future<dynamic> put(String path, [Map<String, dynamic>? body]) async =>
      _decode(await _request('PUT', path, body: body));
  Future<void> delete(String path) async {
    final response = await _request('DELETE', path);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _exception(response);
    }
  }

  Future<http.Response> _request(String method, String path,
      {Map<String, dynamic>? body, bool retry = true}) async {
    final access = await _tokens.readAccessToken();
    final headers = <String, String>{'Accept': 'application/json'};
    if (body != null) {
      headers['Content-Type'] = 'application/json';
    }
    if (access != null) {
      headers['Authorization'] = 'Bearer $access';
    }
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/api/v1$path');
    final encoded = body == null ? null : jsonEncode(body);
    final response = await _withTimeout(switch (method) {
      'POST' => _client.post(uri, headers: headers, body: encoded),
      'PUT' => _client.put(uri, headers: headers, body: encoded),
      'PATCH' => _client.patch(uri, headers: headers, body: encoded),
      'DELETE' => _client.delete(uri, headers: headers),
      _ => _client.get(uri, headers: headers),
    });
    if (response.statusCode == 401 && retry) {
      final currentAccess = await _tokens.readAccessToken();
      final sessionRecovered = currentAccess != null && currentAccess != access
          ? true
          : await _refresh();
      if (sessionRecovered) {
        return _request(method, path, body: body, retry: false);
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _exception(response);
    }
    return response;
  }

  Future<bool> _refresh() {
    final activeRefresh = _refreshInFlight;
    if (activeRefresh != null) return activeRefresh;

    final operation = _performRefresh();
    _refreshInFlight = operation;
    return operation.whenComplete(() {
      if (identical(_refreshInFlight, operation)) {
        _refreshInFlight = null;
      }
    });
  }

  Future<bool> _performRefresh() async {
    final refresh = await _tokens.readRefreshToken();
    if (refresh == null) return false;
    final response = await _withTimeout(_client.post(
        Uri.parse('${AppConfig.apiBaseUrl}/api/v1/auth/token/refresh/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh': refresh})));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await _tokens.clear();
      return false;
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    await _tokens.saveTokens(
        access: data['access'] as String,
        refresh: (data['refresh'] as String?) ?? refresh);
    return true;
  }

  Future<bool> refreshAccessToken() => _refresh();

  Future<http.Response> _withTimeout(Future<http.Response> request) =>
      request.timeout(_requestTimeout,
          onTimeout: () => throw const ApiException(
              0, 'A API demorou para responder. Tente novamente.'));

  dynamic _decode(http.Response response) =>
      response.body.isEmpty ? null : jsonDecode(response.body);

  ApiException _exception(http.Response response) {
    try {
      final data = jsonDecode(response.body);
      return ApiException(response.statusCode, _errorMessage(data));
    } catch (_) {
      return ApiException(
          response.statusCode, 'Erro na API (${response.statusCode}).');
    }
  }

  String _errorMessage(dynamic data) {
    if (data is Map<String, dynamic>) {
      final error = data['error'];
      if (error is Map<String, dynamic>) {
        final details = _validationMessage(error['details']);
        if (details != null) return details;

        final message = error['message'];
        if (message != null) return message.toString();
      }

      final detail = data['detail'];
      if (detail != null) return detail.toString();

      final details = _validationMessage(data);
      if (details != null) return details;
    }
    if (data is List && data.isNotEmpty) return data.join('\n');
    return 'Erro na API.';
  }

  String? _validationMessage(dynamic data) {
    if (data is Map<String, dynamic>) {
      final messages = data.entries
          .map((entry) {
            final value = entry.value;
            final message = value is List ? value.join(' ') : value.toString();
            return '${_fieldLabel(entry.key)}: $message';
          })
          .where((message) => !message.endsWith(': '))
          .toList();
      if (messages.isNotEmpty) return messages.join('\n');
    }
    return null;
  }

  String _fieldLabel(String field) => switch (field) {
        'email' => 'E-mail',
        'password' => 'Senha',
        _ => field,
      };
}
