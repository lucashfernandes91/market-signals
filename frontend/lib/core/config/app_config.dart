class AppConfig {
  const AppConfig._();

  static const _isRelease = bool.fromEnvironment('dart.vm.product');
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL',
      defaultValue:
          _isRelease ? 'https://api.example.invalid' : 'http://127.0.0.1:8001');
  static const websocketBaseUrl = String.fromEnvironment('WS_BASE_URL',
      defaultValue:
          _isRelease ? 'wss://api.example.invalid' : 'ws://127.0.0.1:8001');
}
