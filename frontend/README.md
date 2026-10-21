# Market Radar Flutter

## Desenvolvimento

Com Flutter instalado:

```powershell
flutter pub get
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8001 --dart-define=WS_BASE_URL=ws://127.0.0.1:8001
```

No emulador Android, use o endereço especial do host:

```powershell
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8001 --dart-define=WS_BASE_URL=ws://10.0.2.2:8001
```

Para gerar o APK de desenvolvimento do emulador:

```powershell
flutter build apk --debug --dart-define=API_BASE_URL=http://10.0.2.2:8001 --dart-define=WS_BASE_URL=ws://10.0.2.2:8001
```

O cliente usa Riverpod, JWT em armazenamento seguro, renovação automática do access token e WebSocket para cotações. Mercado, detalhe, Radar e favoritos locais funcionam sem cadastro. A conta é solicitada somente para sincronizar favoritos, administrar watchlists ou criar alertas.

O catálogo possui busca e paginação no backend. Preços e candles são convertidos com taxas ao vivo para BRL ou USD. O Radar recebe métricas agregadas de 24 horas e pode ser filtrado por favoritos locais ou watchlist sincronizada. O Perfil permite configurar moeda, tema e perfil de monitoramento.

Para habilitar push real, configure o projeto nativo com `flutterfire configure`, adicione os arquivos do Firebase e execute o app em um dispositivo ou emulador com Google Play Services. O token FCM é registrado em `/api/v1/devices/{device_id}/` depois da autenticação.

No Android 13 ou superior, o app solicita a permissão de notificações depois da autenticação. Sem os arquivos nativos do Firebase, o app continua funcionando com REST e WebSocket, mas não registra token FCM.
