# Dev compose — ETS ERPNext (port 8081)

Same stack as [`../prod/`](../prod/) (shared `bench-env`, bind-mounted custom apps). Isolated by:

- `STACK_NAME=ets_dev` → separate containers, volumes, network
- `SITE_NAME=frontend` → matches Mac `frappe_docker` / pwd.yml backups
- `WEB_PORT=8081` → prod stays on 8080

**Runbook:** [`docs/runbooks/ubuntu-dev-install.md`](../../docs/runbooks/ubuntu-dev-install.md)
