#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

postgres_backup="${1:-}"
redis_backup="${2:-}"
if [[ ! -f "$postgres_backup" || ! -f "$redis_backup" ]]; then
    printf 'Usage: bash scripts/production/restore.sh <postgres.dump> <redis.rdb>\n' >&2
    exit 1
fi

postgres_timestamp="$(basename -- "$postgres_backup")"
postgres_timestamp="${postgres_timestamp#postgres-}"
postgres_timestamp="${postgres_timestamp%.dump}"
redis_timestamp="$(basename -- "$redis_backup")"
redis_timestamp="${redis_timestamp#redis-}"
redis_timestamp="${redis_timestamp%.rdb}"
if [[ -z "$postgres_timestamp" || "$postgres_timestamp" != "$redis_timestamp" ]]; then
    printf 'PostgreSQL and Redis backups must share the same generated timestamp.\n' >&2
    exit 1
fi

compose config --quiet
docker run --rm --network none -v "$redis_backup:/backup.rdb:ro" \
    redis:8.2.10-alpine redis-check-rdb /backup.rdb
compose exec -T postgres pg_restore --list - < "$postgres_backup" > /dev/null

database_name="$(compose exec -T postgres printenv POSTGRES_DB | tr -d '\r')"
if [[ -z "$database_name" ]]; then
    printf 'Could not determine the configured PostgreSQL database.\n' >&2
    exit 1
fi

printf 'This restore replaces PostgreSQL data in "%s" and Redis data. Type the database name to continue: ' \
    "$database_name"
read -r confirmation
if [[ "$confirmation" != "$database_name" ]]; then
    printf 'Restore cancelled; no services or data were changed.\n' >&2
    exit 1
fi

restore_container=""
cleanup_restore_container() {
    if [[ -n "$restore_container" ]]; then
        docker rm -f "$restore_container" >/dev/null 2>&1 || true
    fi
}
trap cleanup_restore_container EXIT

compose stop web catalog-sync market-ingestor alert-worker notification-worker redis
compose exec -T postgres sh -c \
    'pg_restore --clean --if-exists --exit-on-error --single-transaction --no-owner --no-privileges --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -' \
    < "$postgres_backup"

compose run --rm --no-deps \
    -v "$redis_backup:/restore.rdb:ro" \
    redis sh -c 'rm -rf /data/appendonlydir && cp /restore.rdb /data/dump.rdb'
restore_container="$(compose run -d --no-deps redis sh -c \
    'exec redis-server --requirepass "$REDISCLI_AUTH" --appendonly no')"

redis_ready=false
for ((attempt = 0; attempt < 30; attempt++)); do
    if docker exec "$restore_container" redis-cli ping >/dev/null 2>&1; then
        redis_ready=true
        break
    fi
    sleep 1
done
if [[ "$redis_ready" != true ]]; then
    printf 'Temporary Redis did not become ready to load the restored snapshot.\n' >&2
    exit 1
fi

docker exec "$restore_container" redis-cli CONFIG SET appendonly yes >/dev/null
aof_ready=false
for ((attempt = 0; attempt < 600; attempt++)); do
    persistence="$(docker exec "$restore_container" redis-cli INFO persistence)"
    if grep -q '^aof_enabled:1' <<< "$persistence" \
        && grep -q '^aof_rewrite_in_progress:0' <<< "$persistence" \
        && grep -q '^aof_last_bgrewrite_status:ok' <<< "$persistence" \
        && docker exec "$restore_container" test -s /data/appendonlydir/appendonly.aof.manifest; then
        aof_ready=true
        break
    fi
    sleep 1
done
if [[ "$aof_ready" != true ]]; then
    printf 'Redis did not finish creating its append-only files from the restored snapshot.\n' >&2
    exit 1
fi

docker stop "$restore_container" >/dev/null
docker rm "$restore_container" >/dev/null
restore_container=""
compose up -d --wait redis

printf 'Restore completed. Application services remain stopped; redeploy the compatible release after verification.\n'
