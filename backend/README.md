# Market Radar Backend

Fundação Django do Market Radar.

## Desenvolvimento

```powershell
uv sync
docker compose -f ..\docker-compose.yml up -d redis
uv run python manage.py migrate
uv run python manage.py seed_market
uv run daphne -b 127.0.0.1 -p 8001 core.asgi:application
```

Em terminais separados:

```powershell
uv run python manage.py run_market_ingestor
uv run python manage.py run_alert_worker
uv run python manage.py run_notification_worker
```

Endpoints iniciais:

- `GET /health/live/`
- `GET /health/ready/`
- `GET /api/v1/status/`
- `POST /api/v1/auth/register/`
- `POST /api/v1/auth/token/`
- `POST /api/v1/auth/token/refresh/`
- `GET /api/v1/auth/me/`
- `/admin/`

O seed inicial pode ser executado depois das migrations:

```powershell
uv run python manage.py seed_market
```

Com Redis ativo, o provider simulado pode ser executado com:

```powershell
uv run python manage.py run_market_ingestor
```

API local: `http://127.0.0.1:8001/`.

WebSocket inicial: `ws://127.0.0.1:8001/ws/market/`.

O Compose fica na raiz do projeto. O serviço web aplica migrations e executa o seed
idempotente antes de iniciar:

```powershell
docker compose up --build -d
docker compose ps
docker compose logs -f
```

O Compose usa recursos próprios do projeto: container `market-radar-dev-redis-1`,
volume `market-radar-dev_redis_data`, rede `market-radar-dev_default`, Redis na porta
local `6380` e Django na porta local `8001`.

Para reconstruir no Redis o índice dos alertas ativos:

```powershell
uv run python manage.py rebuild_alert_index
```

## Qualidade

```powershell
uv run python manage.py check
uv run ruff check .
uv run ruff format --check .
uv run mypy apps/alerts/evaluator.py apps/market/providers infrastructure/redis/keys.py
uv run pytest
```

A CI executa essas verificações com Python 3.12 e Redis.

## Protocolo

O contrato REST e WebSocket está em docs/02_COMMUNICATION_PROTOCOLS.md na raiz
do repositório.
