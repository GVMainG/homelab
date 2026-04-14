#!/usr/bin/env bash
# setup.sh — запускается ОДИН РАЗ от root на чистом Debian 12 на VPS.
# Устанавливает Docker, генерирует учётные данные, настраивает fail2ban
# и запускает стек через docker compose.
# Идемпотентен: повторный запуск не ломает существующую конфигурацию.
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

# ── Проверка: запуск от root ──────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    log_error "Скрипт должен запускаться от root. Используйте: sudo bash $0"
    exit 1
fi

ENV_FILE="${SCRIPT_DIR}/.env"
FRPS_CONFIG="${SCRIPT_DIR}/frps/frps.toml"
FRPS_TEMPLATE="${SCRIPT_DIR}/frps.toml"

# ── Шаг 1: Обновление системы ─────────────────────────────────────────────────
log_step "Обновление системы"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq
log_info "Система обновлена"

# ── Шаг 2: Установка пакетов ──────────────────────────────────────────────────
# gettext-base предоставляет envsubst для шаблонизации frps.toml
log_step "Установка вспомогательных пакетов"
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    fail2ban \
    pwgen \
    jq \
    gettext-base
log_info "Пакеты установлены"

# ── Шаг 3: Установка Docker ───────────────────────────────────────────────────
log_step "Установка Docker"
if command -v docker &>/dev/null; then
    log_warn "Docker уже установлен ($(docker --version)) — пропуск"
else
    # Добавляем официальный GPG-ключ Docker
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg \
        | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    # Добавляем репозиторий Docker
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

# ── Шаг 4: Создание структуры директорий ─────────────────────────────────────
log_step "Создание структуры директорий"
# mkdir -p идемпотентен — безопасно при повторном запуске
mkdir -p \
    "${SCRIPT_DIR}/npm/data" \
    "${SCRIPT_DIR}/npm/letsencrypt" \
    "${SCRIPT_DIR}/npm/mysql" \
    "${SCRIPT_DIR}/frps"
log_info "Директории готовы"

# ── Шаг 5: Генерация учётных данных ──────────────────────────────────────────
log_step "Настройка учётных данных"

SKIP_ENV=false
if [[ -f "$ENV_FILE" ]]; then
    log_warn ".env уже существует"
    read -r -p "  Перегенерировать .env? Существующие данные будут перезаписаны [y/N]: " answer
    if [[ "${answer,,}" != "y" ]]; then
        log_info "Используется существующий .env"
        SKIP_ENV=true
    fi
fi

if [[ "$SKIP_ENV" == "false" ]]; then
    log_info "Генерация случайных значений через pwgen..."

    # pwgen -s: криптографически случайные символы (буквы + цифры, без -y)
    FRP_TOKEN="$(pwgen -s 48 1)"
    FRP_DASHBOARD_PASSWORD="$(pwgen -s 16 1)"
    MYSQL_ROOT_PASSWORD="$(pwgen -s 32 1)"
    MYSQL_PASSWORD="$(pwgen -s 32 1)"

    cat > "$ENV_FILE" <<EOF
# Сгенерировано setup.sh $(date -u '+%Y-%m-%d %H:%M:%S UTC')
# Не коммитить в git. Права: 600.

# ── FRP ──────────────────────────────────────────────────────────────────────
# Токен аутентификации туннеля (frps ↔ frpc должны совпадать)
FRP_TOKEN=${FRP_TOKEN}
# Пароль веб-дашборда frps (пользователь: admin)
FRP_DASHBOARD_PASSWORD=${FRP_DASHBOARD_PASSWORD}

# ── MariaDB (Nginx Proxy Manager) ────────────────────────────────────────────
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}
MYSQL_PASSWORD=${MYSQL_PASSWORD}
EOF
    chmod 600 "$ENV_FILE"
    log_info ".env создан (права: 600)"
fi

# Загружаем переменные из .env для дальнейшего использования
# shellcheck source=.env
source "$ENV_FILE"
log_info "Переменные окружения загружены"

# ── Шаг 6: Шаблонизация frps.toml ────────────────────────────────────────────
log_step "Генерация конфига frps"

SKIP_FRPS=false
if [[ -f "$FRPS_CONFIG" ]]; then
    log_warn "frps/frps.toml уже существует"
    read -r -p "  Перезаписать frps/frps.toml? [y/N]: " answer
    if [[ "${answer,,}" != "y" ]]; then
        log_info "Существующий frps/frps.toml сохранён"
        SKIP_FRPS=true
    fi
fi

if [[ "$SKIP_FRPS" == "false" ]]; then
    if [[ ! -f "$FRPS_TEMPLATE" ]]; then
        log_error "Шаблон не найден: ${FRPS_TEMPLATE}"
        exit 1
    fi

    # envsubst заменяет только указанные переменные, не трогая остальные ${...}
    export FRP_TOKEN FRP_DASHBOARD_PASSWORD
    envsubst '${FRP_TOKEN} ${FRP_DASHBOARD_PASSWORD}' \
        < "$FRPS_TEMPLATE" \
        > "$FRPS_CONFIG"

    log_info "frps/frps.toml сгенерирован из шаблона"
fi

# ── Шаг 7: Настройка fail2ban ─────────────────────────────────────────────────
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

# ── Шаг 8: Авторизация в Docker Hub ──────────────────────────────────────────
# Анонимные pull ограничены ~100 запросов/6 часов на IP.
# Бесплатный аккаунт снимает это ограничение.
log_step "Проверка авторизации Docker Hub"
if docker info 2>/dev/null | grep -q "Username:"; then
    log_info "Уже авторизован в Docker Hub"
else
    log_warn "Не авторизован в Docker Hub — возможна ошибка rate limit при pull"
    read -r -p "  Войти в Docker Hub? (рекомендуется) [Y/n]: " answer
    if [[ "${answer,,}" != "n" ]]; then
        docker login
    else
        log_warn "Пропуск. Если pull упадёт с rate limit — выполните: docker login"
    fi
fi

# ── Шаг 9: Запуск сервисов ────────────────────────────────────────────────────
log_step "Запуск Docker-сервисов"
docker compose up -d
log_info "Сервисы запущены"

# ── Итоговая сводка ───────────────────────────────────────────────────────────
# Определяем внешний IP VPS (fallback на первый IP сетевого интерфейса)
VPS_IP="$(curl -s --max-time 5 https://ifconfig.me 2>/dev/null \
    || hostname -I | awk '{print $1}')"

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║              Установка завершена!                ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  NPM admin panel:     ${BLUE}http://${VPS_IP}:81${NC}"
echo -e "  FRP dashboard:       ${BLUE}http://${VPS_IP}:7500${NC}"
echo ""
echo -e "  FRP dashboard user:  ${YELLOW}admin${NC}"
echo -e "  FRP dashboard pass:  ${YELLOW}${FRP_DASHBOARD_PASSWORD}${NC}"
echo ""
echo -e "  FRP токен для frpc:  ${YELLOW}${FRP_TOKEN}${NC}"
echo ""
echo -e "${YELLOW}  ⚠  Смените пароль NPM после первого входа!${NC}"
echo -e "     Email:    ${YELLOW}admin@example.com${NC}"
echo -e "     Password: ${YELLOW}changeme${NC}"
echo ""
echo -e "  Учётные данные сохранены в: ${BLUE}${ENV_FILE}${NC}"
echo ""
