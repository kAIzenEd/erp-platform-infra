# Ubuntu prod install runbook — ETS ERPNext (port 8080)

Step-by-step commands for standing up the **production** stack on Ubuntu (VM or bare metal). This documents the path that was validated on a GUI Ubuntu VM with Docker.

> **Related docs**
>
> - Architecture, migration, Cloudflare, day-2 scripts: [`prod-setup.md`](./prod-setup.md)
> - Compose stack: [`../../compose/prod/compose.yml`](../../compose/prod/compose.yml)
>
> **Stack identity**
>
> | Item | Value |
> |------|--------|
> | Site name (Host header) | `erp.aca.local` |
> | Stack prefix | `ets_prod` |
> | HTTP port | `8080` |
> | Infra path | `/opt/aca/infra` |
> | Custom apps | `/opt/aca/repos/ets_admissions`, `/opt/aca/repos/ets_students` |

---

## Prerequisites (once per host)

```bash
docker --version
docker compose version

# Optional: avoid sudo for every docker command
sudo usermod -aG docker $USER
newgrp docker

sudo mkdir -p /opt/aca
sudo chown $USER:$USER /opt/aca
```

---

## Phase 1 — First-time prod install (clean host)

### 1. Clone infrastructure repo

```bash
cd /opt/aca
git clone https://github.com/kAIzenEd/erp-platform-infra.git infra
```

### 2. Clone custom apps (required)

The prod compose bind-mounts app source from the host. Repos use a nested package layout (`ets_admissions/ets_admissions/hooks.py`).

```bash
mkdir -p /opt/aca/repos
git clone https://github.com/kAIzenEd/ets_admissions.git /opt/aca/repos/ets_admissions
git clone https://github.com/kAIzenEd/ets_students.git   /opt/aca/repos/ets_students

ls /opt/aca/repos/ets_admissions/ets_admissions/hooks.py
ls /opt/aca/repos/ets_students/ets_students/hooks.py
```

### 3. Bootstrap host

Creates `/opt/aca/repos` if needed, writes `compose/prod/.env` with random secrets, pulls images.

```bash
/opt/aca/infra/scripts/prod/bootstrap-host.sh
```

Save passwords immediately:

```bash
grep -E '^(DB_ROOT_PASSWORD|ADMIN_PASSWORD|SITE_NAME|WEB_PORT|REPOS_ROOT|STACK_NAME)=' \
  /opt/aca/infra/compose/prod/.env
```

### 4. Start the stack

```bash
cd /opt/aca/infra/compose/prod
docker compose --env-file .env pull
docker compose --env-file .env up -d
```

### 5. Watch one-shot services (order matters)

**Configurator** — pip-installs custom apps into shared `bench-env` volume, writes `sites/apps.txt`, sets global bench config:

```bash
docker compose --env-file .env logs -f configurator
```

Wait for `configurator: done`, then **Ctrl+C**.

**Create site** — first boot often takes 3–5 minutes:

```bash
docker compose --env-file .env logs -f create-site
```

Wait for `create-site: done`, then **Ctrl+C**.

### 6. Verify containers

```bash
docker compose --env-file .env ps -a
```

| Container | Expected status |
|-----------|-----------------|
| `ets_prod_configurator` | Exited (0) |
| `ets_prod_create_site` | Exited (0) |
| `ets_prod_backend`, `ets_prod_frontend`, `ets_prod_db`, redis, workers | Up |

### 7. Verify API

```bash
curl -s -H "Host: erp.aca.local" http://127.0.0.1:8080/api/method/ping
```

Expected: `{"message":"pong"}`

### 8. Hosts file and browser

On the Ubuntu host (or on client machines that browse prod):

```bash
grep -q erp.aca.local /etc/hosts || echo "127.0.0.1   erp.aca.local" | sudo tee -a /etc/hosts
```

- URL: **http://erp.aca.local:8080**
- User: `Administrator`
- Password: `ADMIN_PASSWORD` from `compose/prod/.env`

---

## Phase 2 — Full reset (wipe prod data, reinstall)

Use after a failed install, DB/site credential mismatch (`1045 Access denied`), or when you need an empty prod site again.

```bash
cd /opt/aca/infra/compose/prod

docker compose --env-file .env down --remove-orphans

# Remove stray one-off containers (e.g. from `docker compose run`)
docker ps -a --filter name=ets_prod -q | xargs -r docker rm -f
docker ps -a --filter name=prod- -q | xargs -r docker rm -f

# DESTROYS prod database, site files, bench env, logs, redis queue persistence
docker volume rm ets_prod_sites ets_prod_db_data ets_prod_logs \
  ets_prod_redis_queue_data ets_prod_bench_env 2>/dev/null || true

docker volume ls | grep ets_prod
```

