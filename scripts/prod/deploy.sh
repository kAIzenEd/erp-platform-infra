#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# scripts/prod/deploy.sh
#
# Day-2 deploy procedure for the ETS ERPNext PROD stack.
#
# Steps:
#   1. git pull each custom app under $REPOS_ROOT (ets_admissions, ets_students)
#   2. run `bench --site $SITE_NAME migrate` inside the backend container
#   3. clear cache (build assets are not bundled per app for our pure-server apps)
#   4. restart the long-running services so Python re-imports module code
#
# Run from anywhere; the script auto-locates compose/prod relative to itself.
#
# Usage:
#   ./scripts/prod/deploy.sh                 # full deploy
#   ./scripts/prod/deploy.sh --skip-pull     # skip git pull (deploy already-fetched code)
#   ./scripts/prod/deploy.sh --app NAME      # pull/migrate only one custom app
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
COMPOSE_DIR="$REPO_ROOT/compose/prod"
ENV_FILE="$COMPOSE_DIR/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: $ENV_FILE not found. Copy .env.example and fill it in first." >&2
  exit 1
fi

# Load .env so we can use $SITE_NAME, $REPOS_ROOT, etc.
set -a; source "$ENV_FILE"; set +a

SKIP_PULL=0
APP_FILTER=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-pull) SKIP_PULL=1; shift ;;
    --app) APP_FILTER="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

log() { printf '\033[1;36m[deploy]\033[0m %s\n' "$*"; }

APPS=(ets_admissions ets_students)
if [[ -n "$APP_FILTER" ]]; then
  APPS=("$APP_FILTER")
fi

if [[ "$SKIP_PULL" -eq 0 ]]; then
  for app in "${APPS[@]}"; do
    APP_DIR="$REPOS_ROOT/$app"
    if [[ ! -d "$APP_DIR/.git" ]]; then
      log "SKIP $app — $APP_DIR is not a git repo"
      continue
    fi
    log "git pull: $APP_DIR"
    git -C "$APP_DIR" fetch --prune
    git -C "$APP_DIR" pull --ff-only
    log "  HEAD: $(git -C "$APP_DIR" log -1 --oneline)"
  done
fi

log "running bench migrate on site $SITE_NAME"
docker compose --env-file "$ENV_FILE" -f "$COMPOSE_DIR/compose.yml" \
  exec -T backend bench --site "$SITE_NAME" migrate

log "clearing cache"
docker compose --env-file "$ENV_FILE" -f "$COMPOSE_DIR/compose.yml" \
  exec -T backend bench --site "$SITE_NAME" clear-cache

log "restarting services so Python reloads"
docker compose --env-file "$ENV_FILE" -f "$COMPOSE_DIR/compose.yml" \
  restart backend frontend websocket queue-short queue-long scheduler

log "deploy complete. Verify: docker compose logs --tail 30 backend"
