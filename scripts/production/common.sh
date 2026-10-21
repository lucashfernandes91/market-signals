#!/usr/bin/env bash
set -Eeuo pipefail

PRODUCTION_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
PRODUCTION_ENV_FILE="${ENV_FILE:-$PRODUCTION_ROOT/backend/.env.production}"
PRODUCTION_COMPOSE_FILE="$PRODUCTION_ROOT/docker-compose.production.yml"

if [[ ! -f "$PRODUCTION_ENV_FILE" ]]; then
    printf 'Production environment file not found: %s\n' "$PRODUCTION_ENV_FILE" >&2
    exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
    printf 'Docker is required for production operations.\n' >&2
    exit 1
fi

compose() {
    docker compose --env-file "$PRODUCTION_ENV_FILE" -f "$PRODUCTION_COMPOSE_FILE" "$@"
}

validate_release_version() {
    local version="${1:-}"
    if [[ ! "$version" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]]; then
        printf 'Release version must be a unique tag using letters, digits, ".", "_" or "-".\n' >&2
        return 1
    fi
    export APP_VERSION="$version"
}