Refresh code:

```bash
cd /opt/aca/infra && git pull
cd /opt/aca/repos/ets_admissions && git pull
cd /opt/aca/repos/ets_students && git pull
```

Keep existing `compose/prod/.env` unless you want new secrets (re-run `bootstrap-host.sh` only if `.env` was deleted).

Repeat **Phase 1** from step 4 (`pull` + `up -d` + logs).

---

## Phase 3 — Update compose/scripts only (keep prod data)

```bash
cd /opt/aca/infra
git pull

cd /opt/aca/infra/compose/prod
docker compose --env-file .env pull
docker compose --env-file .env up -d
docker compose --env-file .env ps -a
```

Do **not** remove Docker volumes unless you intend to wipe prod.

---

## Phase 4 — Day-2 operations

From `/opt/aca/infra`:

| Task | Command |
|------|---------|
| Deploy custom app changes | `./scripts/prod/deploy.sh` |
| Backup | `./scripts/prod/backup.sh` |
| Restore (destructive) | `./scripts/prod/restore.sh backups/<folder>` |

See [`prod-setup.md`](./prod-setup.md) for backup retention, cron, host migration, and Cloudflare Tunnel.

---

## Copy-paste: from zero to running prod

```bash
sudo mkdir -p /opt/aca && sudo chown $USER:$USER /opt/aca

cd /opt/aca
git clone https://github.com/kAIzenEd/erp-platform-infra.git infra
mkdir -p /opt/aca/repos
git clone https://github.com/kAIzenEd/ets_admissions.git /opt/aca/repos/ets_admissions
git clone https://github.com/kAIzenEd/ets_students.git   /opt/aca/repos/ets_students

/opt/aca/infra/scripts/prod/bootstrap-host.sh

cd /opt/aca/infra/compose/prod
docker compose --env-file .env pull
docker compose --env-file .env up -d
docker compose --env-file .env logs -f configurator
docker compose --env-file .env logs -f create-site
docker compose --env-file .env ps -a
curl -s -H "Host: erp.aca.local" http://127.0.0.1:8080/api/method/ping
```

---

## Troubleshooting

| Symptom | Likely cause | What to do |
|---------|----------------|------------|
| `No module named 'ets_admissions'` | Custom apps not pip-installed in shared env | Ensure `compose/prod/compose.yml` includes `bench-env` volume and configurator `pip install` (current `main`). Wipe volumes and reinstall (Phase 2). |
| `1045 Access denied` for site DB user | `sites` volume from old run, `db` volume new (or `.env` password changed) | Phase 2 full reset — remove **both** `ets_prod_sites` and `ets_prod_db_data`. |
| `volume is in use` on `docker volume rm` | Leftover `docker compose run` container | `docker rm -f prod-configurator-run-*` (or id from `docker network inspect ets_prod_network`), then retry volume rm. |
| `service "configurator" didn't complete` | Missing `/opt/aca/repos/ets_*` or empty clone | Re-clone apps (Phase 1 step 2). |
| `service "create-site" didn't complete` | See `docker compose logs create-site` | Fix configurator/apps first; Phase 2 reset if DB/site mismatch. |
| Broken UI / missing CSS | Assets not built | `docker compose exec backend bench build --force` then restart frontend/backend (see `prod-setup.md`). |
| Network `ets_prod_network` still in use on `down` | Another container attached | `docker compose down --remove-orphans`; remove stray containers (Phase 2). |

### Do not

- Run `docker compose run ... configurator` for normal installs — use `up -d` so the stack-managed configurator runs once. Manual `run` containers can lock volumes.
- Change `DB_ROOT_PASSWORD` in `.env` without wiping `ets_prod_db_data` and `ets_prod_sites` together.
- Use `http://localhost` without `:8080` — prod listens on **port 8080**.

---

## Compose requirements (on `main`)

Prod install expects `compose/prod/compose.yml` to:

1. Mount named volume `bench-env` at `/home/frappe/frappe-bench/env` on all Frappe services.
2. Run `./env/bin/pip install -e apps/ets_admissions -e apps/ets_students` in **configurator** (and create-site as a safety net).
3. Write `sites/apps.txt` with `frappe`, `erpnext`, `ets_admissions`, `ets_students` (not `ls -1 apps` alone).

---

## Next: dev stack

Dev uses the same compose pattern under `compose/dev` with:

- `SITE_NAME=frontend`
- `WEB_PORT=8081`
- `STACK_NAME=ets_dev`
- Restore from Mac backup under `/opt/aca/dev-backup/`

See future runbook `ubuntu-dev-install.md` (to be added).
