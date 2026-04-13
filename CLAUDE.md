# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Homelab monorepo for a 2-VM home network infrastructure (LAN 192.168.1.0/24). Each directory corresponds to a separate VM and is distributed via git sparse checkout — VMs only clone their own subdirectory.

- **vm-db-01** (192.168.1.51) — PostgreSQL 16.4 + Vaultwarden 1.32.5 + pgAdmin 8.12
- **vm-proxy-01** (192.168.1.50) — dnsmasq (split-DNS/DHCP) + Nginx Proxy Manager (reverse proxy + SSL)

Remote: `https://github.com/GVMainG/homelab.git`, branch: `main`

## Deployment

Each VM uses sparse checkout to pull only its directory:

```bash
git clone --no-checkout --filter=blob:none https://github.com/GVMainG/homelab.git
cd homelab
git sparse-checkout init --cone
git sparse-checkout set vm-db-01   # or vm-proxy-01
git checkout main
```

After cloning, copy `.env.example` to `.env`, fill in secrets, then run the deploy script.

### vm-db-01

```bash
cp .env.example .env
# Edit .env with actual passwords
bash deploy.sh          # idempotent — safe to re-run
bash backup.sh          # manual PostgreSQL backup (30-day rotation)
bash sync.sh            # pull latest code from git
```

### vm-proxy-01

```bash
sudo bash deploy-dnsmasq.sh    # requires root; idempotent
bash sync.sh                   # pull latest code from git
docker compose up -d           # start Nginx Proxy Manager
```

## Code Conventions

- **Bash**: all scripts start with `set -euo pipefail`; use `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` for paths; validate dependencies at script entry
- **Docker Compose**: always v2 syntax (`docker compose`, not `docker-compose`); pin image versions to specific tags (exception: `nginx-proxy-manager:latest` is noted as non-ideal)
- **Secrets**: stored in `.env` (git-ignored); `.env.example` is the template — keep it updated when adding new variables
- **Idempotency**: deploy scripts must be safe to re-run without side effects

## Architecture

```
Internet
    │
    ▼
vm-proxy-01 (192.168.1.50)
  ├── dnsmasq: resolves *.host.loc → 192.168.1.50; upstream DNS 1.1.1.1 / 8.8.8.8
  └── Nginx Proxy Manager: SSL termination + reverse proxy to LAN services

vm-db-01 (192.168.1.51)
  ├── PostgreSQL: bound to 127.0.0.1 only (localhost)
  ├── Vaultwarden: password manager, exposed to LAN
  └── pgAdmin: DB admin UI, exposed to LAN
       (all three on Docker network: db-internal)
```

Split-DNS: all `*.host.loc` domains are routed to 192.168.1.50 via dnsmasq config in `vm-proxy-01/configs/dnsmasq/01-split-dns.conf`.

## Documentation

Full project documentation (in Russian) is in [QWEN.md](QWEN.md), covering architecture decisions, backup/restore procedures, and security notes.
