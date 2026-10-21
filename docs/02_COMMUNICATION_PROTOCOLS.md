---
title: "02 — Protocolos de Comunicação e Fluxo de Market Data"
project: "Market Radar"
status: ready-for-implementation
version: 1.1
date: 2026-10-14
scope:
  - REST API
  - WebSocket
  - JWT
  - market data
  - alerts
  - notifications
---

# 02 — Protocolos de Comunicação e Fluxo de Market Data

Este documento define o contrato público entre o backend e Flutter, Web e PWA.
Ele complementa a fundação Django, SQLite e Redis já criada.

## 1. Regras gerais

- API REST: /api/v1/.
- WebSocket de mercado: /ws/v1/market/.
- UUIDs são strings canônicas.
- Timestamps usam ISO 8601 em UTC.
- Preços, volumes, percentuais e limites financeiros são strings decimais.
- O cliente nunca avalia alertas; ele apenas cria e consulta regras.
- Valores futuros acrescentam campos. Uma mudança incompatível exige /v2/.
- Toda resposta HTTP inclui X-Request-ID.

### Origem da cotação e catálogo

Nesta versão, Binance é a única fonte ativa. O contrato, porém, expõe a origem
da cotação para que o cliente não dependa de textos ou símbolos fixos de uma
exchange. O backend controla o catálogo; a entrada de um par Binance não exige
atualização do cliente.

| Campo | Significado |
| --- | --- |
| `market_id` | UUID do instrumento canônico, como BTC/USDT |
| `provider_market_id` | UUID da listagem que originou a cotação |
| `provider` | identificador técnico, atualmente `binance` |
| `provider_name` | nome para exibição, atualmente `Binance` |
| `provider_symbol` | símbolo na fonte, como `BTCUSDT` |
| `provider_timestamp` | horário informado pela fonte |
| `received_at` | horário em que o backend recebeu o dado |
| `source_status` | `live`, `stale` ou `unavailable`, sem inferir a origem pelo nome da exchange |

Os campos são aditivos em `/api/v1` e `/ws/v1/market/`. `market_id` continua
compatível com favoritos, alertas, notificações e deep links existentes.

Exemplo de preço:

~~~
{
  "price": "70123.42",
  "volume_24h": "18722399122.00",
  "change_24h_percent": "2.31"
}
~~~

## 2. Autenticação

### REST

Rotas protegidas usam o cabeçalho Authorization com o access token JWT. O
access token expira em 15 minutos. O refresh token expira em 30 dias, é
rotacionado e é enviado somente ao endpoint POST /api/v1/auth/token/refresh/.

O cliente tenta um refresh uma única vez após um 401. Caso falhe, remove a
sessão local e volta ao login.

### WebSocket

O navegador não permite Authorization de forma consistente na abertura de
WebSocket. Por isso, autenticação ocorre como primeira mensagem. O token não é
enviado em query string nem em logs de URL.

~~~
{
  "v": 1,
  "id": "a7e10b01-49dc-4720-b5d3-c3dbfec2b278",
  "type": "auth",
  "data": {
    "access_token": "<jwt>"
  }
}
~~~

O servidor aceita a conexão e aguarda essa mensagem por cinco segundos. Antes
de auth.accepted, somente auth e ping são permitidos.

Resposta:

~~~
{
  "v": 1,
  "id": "a7e10b01-49dc-4720-b5d3-c3dbfec2b278",
  "type": "auth.accepted",
  "data": {
    "user_id": "c727c520-0b7b-48aa-af1d-8e3d992fa2e5",
    "expires_at": "2026-09-30T16:30:00Z"
  }
}
~~~

O token expirado encerra a conexão com 4401. O cliente atualiza o token via
REST e reconecta. A rota atual /ws/market/, baseada em sessão Django, é legada
e será removida após o cliente migrar para /ws/v1/market/.

## 3. Envelope de WebSocket

Todas as mensagens seguem este formato:

~~~
{
  "v": 1,
  "id": "uuid-do-comando-ou-evento",
  "type": "market.delta",
  "data": {}
}
~~~

id é gerado pelo cliente para comandos e pelo servidor para eventos. Mensagens
de erro também incluem o id do comando que falhou quando houver.

## 4. Mercado em tempo real

### Subscrição

Após autenticar, o cliente envia:

~~~
{
  "v": 1,
  "id": "a7e10b01-49dc-4720-b5d3-c3dbfec2b278",
  "type": "market.subscribe",
  "data": {
    "market_ids": [
      "ec365d88-5d98-4cd8-9d95-51c639e0e299"
    ]
  }
}
~~~

Limite inicial: 50 mercados por conexão e 100 por usuário. IDs duplicados são
ignorados.

O servidor retorna um snapshot de cada mercado aceito antes de transmitir
deltas:

