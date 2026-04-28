# Compose in this repository

The files under `compose/` and `env/` were started as an **infrastructure sketch** for future Staging/Production-style deployments.

## They are not the supported local Dev stack for ERPNext

For **local development** (correct UI, stable DB bootstrap, workers, nginx, assets):

Use **[frappe/frappe_docker](https://github.com/frappe/frappe_docker)** and follow:

- [docs/dev-setup-frappe-docker.md](../docs/dev-setup-frappe-docker.md)

## Why

Upstream ERPNext in Docker is validated as a **multi-service** layout (configurator, backend, frontend/nginx, websocket, Redis, MariaDB, workers, scheduler). A minimal single-file compose with only `web` on port 8000 often causes:

- asset and routing issues in the browser,
- fragile first-time site creation,
- harder-to-debug DB credential mismatches with persistent volumes.

## When to evolve this folder

Reuse or replace this compose when you design **Staging/Prod** on Linux hosts, aligned with `manifests/*.release.yaml` and your promotion model.
