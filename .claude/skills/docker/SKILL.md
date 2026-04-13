---
name: docker
description: Use when working with Docker or Docker Compose in this homelab — writing or editing docker-compose.yml files, managing containers on vm-db-01 or vm-proxy-01, debugging services, working with volumes/networks/healthchecks, or handling image updates. Triggers on requests involving docker compose, Dockerfile, container logs, or service restarts.
---

# Docker & Docker Compose

Both VMs run services via Docker Compose v2. No Kubernetes, no Swarm — plain `docker compose`.

## Project layout

```
vm-db-01/
  docker-compose.yml    # postgres, vaultwarden, pgadmin
  .env                  # secrets (git-ignored)
  .env.example          # template — keep in sync with .env

vm-proxy-01/
  docker-compose.yml    # nginx-proxy-manager
  .env
  .env.example
```

## Core conventions

- **Always v2 syntax**: `docker compose` (with a space), never `docker-compose`
- **Pin image versions**: `postgres:16.4`, `vaultwarden/server:1.32.5`, `dpage/pgadmin4:8.12` — no `latest` tags except where noted as a known compromise (`jc21/nginx-proxy-manager:latest`)
- **Secrets via `.env`**: reference with `${VAR_NAME}` in compose files; never hardcode credentials
- **Internal network**: services that talk to each other share a named network (`db-internal` on vm-db-01); don't expose ports between services unless necessary
- **Healthchecks**: every service must have a `healthcheck` block so `depends_on: condition: service_healthy` works

## Common operations

```bash
# Start all services (detached)
docker compose up -d

# Restart a single service
docker compose restart vaultwarden

# View logs (follow)
docker compose logs -f postgres

# View logs for last 100 lines
docker compose logs --tail=100 pgadmin

# Pull updated images then recreate
docker compose pull
docker compose up -d

# Stop everything
docker compose down

# Stop and remove volumes (DESTRUCTIVE — data loss)
docker compose down -v
```

## Checking service status

```bash
# Show running containers + health status
docker compose ps

# Inspect a specific container
docker inspect vm-db-01-postgres-1

# Check resource usage
docker stats --no-stream
```

## Executing commands inside containers

```bash
# Open shell in running container
docker compose exec postgres bash
docker compose exec vaultwarden sh    # Alpine-based, no bash

# Run one-off command
docker compose exec postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"

# Run as specific user
docker compose exec --user root postgres bash
```

## Volumes

```bash
# List volumes
docker volume ls

# Inspect volume (find mount path on host)
docker volume inspect vm-db-01_postgres-data

# Backup a named volume
docker run --rm \
  -v vm-db-01_postgres-data:/data \
  -v $(pwd):/backup \
  alpine tar czf /backup/postgres-data-backup.tar.gz /data
```

Volume naming in docker compose: `<project-name>_<volume-name>`. Project name defaults to the directory name unless set with `--project-name` or `COMPOSE_PROJECT_NAME` in `.env`.

## Networks

```bash
# List networks
docker network ls

# Inspect network (see connected containers + IPs)
docker network inspect db-internal
```

Rule: services that don't need to communicate directly should not share a network. PostgreSQL in vm-db-01 is bound to `127.0.0.1` and only accessible inside the `db-internal` Docker network — it has no published port.

## Writing docker-compose.yml

Follow the existing pattern in `vm-db-01/docker-compose.yml`:

```yaml
services:
  example-service:
    image: vendor/image:1.2.3          # pinned version — no latest
    container_name: example-service    # explicit name for predictable log/exec references
    restart: unless-stopped
    env_file: .env                     # load all vars from .env
    environment:
      SPECIFIC_VAR: ${SPECIFIC_VAR}    # or inline specific overrides
    volumes:
      - example-data:/data/dir
    networks:
      - db-internal
    depends_on:
      postgres:
        condition: service_healthy     # wait for healthcheck, not just started
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:PORT/health"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s

volumes:
  example-data:

networks:
  db-internal:
    driver: bridge
```

Healthcheck `test` patterns by service type:

```yaml
# PostgreSQL
test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]

# HTTP service with /health endpoint
test: ["CMD", "curl", "-f", "http://localhost:80/"]

# Generic TCP port check
test: ["CMD-SHELL", "nc -z localhost 3000 || exit 1"]
```

## Updating image versions

1. Edit `image:` tag in `docker-compose.yml` (bump to new pinned version)
2. Pull new image: `docker compose pull <service>`
3. Recreate container: `docker compose up -d <service>`
4. Verify health: `docker compose ps` — wait for `(healthy)`
5. Check logs: `docker compose logs --tail=50 <service>`

For PostgreSQL major version upgrades (e.g., 16 → 17): take a `pg_dumpall` backup first, then upgrade — in-place major upgrades require `pg_upgrade` which is not covered by just swapping the image tag.

## Debugging container failures

```bash
# Container exits immediately — check exit code and last logs
docker compose logs <service>
docker inspect <container> --format='{{.State.ExitCode}}'

# Container stuck in "starting" (healthcheck failing)
docker compose exec <service> <healthcheck-command>

# Permission errors on mounted volumes
docker compose exec <service> ls -la /data
# Fix: set correct user in compose or chown on host

# Environment variable not set
docker compose exec <service> env | grep VAR_NAME
```

## Idempotent deploy pattern

The existing `deploy.sh` scripts use this pattern — preserve it when adding new services:

```bash
# Start or update without downtime for unchanged services
docker compose up -d --remove-orphans

# Verify all services healthy before returning success
docker compose ps | grep -v "healthy" | grep -v "NAME" && {
    echo "ERROR: some services not healthy" >&2
    docker compose ps
    exit 1
}
```

## .env.example maintenance

Every variable referenced in `docker-compose.yml` must have a corresponding entry in `.env.example` with a placeholder value. When adding a new variable:

1. Add to `docker-compose.yml`
2. Add to `.env.example` with a descriptive placeholder: `NEW_VAR=change-me`
3. Add actual value to `.env` on the VM (never commit `.env`)