~~~
{
  "v": 1,
  "id": "9a0bc4a8-41b8-490b-a4fa-82a10d781d14",
  "type": "market.snapshot",
  "data": {
    "market_id": "ec365d88-5d98-4cd8-9d95-51c639e0e299",
    "provider_market_id": "20d0ac76-52d6-4b5b-93b8-7c3e9517d02c",
    "symbol": "BTC-USDT",
    "provider_symbol": "BTCUSDT",
    "price": "70123.42",
    "volume_24h": "18722399122.00",
    "change_24h_percent": "2.31",
    "provider": "binance",
    "provider_name": "Binance",
    "provider_timestamp": "2026-09-30T16:00:00Z",
    "received_at": "2026-09-30T16:00:00.120Z",
    "sequence": "1790784778878-0",
    "stale": false,
    "source_status": "live"
  }
}
~~~

Depois do snapshot:

~~~
{
  "v": 1,
  "id": "c6d48f30-24f2-4d48-b4e7-6ec7b49644a2",
  "type": "market.subscribed",
  "data": {
    "market_ids": ["ec365d88-5d98-4cd8-9d95-51c639e0e299"]
  }
}
~~~

### Delta

Cada atualização coalescida publica:

~~~
{
  "v": 1,
  "id": "b5700a22-063d-4fa8-b92b-9dcebf3ea6f1",
  "type": "market.delta",
  "data": {
    "market_id": "ec365d88-5d98-4cd8-9d95-51c639e0e299",
    "provider_market_id": "20d0ac76-52d6-4b5b-93b8-7c3e9517d02c",
    "provider": "binance",
    "price": "70125.10",
    "volume_24h": "18722400000.00",
    "change_24h_percent": "2.32",
    "provider_timestamp": "2026-09-30T16:00:01Z",
    "received_at": "2026-09-30T16:00:01.110Z",
    "sequence": "1790784779878-0",
    "stale": false,
    "source_status": "live"
  }
}
~~~

O cliente descarta um delta cuja sequência seja menor ou igual à última
sequência aplicada para aquele mercado.

### Cancelamento

~~~
{
  "v": 1,
  "id": "67a2a432-334a-4893-a6a6-549a25887755",
  "type": "market.unsubscribe",
  "data": {
    "market_ids": ["ec365d88-5d98-4cd8-9d95-51c639e0e299"]
  }
}
~~~

Resposta: market.unsubscribed.

## 5. Consistência, stale data e ressincronização

O ingestor limita a propagação de atualizações a uma vez a cada 250 ms por
mercado. O estado mais recente fica no Redis; o stream registra a sequência
interna usada por workers.

Se a última cotação tiver mais de 15 segundos, o backend publica um
`market.delta` com `stale=true` e `source_status=stale`:

~~~
{
  "v": 1,
  "id": "4e9b8cf4-1052-4b67-bd19-e65b014c4a0a",
  "type": "market.delta",
  "data": {
    "market_id": "ec365d88-5d98-4cd8-9d95-51c639e0e299",
    "timestamp": "2026-09-30T15:59:40Z",
    "stale": "true",
    "source_status": "stale"
  }
}
~~~

Ao reconectar, o cliente autentica novamente e reenvia todas as subscrições.
Snapshots são a fonte de recuperação; o cliente não pede replay de ticks.

Backoff: 1, 2, 4, 8, 16 e no máximo 30 segundos, com jitter de até 500 ms. O
backoff volta a um segundo depois de uma conexão estável por 60 segundos.

Sem uma cotação em cache ou quando candles/taxas não puderem ser obtidos da
fonte, a API REST retorna `503` com `error.code=market_data_unavailable`. O
Radar retorna `200` com listas vazias e `source_status=unavailable`, preservando
seu escopo para o cliente renderizar o estado recuperável. Uma listagem
desativada não é assinada pelo ingestor e não pode ser subscrita em WebSocket.

## 6. Heartbeat e pressão de saída

O servidor envia ping a cada 25 segundos. O cliente responde pong com o mesmo
id em até 10 segundos. Sem resposta, o servidor fecha com 4408.

O servidor mantém no máximo 100 mensagens pendentes por conexão. Ao atingir o
limite, remove deltas antigos do mesmo mercado e preserva a atualização mais
recente. Se ainda não conseguir esvaziar a fila, fecha com 1013; o cliente
reconecta e recebe snapshots.

## 7. Erros

REST usa:

~~~
{
  "error": {
    "code": "ALERT_NOT_FOUND",
    "message": "Alerta não encontrado.",
    "details": {},
    "request_id": "step2-final"
  }
}
~~~

WebSocket usa:

~~~
{
  "v": 1,
  "id": "id-do-comando",
  "type": "error",
  "data": {
    "code": "INVALID_MARKET_ID",
    "message": "market_id deve ser um UUID válido.",
    "details": {}
  }
}
~~~

