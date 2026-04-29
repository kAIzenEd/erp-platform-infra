# Dev setup: frappe_docker (single supported path)

Use the official **[frappe/frappe_docker](https://github.com/frappe/frappe_docker)** repository for all local ERPNext development. This avoids custom image/compose drift, DB password edge cases from hand-rolled MariaDB volumes, and broken UI from missing nginx/asset routing.

## Prerequisites

- Docker Desktop (current version).
- Git.
- Apple Silicon: prefer multi-arch images; if builds fail, see [Platform notes](https://github.com/frappe/frappe_docker/blob/main/docs/getting-started.md#platform-notes) in upstream docs (for example `DOCKER_DEFAULT_PLATFORM`).

## Where to clone

Clone **next to** your `ets-repos` tree (or any fixed path). Example:

```bash
mkdir -p ~/dev
cd ~/dev
git clone https://github.com/frappe/frappe_docker.git
cd frappe_docker
```

Do **not** nest `frappe_docker` inside `erp-platform-infra` unless you add it to `.gitignore` and accept the extra noise.

---

## Path A — Quick test (fastest way to a correct UI)

Best for: proving Docker + ERPNext + browser UI before you invest in full dev tooling.

From inside `frappe_docker`:

```bash
docker compose -f pwd.yml up -d
```

Watch site creation until it finishes (can take several minutes):

```bash
docker compose -f pwd.yml logs -f create-site
```

When `create-site` completes successfully:

- Open **http://localhost:8080** (upstream default for pwd).
- Login: **Administrator** / **admin** (unless you changed defaults in that compose file).

### Day-1 health verification commands

Run these after startup to validate baseline runtime health:

```bash
cd ~/dev/frappe_docker
docker compose -f pwd.yml ps
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8080
curl -s http://localhost:8080/api/method/ping
```

Expected:

- Frontend HTTP status `200`
- Ping response `{"message":"pong"}`
- `scheduler`, `queue-short`, and `queue-long` services are `Up` in `docker compose ... ps`

### If the UI looks wrong

1. Use **exactly** `http://localhost:8080` first — not a random host name unless the site was created for that host.
2. Hard refresh or try a private window (stale asset cache).
3. Check logs: `docker compose -f pwd.yml logs -f frontend` and `backend`.

### Clean reset (pwd only)

When you only had test data and want a completely clean run:

```bash
cd ~/dev/frappe_docker
docker compose -f pwd.yml down -v
docker compose -f pwd.yml up -d
```

Then watch `create-site` logs again.

---

## Path B — Full development (custom apps, hot reload, VS Code)

Best for: day-to-day work on `ets_*` apps with bench and a proper bench tree.

Follow upstream in order:

1. [Getting started — Full development setup](https://github.com/frappe/frappe_docker/blob/main/docs/getting-started.md#full-development-setup)  
   - Copy devcontainer example, reopen in VS Code Dev Containers, run `installer.py` as documented.
2. [Development — bench and new site](https://github.com/frappe/frappe_docker/blob/main/docs/05-development/01-development.md)  
   - Site names for local browser should follow upstream guidance (for example `*.localhost`).

Typical patterns after a site exists:

```bash
# Inside the environment where bench is available (container or devcontainer)
bench list-apps
bench --site <your-site> set-config developer_mode 1
bench --site <your-site> clear-cache
bench build
bench migrate
```

Install ERPNext on the site when the installer did not already:

```bash
bench --site <your-site> install-app erpnext
```

Link your GitHub `ets_*` apps (replace URL and paths with yours):

```bash
cd ~/dev/frappe_docker/development/frappe-bench
bench get-app https://github.com/kAIzenEd/ets_admissions.git
bench --site <your-site> install-app ets_admissions
```

---

## Wiring this repo to Dev (optional)

- Keep **application code** in `~/ets-repos/ets_*` and use `bench get-app` with your repo URLs, **or** bind-mount apps per upstream devcontainer docs.
- Keep **infra policy, manifests, runbooks** in `erp-platform-infra`. Dev runtime lives in `frappe_docker`; this repo stays the contract for how Staging/Prod will be promoted later.

---

## Stop using the old minimal compose in erp-platform-infra

If you started containers from `erp-platform-infra/compose/`:

```bash
cd ~/ets-repos/erp-platform-infra
docker compose --env-file env/dev/.env \
  -f compose/common/docker-compose.base.yml \
  -f compose/docker-compose.dev.yml \
  down
```

Add `-v` only if you intend to wipe that experiment’s volumes.

---

## Troubleshooting

| Symptom | Likely cause | What to do |
|--------|----------------|------------|
| DB access denied after editing `.env` | MariaDB volume initialized with older passwords | `down -v` on that stack, or align passwords inside DB with `.env`. |
| Broken layout / missing CSS | Wrong host vs site name, or missing `frontend` nginx | Use **Path A** or full frappe_docker stack; avoid bare `web:8000` only. |
| Port already in use | Old compose still running | `docker ps`, stop conflicting stack. |

When in doubt, use **Path A (`pwd.yml`)** to validate Docker and UI, then move to **Path B** for real development.
