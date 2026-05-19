# PROD setup runbook — ETS ERPNext on a Linux host

Zero-to-running guide for standing up the production ERPNext stack on the college Linux server, plus the day-2 deploy + backup + restore procedures and the host-migration playbook.

> **Ubuntu VM quick path:** for a copy-paste command sequence (validated on Ubuntu), see [`ubuntu-prod-install.md`](./ubuntu-prod-install.md).

> **Audience:** the developer doing the install (you), and anyone the college appoints later to keep the stack healthy.
>
> **Scope:** LAN-only access for staff Desk, with optional Cloudflare Tunnel so the public website on Railway can still submit applications into PROD.

---

## Architecture in one picture

```
Public user
   │
   ▼  https://aca-erpnext-production.up.railway.app/admissions/application-form
┌────────────────────────────┐
│ Next.js website (Railway)  │   stays public
└─────────────┬──────────────┘
              │ HTTPS + bearer token
              ▼
┌────────────────────────────┐
│ API gateway (Railway)      │   stays public
└─────────────┬──────────────┘
              │ HTTPS via Cloudflare Tunnel (outbound from college)
              ▼
┌────────────────────────────┐
│ ERPNext on college LAN     │   never exposed inbound to the internet
│ (Docker on Linux server)   │   staff hit http://erp.aca.local:8080
└────────────────────────────┘
```

Everything in this runbook concerns the bottom box.

---

## 0. Prerequisites

On the **college Linux server** (any modern distro — Ubuntu 22.04/24.04 LTS, Debian 12, RHEL 9, Rocky 9 all work):

- Root or `sudo` access during initial install.
- Outbound internet for `docker pull`, `git clone`, and (optionally) `cloudflared`.
- ≥ 8 GB RAM, ≥ 30 GB free disk (`/var/lib/docker` is where everything will live by default).
- A user account you'll run Docker as (call it `erp` below). Adding it to the `docker` group lets it run `docker` without `sudo`.

On **your Mac** (this is where you push GitHub commits from):

- The custom-app repos already cloned under `~/ets-repos/`:
  - `ets_admissions`
  - `ets_students`
- Push access to those GitHub repos (you already have this).

---

## 1. Install Docker and the Compose plugin on the server

Run **one** of the following blocks on the server depending on the OS:

### Ubuntu / Debian
```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
# Reopen the SSH session for the docker group to take effect, or:
newgrp docker
```

### RHEL / Rocky / Alma 9
```bash
sudo dnf install -y dnf-plugins-core
sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
newgrp docker
```

Verify:
```bash
docker --version          # must show 24.x or newer
docker compose version    # must NOT be "docker-compose" (old) — must be "docker compose" (plugin)
docker run --rm hello-world
```

---

## 2. Lay out the host filesystem

The compose and scripts expect this structure:

```
/opt/aca/
├── infra/                ← this repo (erp-platform-infra)
├── repos/                ← custom app source (bind-mounted into containers)
│   ├── ets_admissions/
│   └── ets_students/
└── backups/              ← landing zone for backup.sh archives
```

```bash
sudo mkdir -p /opt/aca
sudo chown $USER:$USER /opt/aca
cd /opt/aca
git clone https://github.com/kAIzenEd/erp-platform-infra.git infra
# bootstrap-host.sh will git-clone the custom apps for you in the next step
```

---

## 3. Run the bootstrap script

The script verifies Docker, creates `repos/` and `backups/`, clones the custom apps if missing, generates a fresh `.env` with strong random secrets, and pulls the Docker images.

```bash
/opt/aca/infra/scripts/prod/bootstrap-host.sh
```

It will print the generated `DB_ROOT_PASSWORD` and `ADMIN_PASSWORD`. **Save these to a password manager immediately** — they're in `/opt/aca/infra/compose/prod/.env` (mode 600) but you'll need the admin password to log in.

Optional env overrides on a custom site name:
```bash
SITE_NAME=erp.aca.local WEB_PORT=8080 /opt/aca/infra/scripts/prod/bootstrap-host.sh
```

---

## 4. Bring the stack up

```bash
cd /opt/aca/infra/compose/prod
docker compose --env-file .env up -d
docker compose --env-file .env logs -f create-site   # tail until it exits cleanly
```

First boot takes 3–5 minutes because `create-site` runs `bench new-site` which:
1. Creates the MariaDB database
2. Bootstraps the Frappe + ERPNext schema
3. Installs `ets_admissions` and `ets_students` onto the site
4. Sets the default site

When `create-site` exits with code 0, the site exists.

```bash
docker compose --env-file .env ps   # all "Up (healthy)" or "Exited (0)" for one-shots
```

---

## 5. Reach the new site

The site responds to whatever Host header you set as `SITE_NAME` (default `erp.aca.local`). Browsers send the Host header from the URL bar, so you need each staff workstation's `/etc/hosts` to resolve that name to the server's LAN IP, **or** an internal DNS A record.

Quickest option for testing — add to `/etc/hosts` on each staff Mac:
```
192.168.1.50    erp.aca.local
```

Then visit `http://erp.aca.local:8080/` and log in as:
- **Email:** `Administrator`
- **Password:** the `ADMIN_PASSWORD` from `.env`

Inside Desk, immediately:
1. Create real user accounts (Registrar, Secretary, etc.) and assign roles.
2. Change `Administrator`'s password to something fresh and rotate the original out of your password manager.

---

## 6. Day-2 deploy procedure

Whenever you push code changes to `ets_admissions` or `ets_students`:

**On your Mac (development):**
```bash
cd ~/ets-repos/ets_admissions
git add . && git commit -m "your change" && git push
```

**On the server (deploy):**
```bash
cd /opt/aca/infra
./scripts/prod/deploy.sh
```

