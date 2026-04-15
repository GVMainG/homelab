# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A homelab infrastructure monorepo for VMs running on a Proxmox VE host (LAN 192.168.1.0/24). Each VM uses **git sparse checkout** — it clones only its own subdirectory.

| VM | IP | Services |
| --- | --- | --- |
| `vm-db-01` | 192.168.1.36 | PostgreSQL 16, Vaultwarden, pgAdmin 4 |
| `vm-DevOps-01` | 192.168.1.XX | Dockhand (Docker management UI) |

## Network architecture

```
LAN       → vm-db-01:5432 (PostgreSQL, bound to 0.0.0.0)
            vm-db-01:8080 → Vaultwarden (password manager)
            vm-db-01:5050 → pgAdmin (PostgreSQL web UI)
            All three share isolated Docker network: db-net
```

No reverse proxy or SSL termination — services are accessed directly by LAN IP. No wildcard DNS; add entries to `/etc/hosts` or Windows `hosts` file as needed.

## Deploying / running services

```bash
# vm-db-01 — first deploy
cp .env.example .env   # fill in all CHANGE_ME values
bash sync.sh           # idempotent, sparse checkout

# Update from git
bash vm-db-01/sync.sh
docker compose pull && docker compose up -d

# Manual PostgreSQL backup
docker exec postgres pg_dumpall -U admin > /opt/homelab/backups/full-$(date +%Y%m%d-%H%M%S).sql
```

## Key Docker Compose operations

```bash
docker compose up -d --remove-orphans   # idempotent start/update
docker compose ps                        # check health status
docker compose logs -f <service>
docker compose pull && docker compose up -d   # update images
```

## Validating shell scripts before deploy

```bash
bash -n script.sh          # syntax check
shellcheck script.sh       # lint (apt install shellcheck)
```

## Initial sparse checkout (per VM)

```bash
git clone --filter=blob:none --sparse --branch main https://github.com/GVMainG/homelab.git
cd homelab
git sparse-checkout set vm-db-01
```

## PostgreSQL init-scripts

Scripts in `vm-db-01/init-scripts/` are mounted to `/docker-entrypoint-initdb.d` and **run only once — at the first PostgreSQL container initialization** (when the `postgres-data` volume is empty). Re-running `docker compose up` does not re-execute them. To re-run: stop the stack, remove the volume, then restart.

`01-init-vaultwarden-db.sql` creates the `vw_user` role, the `vaultwarden` database, and grants required privileges. It reads credentials from env vars using psql's `\getenv`.

## Bash script conventions

Every `.sh` file must start with:

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
```

- Guard all installs, config writes, and directory creation for idempotency
- Validate required commands and `.env` at script start, exit with stderr message on failure
- Always quote variable expansions; use `[[ ]]` over `[ ]`
- Scripts requiring root must check `$EUID` explicitly

## Docker Compose conventions

- Always use `docker compose` (v2, with space) — never `docker-compose`
- Pin all image versions (`postgres:16.4`) — known exceptions using `:latest`: `vaultwarden/server`, `dpage/pgadmin4` (no stable versioned releases), `jc21/nginx-proxy-manager`
- Every service needs a `healthcheck` block; use `depends_on: condition: service_healthy`
- Secrets only via `.env`; never hardcode credentials
- Every variable in `docker-compose.yml` must have a placeholder in `.env.example`
- PostgreSQL major upgrades (e.g., 16→17) require `pg_dumpall` backup first — swapping the image tag alone is not sufficient

## Docs directory

`docs/` contains infrastructure documentation written in Russian:
- `overview.md` — network diagram, VM table, service endpoints
- `services.md` — per-service reference (ports, volumes, env vars, healthchecks)
- `decisions.md` — architecture decision records (ADRs) explaining why things are the way they are
- `runbooks.md` — step-by-step operational procedures
- `troubleshooting.md` — known issues and fixes
- `changelog.md` — change log

Update the relevant doc file whenever you add a service, change a port, or make an architectural change.

## Proxmox conventions

- Snapshot before risky changes: `qm snapshot <vmid> YYYYMMDD-reason`
- SSH to VM: `ssh user-home@192.168.1.36`

## PowerShell (Windows workstation only)

Scripts must start with `#Requires -Version 7.0`, `Set-StrictMode -Version Latest`, `$ErrorActionPreference = 'Stop'`. Use full cmdlet names — no aliases (`ls`, `cat`, `%`).

## What NOT to do

- Never commit `.env` files or put real secrets in `.env.example` — use `CHANGE_ME` placeholders
- Never write a script that can delete `vm-db-01/backups/` without retention logic matching `backup.sh`
- Don't introduce new tools (`jq`, `yq`, etc.) without verifying they're installed on target VMs
