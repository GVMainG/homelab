#!/usr/bin/env bash
# Развёртывание vm-db-01 (PostgreSQL + Vaultwarden + pgAdmin)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "${SCRIPT_DIR}"

ENV_FILE="${SCRIPT_DIR}/.env"

# ──────────────────────────────── Проверки ─────────────────────
if ! command -v docker &>/dev/null; then
  echo "❌ Docker не установлен."
  exit 1
fi

if ! docker compose version &>/dev/null; then
  echo "❌ Docker Compose v2 не найден. Установите: apt install docker-compose-plugin"
  exit 1
fi

# ──────────────────────────────── .env ─────────────────────────
if [[ ! -f "${ENV_FILE}" ]]; then
  echo "==> .env не найден — копирую из .env.example"
  cp .env.example "${ENV_FILE}"
  echo "⚠️  Отредактируйте ${ENV_FILE} (пароли, email) и запустите скрипт заново."
  exit 1
fi

# Проверяем что пароли изменены с дефолтных
if grep -q "CHANGE_ME" "${ENV_FILE}"; then
  echo "❌ В .env обнаружены значения CHANGE_ME. Замените их на реальные секреты."
  exit 1
fi

# ──────────────────────────────── Директории ───────────────────
mkdir -p "${SCRIPT_DIR}/backups"
mkdir -p "${SCRIPT_DIR}/pgadmin"

# ──────────────────────────────── pgAdmin конфиги ──────────────
# Загружаем переменные из .env
set -a
# shellcheck disable=SC1091
source "${ENV_FILE}"
set +a

# servers.json — автоподключение к локальному PostgreSQL
cat > "${SCRIPT_DIR}/pgadmin/servers.json" <<EOF
{
  "Servers": {
    "1": {
      "Name": "vm-db-01",
      "Group": "Servers",
      "Host": "postgres",
      "Port": 5432,
      "MaintenanceDB": "${POSTGRES_DB}",
      "Username": "${POSTGRES_USER}",
      "PassFile": "/pgadmin4/pgpass"
    }
  }
}
EOF

# pgpass — файл паролей для pgAdmin (формат: host:port:db:user:pass)
# Права 0600 — pgAdmin отказывается читать более открытые файлы
cat > "${SCRIPT_DIR}/pgadmin/pgpass" <<EOF
postgres:5432:*:${POSTGRES_USER}:${POSTGRES_PASSWORD}
EOF
chmod 0600 "${SCRIPT_DIR}/pgadmin/pgpass"

# ──────────────────────────────── Запуск ───────────────────────
echo "==> Запуск сервисов..."
docker compose up -d

# ──────────────────────────────── Ожидание health ─────────────
echo "==> Ожидание healthy-статуса (до 60с)..."
for svc in postgres pgadmin; do
  timeout 60 bash -c "
    until docker inspect --format='{{.State.Health.Status}}' db-\${1} 2>/dev/null | grep -q healthy; do
      sleep 3
    done
  " _ "${svc}" && echo "   ✅ ${svc} healthy" || echo "   ⏳ ${svc} — проверьте: docker compose ps"
done

# ──────────────────────────────── Сводка ───────────────────────
echo ""
echo "=============================================="
echo "       vm-db-01 — ИТОГОВАЯ СВОДКА"
echo "=============================================="
echo "PostgreSQL  : 127.0.0.1:5432  (только localhost)"
echo "Vaultwarden : http://192.168.1.51:8081"
echo "pgAdmin     : http://192.168.1.51:5050"
echo "Бэкапы      : ${SCRIPT_DIR}/backups/"
echo "=============================================="
echo ""
docker compose ps
