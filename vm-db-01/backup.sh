#!/usr/bin/env bash
# Бэкап PostgreSQL через pg_dump с ротацией
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "${SCRIPT_DIR}"

ENV_FILE="${SCRIPT_DIR}/.env"
BACKUP_DIR="${SCRIPT_DIR}/backups"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"

# ──────────────────────────────── Проверки ─────────────────────
if [[ ! -f "${ENV_FILE}" ]]; then
  echo "❌ .env не найден. Запустите deploy.sh primero."
  exit 1
fi

# Загружаем переменные
set -a
# shellcheck disable=SC1091
source "${ENV_FILE}"
set +a

mkdir -p "${BACKUP_DIR}"

# ──────────────────────────────── Бэкап ────────────────────────
TIMESTAMP="$(date +%F_%H%M%S)"
BACKUP_FILE="${BACKUP_DIR}/pg_backup_${TIMESTAMP}.sql.gz"

echo "==> Бэкап БД '${POSTGRES_DB}' → ${BACKUP_FILE}"
docker exec db-postgres pg_dump -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" \
  --no-owner --no-privileges \
  | gzip -9 > "${BACKUP_FILE}"

if [[ -s "${BACKUP_FILE}" ]]; then
  SIZE=$(du -h "${BACKUP_FILE}" | cut -f1)
  echo "   ✅ Размер: ${SIZE}"
else
  echo "❌ Файл бэкапа пуст!"
  exit 1
fi

# ──────────────────────────────── Ротация ──────────────────────
echo "==> Удаление бэкапов старше ${RETENTION_DAYS} дней..."
DELETED=$(find "${BACKUP_DIR}" -name "pg_backup_*.sql.gz" -mtime "+${RETENTION_DAYS}" -delete -print | wc -l)
echo "   Удалено файлов: ${DELETED}"

echo ""
echo "📦 Бэкапы:"
ls -lh "${BACKUP_DIR}"/pg_backup_*.sql.gz 2>/dev/null | tail -5
