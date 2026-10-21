import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../network/api_client.dart';
import '../storage/token_storage.dart';

final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());
final apiClientProvider = Provider<ApiClient>(
    (ref) => ApiClient(tokenStorage: ref.watch(tokenStorageProvider)));
final authRepositoryProvider = Provider<AuthRepository>((ref) => AuthRepository(
    ref.watch(apiClientProvider), ref.watch(tokenStorageProvider)));
final sessionControllerProvider =
    StateNotifierProvider<SessionController, SessionState>((ref) =>
        SessionController(ref.watch(authRepositoryProvider),
            ref.watch(tokenStorageProvider)));

class SessionState {
  const SessionState(
      {this.isLoading = true, this.isAuthenticated = false, this.error});
  final bool isLoading;
  final bool isAuthenticated;
  final String? error;
}

class AuthRepository {
  const AuthRepository(this._api, this._tokens);
  final ApiClient _api;
  final TokenStorage _tokens;

  Future<bool> restoreSession() => _api.refreshAccessToken();

  Future<void> startPersonalSession() async {
    await _tokens.clear();
    final data =
        await _api.post('/auth/personal-session/') as Map<String, dynamic>;
    await _tokens.saveTokens(
      access: data['access'] as String,
      refresh: data['refresh'] as String,
      accountId: data['account_id'].toString(),
    );
  }

  Future<void> login(String email, String password) async {
    final data =
        await _api.post('/auth/token/', {'email': email, 'password': password})
            as Map<String, dynamic>;
    await _tokens.saveTokens(
      access: data['access'] as String,
      refresh: data['refresh'] as String,
      accountId: email,
    );
  }

  Future<void> register(String email, String password) async {
    await _api.post('/auth/register/', {
      'email': email,
      'password': password,
      'first_name': '',
      'last_name': ''
    });
    await login(email, password);
  }
}

class SessionController extends StateNotifier<SessionState> {
  SessionController(this._auth, this._tokens) : super(const SessionState()) {
    _restore();
  }
  final AuthRepository _auth;
  final TokenStorage _tokens;

  Future<void> _restore() async {
    final hasToken = await _tokens.readAccessToken() != null;
    if (hasToken && await _auth.restoreSession()) {
      state = const SessionState(isLoading: false, isAuthenticated: true);
      return;
    }
    // Preserva login/cadastro; sem token válido, inicia a sessão pessoal temporária.
    await _startPersonalSession();
  }

  Future<void> _startPersonalSession() async {
    try {
      await _auth.startPersonalSession();
      state = const SessionState(isLoading: false, isAuthenticated: true);
    } catch (_) {
      state = const SessionState(isLoading: false);
    }
  }

  Future<void> login(String email, String password) async {
    state = const SessionState(isLoading: true);
    try {
      await _auth.login(email, password);
      state = const SessionState(isLoading: false, isAuthenticated: true);
    } catch (error) {
      state = SessionState(isLoading: false, error: error.toString());
    }
  }

  Future<void> register(String email, String password) async {
    state = const SessionState(isLoading: true);
    try {
      await _auth.register(email, password);
      state = const SessionState(isLoading: false, isAuthenticated: true);
    } catch (error) {
      state = SessionState(isLoading: false, error: error.toString());
    }
  }

  Future<void> logout() async {
    await _tokens.clear();
    state = const SessionState(isLoading: true);
    await _startPersonalSession();
  }

  void clearError() {
    if (state.error != null) {
      state = SessionState(
        isLoading: state.isLoading,
        isAuthenticated: state.isAuthenticated,
      );
    }
  }
}
