#!/usr/bin/env bash
# first-deployment.sh — первичный деплой vm-DevOps-01.
# Запускать от root на чистом Debian 12.
#
# Bootstrap (одна команда на чистой VM):
#   bash <(curl -fsSL https://raw.githubusercontent.com/GVMainG/homelab/main/vm-DevOps-01/first-deployment.sh)
#
# Защита от повторного запуска: при наличии маркера .deployed скрипт остановится.
# Для переустановки: rm /opt/homelab/vm-DevOps-01/.deployed && bash first-deployment.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ── Цветовой вывод ────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step()  { echo -e "\n${CYAN}════  $*  ════${NC}"; }

# ── Проверка: root ────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    log_error "Запустите от root: sudo bash $0"
    exit 1
fi

DEPLOY_DIR="/opt/vm-DevOps-01"
REPO_URL="https://github.com/GVMainG/homelab.git"
SPARSE_PATH="vm-DevOps-01"

mkdir -p "$DEPLOY_DIR"
cd "$DEPLOY_DIR"

# ── Шаг 1: Получение файлов VM из репозитория ────────────────────────────────
log_step "Получение конфигурации из репозитория"

if ! command -v git &>/dev/null; then
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq git
fi

if [[ ! -d ".git" ]]; then
    log_info "Инициализация репозитория..."
    git init -q
    git remote add origin "$REPO_URL"
fi

log_info "Получение изменений..."
git fetch origin main --quiet
git checkout -f origin/main -- "$SPARSE_PATH/"

# Переместить содержимое подкаталога в корень
shopt -s dotglob nullglob
for item in "$SPARSE_PATH"/*; do
    mv -f "$item" "./"
done
rm -rf "$SPARSE_PATH"
shopt -u dotglob

log_info "Файлы в: ${DEPLOY_DIR}/"

# ── Защита от повторного запуска ──────────────────────────────────────────────
DEPLOYED_MARKER="${DEPLOY_DIR}/.deployed"

if [[ -f "$DEPLOYED_MARKER" ]]; then
    log_warn "════════════════════════════════════════════════════════════════"
    log_warn "VM уже была задеплоена: $(cat "$DEPLOYED_MARKER")"
    log_warn "Повторный запуск перезапишет ENCRYPTION_KEY и сделает"
    log_warn "все сохранённые credentials в Dockhand нечитаемыми."
    log_warn "Для обновления используйте:  bash ${DEPLOY_DIR}/sync.sh"
    log_warn "Для сброса удалите маркер:   rm ${DEPLOYED_MARKER}"
    log_warn "════════════════════════════════════════════════════════════════"
    read -r -p "  Продолжить принудительно? [y/N]: " answer
    if [[ "${answer,,}" != "y" ]]; then
        log_info "Отменено."
        exit 0
    fi
fi

ENV_FILE="${DEPLOY_DIR}/.env"

# ── Шаг 2: Обновление системы ─────────────────────────────────────────────────
log_step "Обновление системы"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    openssl
log_info "Система обновлена"

# ── Шаг 3: Установка Docker ───────────────────────────────────────────────────
log_step "Установка Docker"
if command -v docker &>/dev/null; then
    log_warn "Docker уже установлен ($(docker --version)) — пропуск"
else
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg \
        | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/debian $(lsb_release -cs) stable" \
        | tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin

    systemctl enable --now docker
    log_info "Docker установлен: $(docker --version)"
fi

# ── Шаг 4: Генерация .env ─────────────────────────────────────────────────────
log_step "Настройка .env"

SKIP_ENV=false
if [[ -f "$ENV_FILE" ]]; then
    log_warn ".env уже существует"
    read -r -p "  Перегенерировать .env? [y/N]: " answer
    if [[ "${answer,,}" != "y" ]]; then
        log_info "Используется существующий .env"
        SKIP_ENV=true
    fi
fi

if [[ "$SKIP_ENV" == "false" ]]; then
    # AES-256 ключ для шифрования учётных данных в Dockhand.
    # НЕЛЬЗЯ менять после первого запуска — все credentials станут нечитаемыми.
    ENCRYPTION_KEY="$(openssl rand -base64 32)"

    cat > "$ENV_FILE" <<EOF
# Сгенерировано first-deployment.sh $(date -u '+%Y-%m-%d %H:%M:%S UTC')
# Не коммитить в git. Права: 600.

# ── Dockhand ──────────────────────────────────────────────────────────────────
# AES-256 ключ для шифрования учётных данных. Менять НЕЛЬЗЯ после первого запуска.
ENCRYPTION_KEY=${ENCRYPTION_KEY}

# UID/GID пользователя внутри контейнера
PUID=$(id -u)
PGID=$(id -g)
EOF
    chmod 600 "$ENV_FILE"
    log_info ".env создан (права: 600)"
fi

# ── Шаг 5: Запуск сервисов ────────────────────────────────────────────────────
log_step "Запуск Docker-сервисов"
docker compose up -d
log_info "Сервисы запущены"

# ── Запись маркера деплоя ────────────────────────────────────────────────────
echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') on $(hostname)" > "$DEPLOYED_MARKER"
log_info "Маркер .deployed записан"

# ── Итоговая сводка ───────────────────────────────────────────────────────────
VM_IP="$(hostname -I | awk '{print $1}')"

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║           vm-DevOps-01 готов!                    ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Dockhand UI: http://${VM_IP}:3000"
echo ""
echo -e "  ${YELLOW}⚠  При первом входе аутентификация отключена.${NC}"
echo -e "     Включить: Settings → Authentication"
echo ""
echo -e "  Статус:  docker compose ps"
echo -e "  Логи:    docker compose logs -f dockhand"
echo ""
echo -e "  Для настройки FRP-туннеля:"
echo -e "    sudo bash ${DEPLOY_DIR}/frp-setup.sh"
echo ""
echo -e "  Для добавления агента Dockhand (Hawser) на другие VM:"
echo -e "    sudo bash /opt/homelab/<vm>/run-hawser.sh"
echo ""
