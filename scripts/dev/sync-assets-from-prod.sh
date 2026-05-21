#!/usr/bin/env bash
# Copy pre-built Frappe/ERPNext dist/ trees from prod containers into dev containers.
#
# The production frappe/erpnext image does not include Node, so `bench build`
# cannot rebundle assets on dev. sites/assets (symlinks + assets.json) is already
# shared via volume copy, but hashed CSS/JS files live under each container's
# apps/*/public/dist/ filesystem — prod usually has them after a healthy boot.
#
# Run after restore.sh (or whenever dev Desk looks unstyled).
#
# Usage:
#   ./scripts/dev/sync-assets-from-prod.sh
#   PROD_STACK=ets_prod DEV_STACK=ets_dev ./scripts/dev/sync-assets-from-prod.sh
set -euo pipefail

PROD_STACK="${PROD_STACK:-ets_prod}"
DEV_STACK="${DEV_STACK:-ets_dev}"

log() { printf '\033[1;32m[sync-assets]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[sync-assets]\033[0m %s\n' "$*" >&2; exit 1; }

for ctr in "${PROD_STACK}_frontend" "${PROD_STACK}_backend" "${DEV_STACK}_frontend" "${DEV_STACK}_backend"; do
  if ! docker inspect "$ctr" >/dev/null 2>&1; then
    die "container $ctr is not running. Start prod and dev stacks first."
  fi
done

sync_dist() {
  local app_path="$1"
  local from_ctr="$2"
  local to_ctr="$3"
  log "  $app_path: $from_ctr -> $to_ctr"
  docker exec "$from_ctr" test -d "/home/frappe/frappe-bench/apps/${app_path}/public/dist" \
    || die "missing dist on $from_ctr: apps/${app_path}/public/dist"
  docker exec "$from_ctr" tar -C "/home/frappe/frappe-bench/apps/${app_path}/public" -cf - dist \
    | docker exec -i "$to_ctr" tar -C "/home/frappe/frappe-bench/apps/${app_path}/public" -xf -
}

for role in frontend backend; do
  from="${PROD_STACK}_${role}"
  to="${DEV_STACK}_${role}"
  log "syncing dist for $to from $from"
  sync_dist "frappe/frappe" "$from" "$to"
  sync_dist "erpnext/erpnext" "$from" "$to"
done

# Verify desk CSS path from assets.json (if present)
DESK_CSS="$(docker exec "${DEV_STACK}_backend" python3 -c "
import json
p='/home/frappe/frappe-bench/sites/assets/assets.json'
d=json.load(open(p))
print(d.get('desk.bundle.css','').split('/')[-1])
" 2>/dev/null || true)"

if [[ -n "$DESK_CSS" ]]; then
  if docker exec "${DEV_STACK}_frontend" test -f "/home/frappe/frappe-bench/apps/frappe/frappe/public/dist/css/${DESK_CSS}"; then
    log "verified: frappe/public/dist/css/${DESK_CSS}"
  else
    die "after sync, still missing apps/frappe/frappe/public/dist/css/${DESK_CSS}"
  fi
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
COMPOSE_DIR="$REPO_ROOT/compose/dev"
ENV_FILE="$COMPOSE_DIR/.env"

if [[ -f "$ENV_FILE" ]]; then
  set -a; source "$ENV_FILE"; set +a
  log "flushing redis + clear-cache for site ${SITE_NAME:-frontend}"
  docker compose --env-file "$ENV_FILE" -f "$COMPOSE_DIR/compose.yml" \
    exec -T redis-cache redis-cli FLUSHALL >/dev/null 2>&1 || true
  docker exec "${DEV_STACK}_backend" bench --site "${SITE_NAME:-frontend}" clear-cache >/dev/null 2>&1 || true
  log "restarting dev web services"
  docker compose --env-file "$ENV_FILE" -f "$COMPOSE_DIR/compose.yml" \
    restart frontend backend websocket queue-short queue-long >/dev/null
fi

log "done. Open http://frontend:${WEB_PORT:-8081}/desk (hard refresh)."
