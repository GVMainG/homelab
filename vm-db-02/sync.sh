#!/usr/bin/env bash
# Идемпотентный скрипт: клонирует репозиторий (sparse checkout) или делает git pull
set -euo pipefail

REPO_URL="https://github.com/GVMainG/homelab.git"
CLONE_DIR="/opt/homelab"
SPARSE_PATH="vm-db-02"

if [[ -d "${CLONE_DIR}/.git" ]]; then
    echo "[sync] Repository already exists — pulling latest changes..."
    git -C "${CLONE_DIR}" pull
else
    echo "[sync] Cloning repository with sparse checkout..."
    git clone --filter=blob:none --sparse --branch main "${REPO_URL}" "${CLONE_DIR}"
    git -C "${CLONE_DIR}" sparse-checkout set "${SPARSE_PATH}"
fi

echo "[sync] Done. Working directory: ${CLONE_DIR}/${SPARSE_PATH}/"
