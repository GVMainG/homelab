#!/usr/bin/env bash
# sync.sh — обновить vm-db-01 из git-репозитория.
# Извлекает ТОЛЬКО содержимое vm-db-01/ прямо в /opt/vm-db-01/.
# Локальные файлы (.env, данные PostgreSQL) НЕ перезаписываются.
# Идемпотентен: безопасно запускать повторно.
set -euo pipefail

REPO_URL="https://github.com/GVMainG/homelab.git"
TARGET_DIR="/opt/vm-db-01"
SPARSE_PATH="vm-db-01"

cd "$TARGET_DIR"

# Инициализация репозитория если нет
if [[ ! -d ".git" ]]; then
    echo "[sync] Инициализация репозитория..."
    git init -q
    git remote add origin "$REPO_URL"
fi

echo "[sync] Получение изменений..."
git fetch origin main --quiet

# Извлечь только содержимое vm-db-01/ из remote
git checkout -f origin/main -- "$SPARSE_PATH/"

# Переместить содержимое подкаталога в корень
echo "[sync] Распаковка файлов..."
shopt -s dotglob nullglob
for item in "$SPARSE_PATH"/*; do
    mv -f "$item" "./"
done
rm -rf "$SPARSE_PATH"
shopt -u dotglob

echo "[sync] Готово. Рабочий каталог: ${TARGET_DIR}/"
