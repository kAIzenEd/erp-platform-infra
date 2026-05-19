#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# scripts/prod/restore.sh
#
# Restores a Frappe backup (taken by backup.sh) onto the running PROD stack.
#
# *** DESTRUCTIVE: replaces the current site DB and files. ***
# Run a backup.sh first if you're not sure you want to overwrite.
#
# Usage:
#   ./scripts/prod/restore.sh ./backups/20260512T080000Z
#   ./scripts/prod/restore.sh ./backups/cutover-pre
#
# The folder must contain a *.sql.gz file. Public/private files are restored
# automatically if the matching *-files.tar / *-files.tgz files are present.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
COMPOSE_DIR="$REPO_ROOT/compose/prod"
ENV_FILE="$COMPOSE_DIR/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: $ENV_FILE not found." >&2; exit 1
fi
set -a; source "$ENV_FILE"; set +a

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <backup-folder>" >&2
  exit 1
fi
SRC="$1"
if [[ ! -d "$SRC" ]]; then
  echo "ERROR: $SRC is not a directory" >&2; exit 1
fi

log() { printf '\033[1;31m[restore]\033[0m %s\n' "$*"; }

DB_FILE="$(ls -1 "$SRC"/*-database.sql.gz 2>/dev/null | head -1 || true)"
if [[ -z "$DB_FILE" ]]; then
  log "ERROR: no *-database.sql.gz file in $SRC"
  exit 1
fi

PRIVATE_FILES="$(ls -1 "$SRC"/*-private-files.tar 2>/dev/null | head -1 || true)"
PUBLIC_FILES="$(ls -1 "$SRC"/*-files.tar 2>/dev/null | grep -v -- '-private-' | head -1 || true)"

log "restoring onto site $SITE_NAME"
log "  DB:       $(basename "$DB_FILE")"
log "  private:  ${PRIVATE_FILES:+$(basename "$PRIVATE_FILES")}"
log "  public:   ${PUBLIC_FILES:+$(basename "$PUBLIC_FILES")}"

read -r -p "Type the site name '$SITE_NAME' to confirm DESTRUCTIVE restore: " CONFIRM
if [[ "$CONFIRM" != "$SITE_NAME" ]]; then
  log "aborted."
  exit 1
fi

BACKEND_CTR="${STACK_NAME}_backend"

# Copy archives into the container before restoring.
TMP_REMOTE="/tmp/restore-$(date +%s)"
docker exec "$BACKEND_CTR" mkdir -p "$TMP_REMOTE"
docker cp "$DB_FILE" "$BACKEND_CTR:$TMP_REMOTE/"
if [[ -n "$PRIVATE_FILES" ]]; then docker cp "$PRIVATE_FILES" "$BACKEND_CTR:$TMP_REMOTE/"; fi
if [[ -n "$PUBLIC_FILES" ]]; then docker cp "$PUBLIC_FILES" "$BACKEND_CTR:$TMP_REMOTE/"; fi

# Run bench restore inside the container.
EXTRA=""
if [[ -n "$PRIVATE_FILES" ]]; then EXTRA+=" --with-private-files $TMP_REMOTE/$(basename "$PRIVATE_FILES")"; fi
if [[ -n "$PUBLIC_FILES" ]]; then EXTRA+=" --with-public-files $TMP_REMOTE/$(basename "$PUBLIC_FILES")"; fi

log "running bench --site $SITE_NAME restore ..."
docker exec -i "$BACKEND_CTR" bash -lc \
  "bench --site $SITE_NAME --force restore $TMP_REMOTE/$(basename "$DB_FILE") $EXTRA"

log "running bench migrate after restore (apps may be a newer version)"
docker exec "$BACKEND_CTR" bench --site "$SITE_NAME" migrate

log "restarting services"
docker compose --env-file "$ENV_FILE" -f "$COMPOSE_DIR/compose.yml" \
  restart backend frontend websocket queue-short queue-long scheduler

log "restore complete. Smoke check: open http://<host>:${WEB_PORT}/"
