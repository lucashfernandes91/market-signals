#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

validate_release_version "${1:-}"
compose config --quiet
compose build migrate web catalog-sync market-ingestor alert-worker notification-worker
compose up -d --wait postgres redis
bash "$PRODUCTION_ROOT/scripts/production/backup.sh"
compose up -d --force-recreate migrate
compose up -d --wait --wait-timeout 180 \
    web catalog-sync market-ingestor alert-worker notification-worker
compose ps
