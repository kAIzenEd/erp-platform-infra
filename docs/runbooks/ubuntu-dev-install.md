# Ubuntu dev install runbook — ETS ERPNext (port 8081)

Stand up the **development** stack on the same Ubuntu host as prod, then restore the Mac `frappe_docker` backup (site name **`frontend`**).

> **Prerequisites**
>
> - Prod already running per [`ubuntu-prod-install.md`](./ubuntu-prod-install.md)
> - Custom apps at `/opt/aca/repos/ets_admissions` and `ets_students`
> - Mac backup copied to `/opt/aca/dev-backup/` (four files with prefix `*-frontend-*`)

| Item | Dev | Prod (reference) |
|------|-----|------------------|
| Site name | `frontend` | `erp.aca.local` |
| Stack | `ets_dev` | `ets_prod` |
| Port | `8081` | `8080` |
| URL | http://frontend:8081/desk | http://erp.aca.local:8080 |

---

## Phase 0 — Copy Mac backup to the VM

On the **Mac** (adjust path if your latest backup differs):

```bash
rsync -avz ~/erpnext-migration-backups/latest/ \
  kaizen@192.168.29.21:/opt/aca/dev-backup/
```

Or use a shared folder / USB. On the **VM**:

```bash
ls -lh /opt/aca/dev-backup/
# Expect: *-frontend-database.sql.gz, *-files.tar, *-private-files.tar, *-site_config_backup.json
```

---

## Phase 1 — Pull infra with dev compose

```bash
cd /opt/aca/infra
git pull
```

Confirm:

```bash
ls /opt/aca/infra/compose/dev/compose.yml
ls /opt/aca/infra/scripts/dev/restore.sh
```

---

## Phase 2 — Create dev `.env`

```bash
cd /opt/aca/infra/compose/dev
cp .env.example .env
chmod 600 .env
```

Generate **new** secrets (different from prod):

```bash
DB_PASS=$(openssl rand -hex 24)
ADMIN_PASS=$(openssl rand -hex 32)
sed -i "s/^DB_ROOT_PASSWORD=.*/DB_ROOT_PASSWORD=$DB_PASS/" .env
sed -i "s/^ADMIN_PASSWORD=.*/ADMIN_PASSWORD=$ADMIN_PASS/" .env
```

Verify:

```bash
grep -E '^(STACK_NAME|SITE_NAME|WEB_PORT|REPOS_ROOT)=' .env
# STACK_NAME=ets_dev
# SITE_NAME=frontend
# WEB_PORT=8081
# REPOS_ROOT=/opt/aca/repos
```

---

## Phase 3 — Start dev stack (empty site first)

```bash
cd /opt/aca/infra/compose/dev
docker compose --env-file .env pull
docker compose --env-file .env up -d
```

Watch bootstrap:

```bash
docker compose --env-file .env logs -f configurator
```

Wait for `configurator: done` → **Ctrl+C**

```bash
docker compose --env-file .env logs -f create-site
```

Wait for `create-site: done` → **Ctrl+C**

```bash
docker compose --env-file .env ps -a
```

Both one-shots should be **Exited (0)**.

---

## Phase 4 — Restore Mac backup

```bash
chmod +x /opt/aca/infra/scripts/dev/restore.sh
/opt/aca/infra/scripts/dev/restore.sh /opt/aca/dev-backup
```

When prompted, type: **`frontend`**

The script runs migrate, clear-cache, `bench build`, and restarts services.

---

## Phase 5 — Hosts and browser

On the **VM** (and on your Mac if you browse the VM by IP):

```bash
grep -q frontend /etc/hosts || echo "127.0.0.1   frontend" | sudo tee -a /etc/hosts
```

From the VM browser:

- **http://frontend:8081/desk**
- Or login: **http://frontend:8081/login**

**Login after restore:** use the **Administrator password from your Mac site** (the backup), not necessarily `ADMIN_PASSWORD` in dev `.env`.

---

## Phase 6 — Verify

```bash
curl -s -H "Host: frontend" http://127.0.0.1:8081/api/method/ping
```

Expected: `{"message":"pong"}`

Confirm custom modules appear in Desk.

---

## Phase 7 — Stop Mac Docker (optional, after dev works)

On the **Mac**:

```bash
cd ~/dev/frappe_docker
docker compose -f pwd.yml down

cd ~/ets-repos/erp-platform-infra
docker compose --env-file env/dev/.env \
  -f compose/common/docker-compose.base.yml \
  -f compose/docker-compose.dev.yml down
```

Do not use `-v` unless you intend to delete Mac volumes.

---

## Full reset dev only (keep prod running)

```bash
cd /opt/aca/infra/compose/dev
docker compose --env-file .env down --remove-orphans
docker ps -a --filter name=ets_dev -q | xargs -r docker rm -f

docker volume rm ets_dev_sites ets_dev_db_data ets_dev_logs \
  ets_dev_redis_queue_data ets_dev_bench_env 2>/dev/null || true
```

Then repeat Phase 3 → 4.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Prod and dev clash | Different `STACK_NAME`, `WEB_PORT`, volumes (`ets_prod_*` vs `ets_dev_*`) |
| Restore: wrong site | Backup must be `*-frontend-*`; `SITE_NAME=frontend` in dev `.env` |
| 404 / site does not exist | URL must use host **frontend**, port **8081** |
| Unstyled UI | `docker compose exec backend bench build --force` then restart frontend/backend |
| `No module named 'ets_*'` | Re-run prod-style fix: ensure `bench-env` in `compose/dev/compose.yml`, wipe `ets_dev_bench_env`, `up -d` again |

---

## Copy-paste summary

```bash
cd /opt/aca/infra && git pull
cd /opt/aca/infra/compose/dev && cp .env.example .env && chmod 600 .env
# edit .env secrets (openssl rand) — see Phase 2

docker compose --env-file .env pull
docker compose --env-file .env up -d
docker compose --env-file .env logs -f configurator
docker compose --env-file .env logs -f create-site

/opt/aca/infra/scripts/dev/restore.sh /opt/aca/dev-backup
# type: frontend

grep -q frontend /etc/hosts || echo "127.0.0.1   frontend" | sudo tee -a /etc/hosts
curl -s -H "Host: frontend" http://127.0.0.1:8081/api/method/ping
```

Open **http://frontend:8081/desk**
