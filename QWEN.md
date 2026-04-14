# Homelab Infrastructure Monorepo

## Overview

This repository contains infrastructure-as-code for a homelab environment running on two Proxmox VE virtual machines within a local network (192.168.1.0/24). Each VM manages its own configuration through **git sparse checkout**, cloning only its specific subdirectory.

### Virtual Machines

| VM | IP | Services |
|---|---|---|
| `vm-db-02` | 192.168.1.52 | PostgreSQL 16, Vaultwarden (password manager), pgAdmin |
| `vm-proxy-02` | 192.168.1.51 | dnsmasq (split-DNS), Nginx Proxy Manager (reverse proxy with SSL termination) |

**Note:** This repository also contains configurations for `vm-db-01` and `vm-proxy-01` (the original VMs), following the same patterns.

## Architecture

```
Internet → vm-proxy-02:443 (NPM, SSL termination) → internal services
LAN       → dnsmasq:53  (*.home.loc → proxy VM IP)
vm-db-02  → PostgreSQL bound to localhost only
            Vaultwarden and pgAdmin accessible on LAN
            All services share isolated Docker network: db-net
```

## Directory Structure

```
homelab/
├── .gitignore              # Excludes .env files, SSL certs, backups
├── CLAUDE.md               # Comprehensive project guidelines
├── QWEN.md                 # This file
├── vm-db-01/               # Database VM #1 (PostgreSQL, Vaultwarden, pgAdmin)
├── vm-db-02/               # Database VM #2 (PostgreSQL, Vaultwarden, pgAdmin)
│   ├── docker-compose.yml  # Service definitions
│   ├── sync.sh             # Git sparse checkout sync script
│   ├── .env.example        # Environment variable template
│   └── init-scripts/       # PostgreSQL initialization scripts
│       └── 01-init-vaultwarden-db.sql
└── vm-proxy-02/            # Proxy VM #2 (Nginx Proxy Manager, dnsmasq)
    ├── docker-compose.yml  # Nginx Proxy Manager service
    ├── sync.sh             # Git sparse checkout sync script
    ├── .env.example        # Environment variable template
    └── ssl/
        └── generate-ssl.sh # Wildcard SSL certificate generator
```

## Key Technologies

- **Docker Compose** (v2) — container orchestration
- **PostgreSQL 16** — relational database
- **Vaultwarden** — lightweight Bitwarden-compatible password manager
- **pgAdmin 4** — PostgreSQL web administration interface
- **Nginx Proxy Manager** — reverse proxy with Let's Encrypt SSL
- **dnsmasq** — DNS server with split-DNS functionality
- **OpenSSL** — wildcard certificate generation
- **Proxmox VE** — hypervisor hosting the VMs

## Deployment Guide

### Initial Setup (Per VM)

#### Sparse Checkout

Each VM clones only its own subdirectory:

```bash
# On the target VM
git clone --filter=blob:none --sparse --branch main https://github.com/GVMainG/homelab.git
cd homelab
git sparse-checkout set vm-db-02   # or vm-proxy-02
```

#### Using sync.sh (Recommended)

Both VM directories include a `sync.sh` script that automates sparse checkout:

```bash
# vm-db-02
sudo bash vm-db-02/sync.sh

# vm-proxy-02
sudo bash vm-proxy-02/sync.sh
```

### vm-db-02 (Database VM)

```bash
cd /opt/homelab/vm-db-02

# 1. Create environment file
cp .env.example .env
# Edit .env and replace all CHANGE_ME values

# 2. Deploy services
docker compose up -d --remove-orphans

# 3. Verify
docker compose ps    # check all services are healthy
docker compose logs -f <service>
```

### vm-proxy-02 (Proxy VM)

```bash
cd /opt/homelab/vm-proxy-02

# 1. Create environment file
cp .env.example .env
# Edit .env with admin credentials

# 2. Install dnsmasq (if not already done)
# (Manual setup required — see CLAUDE.md for Proxmox conventions)

# 3. Generate SSL certificates (optional, for self-signed)
bash ssl/generate-ssl.sh

# 4. Deploy Nginx Proxy Manager
docker compose up -d --remove-orphans
```

### Updating Services

```bash
# Pull latest config from git
bash sync.sh

# Update Docker images and restart
docker compose pull && docker compose up -d
```

## Docker Compose Operations

```bash
# Start/update services (idempotent)
docker compose up -d --remove-orphans

# Check service health
docker compose ps

# View logs
docker compose logs -f <service>

# Update images
docker compose pull && docker compose up -d

# Stop services
docker compose down
```

## Conventions

### Bash Scripts

All `.sh` files must start with:

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
```

- Guard all installs, config writes, and directory creation for idempotency
- Validate required commands and `.env` at script start
- Always quote variable expansions; use `[[ ]]` over `[ ]`
- Scripts requiring root must check `$EUID` explicitly
- Validate with `bash -n script.sh` and `shellcheck script.sh` before deploy

### Docker Compose

- Always use `docker compose` (v2, with space) — never `docker-compose`
- Pin all image versions (e.g., `postgres:16`) — exception: `jc21/nginx-proxy-manager:latest`
- Every service must have a `healthcheck` block
- Use `depends_on: condition: service_healthy` for service ordering
- Secrets only via `.env`; never hardcode credentials
- Every variable in `docker-compose.yml` must have a placeholder in `.env.example`

### Security

- **Never commit `.env` files** — they are in `.gitignore`
- **Never put real secrets in `.env.example`** — use `CHANGE_ME` placeholders
- SSL certificates are excluded from git (see `.gitignore`)
- PostgreSQL backups excluded from git (stored locally on VM)

## PostgreSQL Database Initialization

The `init-scripts/01-init-vaultwarden-db.sql` script runs automatically on first PostgreSQL startup via `docker-entrypoint-initdb.d`. It:

1. Creates a dedicated database user for Vaultwarden
2. Creates the Vaultwarden database
3. Grants appropriate privileges

Uses PostgreSQL `\getenv` to read credentials from environment variables.

## SSL Certificate Management

The `vm-proxy-02/ssl/generate-ssl.sh` script generates:

- Root CA (`ca.key`, `ca.crt`)
- Wildcard certificate for `*.home.loc` (10-year validity)

Output files are stored in `ssl/certs/` (excluded from git).

## Backup Strategy

PostgreSQL backups are stored locally on the VM and excluded from git. Backup scripts should include retention logic (default: 30 days rotation).

## Proxmox Best Practices

- Snapshot VMs before risky changes: `qm snapshot <vmid> YYYYMMDD-reason`
- SSH to VMs: `ssh user@192.168.1.XX`
- When adding a new VM: create subdirectory with `deploy.sh`, `sync.sh`, `.env.example`, `docker-compose.yml`
- Add DNS entries to dnsmasq config on proxy VM

## Repository

- **Remote:** https://github.com/GVMainG/homelab.git
- **Branch:** main
- **Clone strategy:** sparse checkout (blobless filter)
