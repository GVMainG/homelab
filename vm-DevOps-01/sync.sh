#!/usr/bin/env bash
# sync.sh — обновить vm-DevOps-01 из git-репозитория (sparse checkout).
# Идемпотентен: безопасно запускать повторно.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

REPO_URL="https://github.com/GVMainG/homelab.git"
CLONE_DIR="/opt/homelab"
SPARSE_PATH="vm-DevOps-01"

if [[ -d "${CLONE_DIR}/.git" ]]; then
    echo "[sync] Репозиторий существует — git pull..."
    git -C "${CLONE_DIR}" pull
else
    echo "[sync] Клонирование (sparse checkout)..."
    git clone --filter=blob:none --sparse --branch main "${REPO_URL}" "${CLONE_DIR}"
    git -C "${CLONE_DIR}" sparse-checkout set "${SPARSE_PATH}"
fi

echo "[sync] Готово. Рабочий каталог: ${CLONE_DIR}/${SPARSE_PATH}/"
