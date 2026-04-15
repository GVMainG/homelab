#!/usr/bin/env bash
# first-deployment.sh — первичный деплой vps-ru-proxy.
# Запускать от root на чистом Debian 12 на VPS.
#
# Bootstrap (одна команда):
#   bash <(curl -fsSL https://raw.githubusercontent.com/GVMainG/homelab/main/vps-ru-proxy/first-deployment.sh)
#
# Структура на VPS: /opt/vps-ru-proxy/[содержимое VM] — без лишних папок.
# Запускает только NPM. Для FRP-сервера после деплоя запустите frp-setup.sh.
#
# Защита от повторного запуска: при наличии маркера .deployed скрипт остановится.
# Для переустановки: rm /opt/vps-ru-proxy/.deployed && bash first-deployment.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ── Цветовой вывод ────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

DEPLOY_DIR="/opt/vps-ru-proxy"
REPO_URL="https://github.com/GVMainG/homelab.git"
SPARSE_PATH="vps-ru-proxy"

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
    log_warn "VPS уже был задеплоен: $(cat "$DEPLOYED_MARKER")"
    log_warn "Для обновления используйте:  bash ${DEPLOY_DIR}/sync.sh"
    log_warn "Для сброса удалите маркер:   rm ${DEPLOYED_MARKER}"
    log_warn "════════════════════════════════════════════════════════════════"
    read -r -p "  Продолжить принудительно? [y/N]: " answer
    if [[ "${answer,,}" != "y" ]]; then
        log_info "Отменено."
        exit 0
    fi
fi

# ── Шаг 2: Обновление системы ─────────────────────────────────────────────────
log_step "Обновление системы"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    fail2ban \
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

# ── Шаг 4: Настройка fail2ban ─────────────────────────────────────────────────
log_step "Настройка fail2ban"
FAIL2BAN_JAIL="/etc/fail2ban/jail.d/homelab-sshd.local"

if [[ -f "$FAIL2BAN_JAIL" ]]; then
    log_info "fail2ban sshd jail уже настроен — пропуск"
else
    cat > "$FAIL2BAN_JAIL" <<'EOF'
# Базовая защита SSH: блокировка на 1 час после 5 неудачных попыток за 10 минут
[sshd]
enabled  = true
port     = ssh
logpath  = %(sshd_log)s
backend  = %(sshd_backend)s
maxretry = 5
bantime  = 3600
findtime = 600
EOF
    systemctl enable fail2ban
    systemctl restart fail2ban
    log_info "fail2ban sshd jail настроен"
fi

# ── Шаг 5: Создание директорий NPM ───────────────────────────────────────────
log_step "Создание директорий"
mkdir -p \
    "${DEPLOY_DIR}/npm/data" \
    "${DEPLOY_DIR}/npm/letsencrypt"
log_info "Директории готовы"

# ── Шаг 6: Запуск NPM ────────────────────────────────────────────────────────
log_step "Запуск Nginx Proxy Manager"
docker compose up -d npm
log_info "NPM запущен"

# ── Запись маркера деплоя ────────────────────────────────────────────────────
echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') on $(hostname)" > "$DEPLOYED_MARKER"
log_info "Маркер .deployed записан"

# ── Итоговая сводка ───────────────────────────────────────────────────────────
VPS_IP="$(curl -s --max-time 5 https://ifconfig.me 2>/dev/null \
    || hostname -I | awk '{print $1}')"

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║          vps-ru-proxy готов!                     ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  NPM admin panel:  ${BLUE}http://${VPS_IP}:81${NC}"
echo ""
echo -e "  ${YELLOW}⚠  Смените пароль NPM после первого входа!${NC}"
echo -e "     Email:    ${YELLOW}admin@example.com${NC}"
echo -e "     Password: ${YELLOW}changeme${NC}"
echo ""
echo -e "  Статус:  docker compose ps"
echo ""
echo -e "  Для настройки FRP-сервера:"
echo -e "    sudo bash ${DEPLOY_DIR}/frp-setup.sh"
echo ""
echo -e "  Для добавления агента Dockhand (Hawser):"
echo -e "    sudo bash ${DEPLOY_DIR}/run-hawser.sh"
echo ""
