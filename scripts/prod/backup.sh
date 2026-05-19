#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# scripts/prod/backup.sh
#
# Takes a full Frappe backup (DB + private + public files) and copies the
# resulting archives out of the named `sites` volume to ./backups/<timestamp>/
# on the host filesystem.
#
# This is the single procedure used for:
#   - routine nightly/weekly backups
#   - dev → prod data seeding
#   - host A → host B migration
#
# Cron example (daily at 02:00):
#   0 2 * * *  /opt/aca/infra/scripts/prod/backup.sh >> /var/log/aca-backup.log 2>&1
#
# Usage:
#   ./scripts/prod/backup.sh                # nightly: keep 14 days
#   ./scripts/prod/backup.sh --keep 30      # retain 30 generations
#   ./scripts/prod/backup.sh --label cutover-pre  # name the folder ./backups/cutover-pre/
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
COMPOSE_DIR="$REPO_ROOT/compose/prod"
ENV_FILE="$COMPOSE_DIR/.env"
BACKUPS_DIR="$REPO_ROOT/backups"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: $ENV_FILE not found." >&2; exit 1
fi
set -a; source "$ENV_FILE"; set +a

KEEP=14
LABEL=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep) KEEP="$2"; shift 2 ;;
    --label) LABEL="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
TARGET_NAME="${LABEL:-$STAMP}"
TARGET_DIR="$BACKUPS_DIR/$TARGET_NAME"
mkdir -p "$TARGET_DIR"

log() { printf '\033[1;33m[backup]\033[0m %s\n' "$*"; }

log "taking backup of site $SITE_NAME (inside backend container)"
docker compose --env-file "$ENV_FILE" -f "$COMPOSE_DIR/compose.yml" \
  exec -T backend bench --site "$SITE_NAME" backup --with-files --compress

# `bench backup` writes to sites/<site>/private/backups/*.sql.gz (+ files tars).
# Pull them out of the named volume to the host so we can rsync/ship them.
log "copying backup artifacts out to $TARGET_DIR"
BACKEND_CTR="${STACK_NAME}_backend"
docker exec "$BACKEND_CTR" bash -c \
  "ls -1t sites/$SITE_NAME/private/backups/* | head -8" \
  | while read -r remote; do
      local_name="$(basename "$remote")"
      docker cp "$BACKEND_CTR:$remote" "$TARGET_DIR/$local_name"
      log "  + $local_name"
    done

# Trim oldest generations beyond $KEEP, but never delete the most recent.
log "pruning to most recent $KEEP timestamped folders (labels are preserved)"
mapfile -t TIMESTAMPED < <(find "$BACKUPS_DIR" -maxdepth 1 -mindepth 1 -type d \
  -regextype posix-extended -regex '.*/[0-9]{8}T[0-9]{6}Z$' | sort)
if (( ${#TIMESTAMPED[@]} > KEEP )); then
  PRUNE_COUNT=$(( ${#TIMESTAMPED[@]} - KEEP ))
  for ((i=0; i<PRUNE_COUNT; i++)); do
    log "  - pruning ${TIMESTAMPED[$i]}"
    rm -rf "${TIMESTAMPED[$i]}"
  done
fi

log "backup complete: $TARGET_DIR"
ls -la "$TARGET_DIR"
