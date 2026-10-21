#!/usr/bin/env bash
set -Eeuo pipefail

base_url="${1:-}"
if [[ -z "$base_url" ]]; then
    printf 'Usage: bash scripts/production/check-health.sh https://api.seudominio.com\n' >&2
    exit 1
fi
base_url="${base_url%/}"
for endpoint in health/live health/ready api/v1/status; do
    printf '%s: ' "$endpoint"
    curl --fail --silent --show-error --max-time 10 "$base_url/$endpoint"
    printf '\n'
done