That's the whole loop. The script does:
1. `git pull` in `/opt/aca/repos/ets_admissions` (and `ets_students`)
2. `docker compose exec backend bench --site $SITE_NAME migrate`
3. `bench clear-cache`
4. `docker compose restart backend frontend websocket queue-short queue-long scheduler`

If you want a no-pull deploy (you already `git fetch`'d on the server):
```bash
./scripts/prod/deploy.sh --skip-pull
```

---

## 7. Backup procedure

```bash
cd /opt/aca/infra
./scripts/prod/backup.sh                # routine — keeps 14 most recent
./scripts/prod/backup.sh --label cutover-pre   # named snapshot, kept indefinitely
```

Backups land in `/opt/aca/infra/backups/<timestamp>/` and contain four files:
- `*-database.sql.gz` — DB dump
- `*-files.tar` — public files (browser-accessible attachments)
- `*-private-files.tar` — private files (sensitive attachments — applicant photos, certificates, etc.)
- `*-site_config_backup.json` — site config snapshot

For automated nightly backups, cron one line:
```bash
sudo crontab -e
# 0 2 * * *  /opt/aca/infra/scripts/prod/backup.sh >> /var/log/aca-backup.log 2>&1
```

To copy a backup off-server for safekeeping:
```bash
# from your Mac:
rsync -avz erp@<server>:/opt/aca/infra/backups/20260512T020000Z/ ~/aca-backups/20260512T020000Z/
```

---

## 8. Restore procedure (same host)

Used when you need to roll back a bad deploy or reload from a snapshot.

```bash
cd /opt/aca/infra
./scripts/prod/restore.sh backups/cutover-pre
```

The script asks you to type the site name to confirm — this prevents accidental restores.

---

## 9. Host migration — server A → server B

This is the procedure you'd use to:
- Move PROD from your Mac to the college server (first cutover)
- Move PROD between college servers (hardware refresh)
- Move from a temporary host to a permanent one

**Source host (server A):**
```bash
cd /opt/aca/infra        # or wherever infra is checked out
./scripts/prod/backup.sh --label cutover
```

**Network transfer:**
```bash
# Run on server A or any machine that can reach both
rsync -avz /opt/aca/infra/backups/cutover/ user@server-b:/opt/aca/infra/backups/cutover/
```

**Target host (server B):** Fresh OS, no Docker yet. Follow steps 1–5 of this runbook. The stack will boot with an *empty* site at the end of step 5.

**Target host (server B):**
```bash
cd /opt/aca/infra
./scripts/prod/restore.sh backups/cutover
```

Smoke check:
```bash
curl -fsS http://localhost:8080/api/method/ping || echo "FAIL"
```

Then update DNS / `/etc/hosts` entries so `erp.aca.local` resolves to server B's IP, and you're done.

---

## 10. (Optional) Cloudflare Tunnel — let Railway gateway reach the LAN

If the public website on Railway needs to submit applications into the college PROD instance, install `cloudflared` on the server as an outbound-only tunnel:

```bash
# Ubuntu/Debian
curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb -o /tmp/cloudflared.deb
sudo dpkg -i /tmp/cloudflared.deb

# Login (one-time, opens a browser)
cloudflared tunnel login

# Create a named tunnel
cloudflared tunnel create aca-erpnext

# Map the tunnel to a hostname (e.g., erp-internal.acaindia.org, on a domain in Cloudflare)
cloudflared tunnel route dns aca-erpnext erp-internal.acaindia.org

# Write a config that routes traffic to the local frontend container
sudo tee /etc/cloudflared/config.yml <<EOF
tunnel: aca-erpnext
credentials-file: /home/$USER/.cloudflared/<tunnel-id>.json
ingress:
  - hostname: erp-internal.acaindia.org
    service: http://localhost:8080
    originRequest:
      httpHostHeader: erp.aca.local
  - service: http_status:404
EOF

# Run as a service
sudo cloudflared service install
sudo systemctl enable --now cloudflared
```

Then in Railway gateway env vars:
```
ERPNEXT_URL=https://erp-internal.acaindia.org
```

The tunnel is outbound-only — no inbound firewall holes needed.

---

## 11. Troubleshooting

| Symptom | First thing to check |
|---|---|
| `create-site` exits non-zero | `docker compose --env-file .env logs create-site` — usually a DB credential mismatch in `.env`, OR a custom app fails to install. Check the traceback. |
| Site returns 502 / "ERPNext is not running" | `docker compose --env-file .env ps` — is `backend` "Up (healthy)"? If not, check `logs backend`. |
| Browser shows raw HTML / broken CSS | Wrong Host header. The URL must resolve to the SITE_NAME you set, not the server IP. Edit `/etc/hosts` or DNS. |
| `bench migrate` complains about a missing module | The host repo is missing a file or wrong branch. `git status` in `$REPOS_ROOT/ets_admissions`. |
| Backup script fails with "no such file" | `bench backup` ran but the path in the container differs. Check `docker exec ${STACK_NAME}_backend ls sites/$SITE_NAME/private/backups/`. |
| Restore fails with foreign-key errors | DB versions don't match. The `FRAPPE_IMAGE` tag on the new host MUST match the source host's tag at the time of backup. |

---

## 12. Where this lives

| Asset | Path |
|---|---|
| Compose stack | `compose/prod/compose.yml` |
| Env template | `compose/prod/.env.example` |
| Bootstrap script | `scripts/prod/bootstrap-host.sh` |
| Deploy script | `scripts/prod/deploy.sh` |
| Backup script | `scripts/prod/backup.sh` |
| Restore script | `scripts/prod/restore.sh` |
| This runbook | `docs/runbooks/prod-setup.md` |