| Código | Significado |
| --- | --- |
| UNAUTHENTICATED | token ausente, inválido ou expirado |
| FORBIDDEN | usuário sem permissão |
| INVALID_PAYLOAD | payload fora do contrato |
| INVALID_MARKET_ID | UUID inválido |
| MARKET_NOT_FOUND | mercado inexistente ou inativo |
| SUBSCRIPTION_LIMIT | limite de mercados excedido |
| RATE_LIMITED | limite temporário excedido |
| STALE_MARKET_DATA | cotação sem atualização recente |
| MARKET_NOT_AVAILABLE | listagem inexistente, inativa ou sem fonte ativa |
| market_data_unavailable | fonte sem dado atual ou indisponível; REST responde 503 |

## 8. REST do MVP 1

### Já disponível

| Método e rota | Autenticação | Resposta |
| --- | --- | --- |
| GET /health/live/ | pública | processo ativo |
| GET /health/ready/ | pública | SQLite e Redis disponíveis |
| GET /api/v1/status/ | pública | versão do backend |
| POST /api/v1/auth/register/ | pública | usuário criado |
| POST /api/v1/auth/token/ | pública | access e refresh tokens |
| POST /api/v1/auth/token/refresh/ | pública | novo access token |
| GET /api/v1/auth/me/ | JWT | usuário atual |

### Disponível no MVP

| Recurso | Rotas |
| --- | --- |
| Mercado | GET /api/v1/markets/, GET /api/v1/markets/{id}/, GET /api/v1/markets/{id}/quote/, GET /api/v1/markets/{id}/candles/?interval=1h&limit=200, GET /api/v1/markets/radar/?limit=5 |
| Watchlists | GET,POST /api/v1/watchlists/, GET,PATCH,DELETE /api/v1/watchlists/{id}/, POST /api/v1/watchlists/{id}/items/, DELETE /api/v1/watchlists/{id}/items/{market_id}/ |
| Alertas | GET,POST /api/v1/alerts/, GET,PATCH,DELETE /api/v1/alerts/{id}/, POST /api/v1/alerts/{id}/pause/, POST /api/v1/alerts/{id}/resume/, GET /api/v1/alerts/{id}/events/ |
| Dispositivos | PUT /api/v1/devices/{device_id}/, DELETE /api/v1/devices/{device_id}/ |
| Notificações | GET /api/v1/notifications/, POST /api/v1/notifications/{id}/opened/ |
| Preferências | GET,PATCH /api/v1/auth/me/preferences/ |

As listas retornam arrays no MVP. A idempotência implementada cobre o consumo
de eventos Redis por alertas e notificações.

## 9. Alertas e notificações

O cliente envia valores decimais como strings:

~~~
{
  "market_id": "ec365d88-5d98-4cd8-9d95-51c639e0e299",
  "name": "BTC acima de 70 mil",
  "logic": "AND",
  "cooldown_seconds": 300,
  "conditions": [
    {
      "condition_type": "PRICE_ABOVE",
      "operator": "gt",
      "value_numeric": "70000",
      "window_seconds": null,
      "position": 0
    }
  ]
}
~~~

Os workers usam o ID do Redis Stream como origem do evento. Uma reentrega não
cria novo AlertEvent, notificação nem push.

Push contém somente dados necessários para abrir a tela correta:

~~~
{
  "type": "market_alert",
  "notification_id": "b1e0f354-fbb7-4fd9-b251-b5f8c44b07d0",
  "alert_event_id": "19f3fe4d-9412-4d63-a84e-7b43df804873",
  "market_id": "ec365d88-5d98-4cd8-9d95-51c639e0e299"
}
~~~

Tokens FCM, APNs e Web Push não entram em logs, respostas REST ou WebSocket.

## 10. Limites para produção

| Escopo | Limite |
| --- | --- |
| login | 5 tentativas por IP em 15 minutos |
| refresh | 20 por usuário em 15 minutos |
| API autenticada | 120 requisições por minuto por usuário |
| WebSocket | 50 mercados por conexão |
| mensagens de comando | 30 por minuto por conexão |

Os limites REST e WebSocket foram aplicados no backend. A validação de carga e
o uso de cache compartilhado no ambiente de produção continuam obrigatórios
antes de exposição pública.

## 11. Estado da implementação

O MVP usa a rota JWT `/ws/v1/market/`, snapshots e deltas com sequência,
reconexão no Flutter, detecção de cotações desatualizadas e testes de contrato.
A rota antiga `/ws/market/` permanece apenas por compatibilidade local e pode
ser removida depois que não houver clientes dependentes.

## 12. Critérios de aceite

- Flutter e Web autenticam usando o mesmo access token JWT.
- O cliente recebe um snapshot antes de qualquer delta.
- Reconexão recupera estado sem ticks duplicados.
- Uma mensagem Redis reentregue não gera alerta ou push duplicado.
- Dados antigos aparecem como stale.
- Limites de produção são aplicados antes de exposição pública.
- Nenhum token, segredo ou URL com JWT aparece nos logs.
