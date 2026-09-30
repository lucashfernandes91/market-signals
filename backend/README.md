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

O Compose fica na raiz do projeto. Em um volume novo, prepare o banco antes de iniciar os
processos:

```powershell
docker compose run --rm web python manage.py migrate
docker compose run --rm web python manage.py seed_market
docker compose up -d
```

O Compose usa recursos próprios do projeto: container `market-radar-dev-redis-1`,
volume `market-radar-dev_redis_data`, rede `market-radar-dev_default`, Redis na porta
local `6380` e Django na porta local `8001`.
