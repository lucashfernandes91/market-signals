#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

validate_release_version "${1:-}"
image="market-radar/backend:$APP_VERSION"
if ! docker image inspect "$image" >/dev/null 2>&1; then
    printf 'Release image is not available locally: %s\n' "$image" >&2
    exit 1
fi

compose config --quiet
compose up -d --no-build --wait --wait-timeout 180 \
    --force-recreate web catalog-sync market-ingestor alert-worker notification-worker
compose ps
