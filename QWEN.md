# homelab — Self-hosted Infrastructure

## Обзор

Монорепозиторий с конфигурациями для развёртывания домашней лаборатории (homelab) на Debian/Ubuntu VM. Каждый сервис — отдельная VM с собственным `deploy.sh`, `docker-compose.yml` и утилитой `sync.sh` для обновления через **Git sparse checkout**.

### Архитектура

```
┌─────────────────────────────────────────────────────┐
│  LAN 192.168.1.0/24                                 │
│                                                     │
│  vm-proxy-01 (192.168.1.50)                         │
│  ┌───────────┐    ┌──────────────────────────┐      │
│  │  dnsmasq  │───▶│  Nginx Proxy Manager     │      │
│  │  Split-DNS│    │  :80 :81 :443            │      │
│  └───────────┘    └──────────────────────────┘      │
│                                                     │
│  vm-db-01 (192.168.1.51)                            │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────┐  │
│  │  PostgreSQL  │  │ Vaultwarden  │  │  pgAdmin  │  │
│  │  :5432 (lo)  │  │  :8081       │  │  :5050    │  │
│  └──────────────┘  └──────────────┘  └───────────┘  │
└─────────────────────────────────────────────────────┘
```

## Структура репозитория

```
homelab/
├── vm-proxy-01/          # Reverse proxy + Split-DNS
│   ├── deploy-dnsmasq.sh # Установка dnsmasq (root, idempotent)
│   ├── docker-compose.yml# Nginx Proxy Manager
│   ├── sync.sh           # Git sparse checkout update
│   └── configs/dnsmasq/
│       ├── 00-main.conf      # Upstream DNS, interface, strict-order
│       └── 01-split-dns.conf # *.host.loc → PROXY_IP
│
├── vm-db-01/             # Database + Secrets
│   ├── docker-compose.yml# PostgreSQL 16.4 + Vaultwarden 1.32.5 + pgAdmin 8.12
│   ├── deploy.sh         # Инициализация (.env → pgadmin configs → up)
│   ├── backup.sh         # pg_dump + gzip + ротация
│   ├── sync.sh           # Git sparse checkout update
│   ├── .env.example      # Шаблон секретов
│   └── .gitignore        # .env, backups/, pgadmin/
│
└── .gitignore            # backups/, pgadmin/
```

## vm-proxy-01 (192.168.1.50)

### Сервисы

| Сервис | Порт | Назначение |
|--------|------|------------|
| dnsmasq | 53 UDP/TCP | Split-DNS: `*.host.loc` → `192.168.1.50` |
| Nginx Proxy Manager | 80, 81, 443 | Reverse proxy + SSL-терминация |

### Развёртывание

```bash
# 1. Клон (sparse checkout)
cd /opt
git clone --filter=blob:none --sparse git@github.com:GVMainG/homelab.git
cd homelab && git sparse-checkout set vm-proxy-01

# 2. Установка dnsmasq
cd vm-proxy-01
chmod +x deploy-dnsmasq.sh
./deploy-dnsmasq.sh

# 3. Запуск NPM
docker compose up -d

# 4. Обновление из git
./sync.sh
```

### Ключевые особенности deploy-dnsmasq.sh

- **Автоопределение интерфейса** — `ip -br addr show` находит первый UP-интерфейс
- **Временный DNS** — до остановки systemd-resolved прописывает `1.1.1.1` в resolv.conf
- **envsubst** — подставляет переменные в шаблоны конфигов
- **Идемпотентность** — бэкап существующих конфигов перед заменой

## vm-db-01 (192.168.1.51)

### Сервисы

| Сервис | Порт | Доступ | Версия |
|--------|------|--------|--------|
| PostgreSQL | 127.0.0.1:5432 | Только localhost | 16.4 |
| Vaultwarden | 0.0.0.0:8081 | LAN (нужен firewall) | 1.32.5 |
| pgAdmin | 0.0.0.0:5050 | LAN (нужен firewall) | 8.12 |

### Развёртывание

```bash
# 1. Клон (sparse checkout)
cd /opt
git clone --filter=blob:none --sparse git@github.com:GVMainG/homelab.git
cd homelab && git sparse-checkout set vm-db-01

# 2. Инициализация
cd vm-db-01
chmod +x deploy.sh backup.sh
./deploy.sh          # скопирует .env.example → .env, попросит заменить пароли
# → отредактировать .env → запустить повторно

# 3. Обновление из git
./sync.sh
```

### Бэкап / Восстановление

```bash
# Создать бэкап (автоматическая ротация)
./backup.sh

# Восстановить
gunzip -c backups/pg_backup_*.sql.gz | \
  docker exec -i db-postgres psql -U admin -d postgre
```

### Безопасность

- Все секреты в `.env` (игнорируется Git)
- `CHANGE_ME`-проверка в deploy.sh
- PostgreSQL привязан к `127.0.0.1` (внешний доступ только через хост)
- Vaultwarden: `ENABLE_ADMIN_PAGE=true`, `SIGNUPS_ALLOWED=true`
- pgAdmin: auto-connect через `servers.json` + `pgpass`
- Healthcheck для каждого сервиса
- Network `db-internal` — изоляция от других compose-проектов

## Git sparse checkout

Каждая VM клонирует **только свою папку** — не весь репозиторий.

```bash
# Первый клон
git clone --filter=blob:none --sparse git@github.com:GVMainG/homelab.git
cd homelab
git sparse-checkout set vm-proxy-01   # или vm-db-01

# Обновление
cd vm-proxy-01 && ./sync.sh
```

## Соглашения

- **Язык скриптов**: bash, `set -euo pipefail`
- **Все deploy-скрипты** проверяют зависимости перед выполнением
- **Docker Compose v2** — без поля `version`
- **Фиксированные версии образов** — `latest` запрещён
- **Относительные пути** — скрипты работают из своей директории (`SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"`)
- **Комментарии на русском** — только по делу, без воды
