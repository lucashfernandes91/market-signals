#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

compose config --quiet
backup_dir="${BACKUP_DIR:-$PRODUCTION_ROOT/var/production/backups}"
mkdir -p "$backup_dir"
chmod 700 "$backup_dir"
umask 077

timestamp="$(date -u +%Y%m%dT%H%M%SZ)-$$"
database_backup="$backup_dir/postgres-$timestamp.dump"
redis_backup="$backup_dir/redis-$timestamp.rdb"
database_temporary="$database_backup.partial"
redis_temporary_host="$redis_backup.partial"
redis_temporary="/tmp/market-radar-backup-$$.rdb"
redis_container="$(compose ps -q redis)"

if [[ -z "$redis_container" ]]; then
    printf 'Redis container is not running; start production services before backing up.\n' >&2
    exit 1
fi

cleanup() {
    compose exec -T redis rm -f "$redis_temporary" >/dev/null 2>&1 || true
    rm -f "$database_temporary" "$redis_temporary_host"
}
trap cleanup EXIT

compose exec -T postgres sh -c \
    'pg_dump --format=custom --username "$POSTGRES_USER" --dbname "$POSTGRES_DB"' \
    > "$database_temporary"
compose exec -T postgres pg_restore --list - < "$database_temporary" > /dev/null

compose exec -T redis redis-cli --rdb "$redis_temporary"
compose exec -T redis redis-check-rdb "$redis_temporary"
docker cp "$redis_container:$redis_temporary" "$redis_temporary_host"
chmod 600 "$redis_temporary_host"
mv "$database_temporary" "$database_backup"
mv "$redis_temporary_host" "$redis_backup"

printf 'PostgreSQL backup: %s\nRedis RDB backup: %s\n' "$database_backup" "$redis_backup"
