# erp-platform-infra

Infrastructure and deployment assets for the ETS ERPNext program.

## Supported paths (important)

| Environment | Source of truth | Purpose |
|---------------|-----------------|---------|
| **Local Dev (ERPNext + correct UI)** | **[frappe/frappe_docker](https://github.com/frappe/frappe_docker)** | Run ERPNext the way upstream tests and documents it. |
| **Staging / Production (later)** | This repo (`compose/`, `manifests/`, `scripts/`) | Portable compose, manifests, runbooks — evolve after Dev is stable. |

**Local ERPNext development must not use the minimal `compose/` stack in this repo** for day-to-day work. That stack was an early scaffold; it lacks the full service set (for example nginx `frontend`, configurator, websocket) that upstream uses, which commonly leads to broken assets and fragile DB bootstrap.

Follow the single canonical guide:

- **[docs/dev-setup-frappe-docker.md](docs/dev-setup-frappe-docker.md)**

## Quick start (Dev only)

1. Install Docker Desktop.
2. Clone `frappe_docker` **outside** this repo (sibling directory is fine), for example `~/dev/frappe_docker`.
3. Open [docs/dev-setup-frappe-docker.md](docs/dev-setup-frappe-docker.md) and run the **Quick test** or **Full development** path — pick one and stick to it.

## Day-1 runbook links

- Dev setup and runtime commands: [docs/dev-setup-frappe-docker.md](docs/dev-setup-frappe-docker.md)
- Operational checks and reset flow:
  - [docs/runbooks/cutover-checklist.md](docs/runbooks/cutover-checklist.md)
  - [docs/runbooks/rollback-checklist.md](docs/runbooks/rollback-checklist.md)

## Repo layout

- `compose/` — Compose experiments for non-Dev environments (see [compose/README.md](compose/README.md)). **Not** the supported local ERPNext dev stack.
- `env/` — Environment templates for future Staging/Prod workflows.
- `manifests/` — Release manifests (pinned versions per environment).
- `scripts/` — Deploy and smoke helpers.
- `docs/runbooks/` — Operational checklists.

## If you previously ran the minimal Dev compose here

1. Stop and remove those containers so ports do not clash with `frappe_docker` (often `8080` on pwd).
2. Do **not** delete volumes until you know you no longer need that data; for a clean restart of local experiments, removing the project volumes is acceptable on a dev machine only.

## References

- [Frappe Docker — Getting Started](https://github.com/frappe/frappe_docker/blob/main/docs/getting-started.md)
- [Development guide](https://github.com/frappe/frappe_docker/blob/main/docs/05-development/01-development.md)
