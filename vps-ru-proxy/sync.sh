#!/usr/bin/env bash
# sync.sh — обновить vps-ru-proxy из git-репозитория.
# Извлекает ТОЛЬКО содержимое vps-ru-proxy/ прямо в /opt/vps-ru-proxy/.
# Локальные файлы (.env, npm/, frps/) НЕ перезаписываются.
# Идемпотентен: безопасно запускать повторно.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

REPO_URL="https://github.com/GVMainG/homelab.git"
TARGET_DIR="/opt/vps-ru-proxy"
SPARSE_PATH="vps-ru-proxy"

# Определяем рабочую директорию
WORK_DIR="$TARGET_DIR"
if [[ -d "$SCRIPT_DIR/.git" ]]; then
    WORK_DIR="$SCRIPT_DIR"
fi

cd "$WORK_DIR"

# Инициализация репозитория если нет
if [[ ! -d ".git" ]]; then
    echo "[sync] Инициализация репозитория..."
    git init -q
    git remote add origin "$REPO_URL"
fi

echo "[sync] Получение изменений..."
git fetch origin main --quiet

# Извлечь только содержимое vps-ru-proxy/ из remote
git checkout -f origin/main -- "$SPARSE_PATH/"

# Переместить содержимое подкаталога в корень (cp мерджит директории)
echo "[sync] Распаковка файлов..."
cp -r "$SPARSE_PATH/." "./"
rm -rf "$SPARSE_PATH"

echo "[sync] Готово. Рабочий каталог: ${WORK_DIR}/"
