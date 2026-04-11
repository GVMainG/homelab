#!/usr/bin/env bash
# Обновление репо с sparse checkout (только vm-proxy-01)
# Первый клон делается вручную (см. вывод ниже), далее — ./sync.sh
set -euo pipefail

# ──────────────────────────────── Переменные ────────────────────────────────
REPO_URL="https://github.com/GVMainG/homelab.git"          # TODO: вставьте URL вашего репозитория
BRANCH="main"        # ветка
TARGET_DIR="vm-proxy-01"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PARENT_DIR="$(dirname "${SCRIPT_DIR}")"
REPO_DIR="${PARENT_DIR}"

cd "${REPO_DIR}"

# ──────────────────────────────── Проверка: репо уже склонировано? ─────────
if [[ ! -d "${REPO_DIR}/.git" ]]; then
  echo "Репозиторий ещё не склонирован. Выполните вручную:"
  echo ""
  echo "  cd ${REPO_DIR}"
  echo "  git clone --filter=blob:none --sparse --branch ${BRANCH} ${REPO_URL} ${REPO_DIR}"
  echo "  cd ${REPO_DIR}"
  echo "  git sparse-checkout set ${TARGET_DIR}"
  echo ""
  echo "После этого запускайте ./sync.sh для обновлений."
  exit 1
fi

# ──────────────────────────────── Обновление ───────────────────────────────
echo "==> Pull из ${BRANCH}..."
git pull origin "${BRANCH}"
git sparse-checkout set "${TARGET_DIR}" 2>/dev/null || true

echo ""
echo "✅ Готово. Содержимое ${TARGET_DIR}/:"
ls -la "${TARGET_DIR}"
