#!/usr/bin/env bash
# frp-setup.sh — настройка FRP (клиент frpc или сервер frps) как Docker-контейнер.
# Идемпотентен: повторный запуск пересоздаёт контейнер и конфигурацию.
#
# Конфигурация сохраняется в ./frp/frpc.toml или ./frp/frps.toml (права 600).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

FRP_DIR="${SCRIPT_DIR}/frp"

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

read_default() {
    local prompt="$1" default="${2:-}" value
    if [[ -n "$default" ]]; then
        read -r -p "  ${prompt} [${default}]: " value
    else
        read -r -p "  ${prompt}: " value
    fi
    echo "${value:-$default}"
}

# ── Проверка: root ────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    log_error "Запустите от root: sudo bash $0"
    exit 1
fi

# ── Проверка Docker ───────────────────────────────────────────────────────────
log_step "Проверка Docker"
if ! command -v docker &>/dev/null; then
    log_error "Docker не установлен. Сначала запустите first-deployment.sh."
    exit 1
fi
log_info "Docker: $(docker --version)"

# ── Выбор режима ──────────────────────────────────────────────────────────────
log_step "Режим FRP"
echo "  1) Клиент (frpc) — пробросить локальные сервисы через туннель на VPS"
echo "  2) Сервер (frps) — принимать входящие туннельные соединения"
echo ""
FRP_MODE="$(read_default "Режим (1=клиент / 2=сервер)" "1")"

mkdir -p "$FRP_DIR"

# ══════════════════════════════════════════════════════════════════════════════
if [[ "$FRP_MODE" == "1" ]]; then
# ══════════════════════════════════════════════════════════════════════════════
# РЕЖИМ КЛИЕНТА (frpc)

    log_step "Параметры FRP-сервера (VPS)"
    echo "  (Значения из вывода frp-setup.sh на VPS или из frp/frps.toml)"
    echo ""

    VPS_HOST="$(read_default "IP или домен VPS")"
    if [[ -z "$VPS_HOST" ]]; then
        log_error "Хост VPS обязателен."
        exit 1
    fi

    FRP_TOKEN="$(read_default "FRP-токен")"
    if [[ -z "$FRP_TOKEN" ]]; then
        log_error "FRP-токен обязателен."
        exit 1
    fi

    FRP_PORT="$(read_default "Bind-порт frps" "7000")"

    # ── Сервисы для проброса ──────────────────────────────────────────────────
    log_step "Сервисы для проброса через туннель"
    echo "  remotePort — порт на VPS, на который NPM будет проксировать трафик."
    echo ""

    PROXY_NAMES=()
    PROXY_LOCAL_PORTS=()
    PROXY_REMOTE_PORTS=()

    add_preset() {
        local name="$1" local_port="$2" default_remote="$3" desc="$4"
        read -r -p "  Пробросить ${desc} (локальный :${local_port})? [Y/n]: " answer
        if [[ "${answer,,}" != "n" ]]; then
            local remote
            remote="$(read_default "    remotePort на VPS" "$default_remote")"
            PROXY_NAMES+=("$name")
            PROXY_LOCAL_PORTS+=("$local_port")
            PROXY_REMOTE_PORTS+=("$remote")
            log_info "  ${name}: 127.0.0.1:${local_port} → VPS:${remote}"
        fi
        echo ""
    }

    # Предустановленный сервис vm-DevOps-01
    add_preset "dockhand" "3000" "13000" "Dockhand UI"

    # Произвольные сервисы
    echo "  Добавить ещё сервис?"
    while true; do
        read -r -p "  [y/N]: " add_more
        [[ "${add_more,,}" != "y" ]] && break
        custom_name="$(read_default "  Имя (латиница, без пробелов)")"
        if [[ -z "$custom_name" ]]; then
            log_warn "Имя не может быть пустым."
            continue
        fi
        custom_local="$(read_default "  Локальный порт")"
        custom_remote="$(read_default "  remotePort на VPS")"
        PROXY_NAMES+=("$custom_name")
        PROXY_LOCAL_PORTS+=("$custom_local")
        PROXY_REMOTE_PORTS+=("$custom_remote")
        log_info "  ${custom_name}: 127.0.0.1:${custom_local} → VPS:${custom_remote}"
        echo ""
    done

    if [[ ${#PROXY_NAMES[@]} -eq 0 ]]; then
        log_error "Не выбрано ни одного сервиса."
        exit 1
    fi

    # ── Генерация frp/frpc.toml ───────────────────────────────────────────────
    log_step "Генерация frp/frpc.toml"
    FRP_CONFIG="${FRP_DIR}/frpc.toml"

    {
        cat <<EOF
# frpc.toml — конфигурация FRP-клиента (vm-DevOps-01)
# Сгенерировано frp-setup.sh $(date -u '+%Y-%m-%d %H:%M:%S UTC')
# Содержит токен — не коммитить в git.

serverAddr = "${VPS_HOST}"
serverPort = ${FRP_PORT}

[auth]
method = "token"
token  = "${FRP_TOKEN}"

[log]
to    = "console"
level = "info"

EOF
        for i in "${!PROXY_NAMES[@]}"; do
            cat <<EOF
[[proxies]]
name       = "${PROXY_NAMES[$i]}"
type       = "tcp"
localIP    = "127.0.0.1"
localPort  = ${PROXY_LOCAL_PORTS[$i]}
remotePort = ${PROXY_REMOTE_PORTS[$i]}

EOF
        done
    } > "$FRP_CONFIG"

    chmod 600 "$FRP_CONFIG"
    log_info "frp/frpc.toml создан (права: 600)"

    # ── Запуск контейнера frpc ────────────────────────────────────────────────
    log_step "Запуск контейнера frpc"
    CONTAINER_NAME="frpc"

    if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
        log_warn "Контейнер ${CONTAINER_NAME} уже существует — пересоздание..."
        docker stop "$CONTAINER_NAME" 2>/dev/null || true
        docker rm "$CONTAINER_NAME"
    fi

    docker run -d \
        --name "$CONTAINER_NAME" \
        --restart unless-stopped \
        --network host \
        -v "${FRP_CONFIG}:/etc/frp/frpc.toml:ro" \
        snowdreamtech/frpc:latest

    log_info "frpc запущен"

    # ── Сводка (клиент) ───────────────────────────────────────────────────────
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║           frpc успешно настроен!                 ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  VPS: ${YELLOW}${VPS_HOST}:${FRP_PORT}${NC}"
    echo ""
    echo -e "  Прокси:"
    for i in "${!PROXY_NAMES[@]}"; do
        echo -e "    ${GREEN}${PROXY_NAMES[$i]}${NC}"
        echo -e "      локально:  127.0.0.1:${PROXY_LOCAL_PORTS[$i]}"
        echo -e "      на VPS:    ${VPS_HOST}:${PROXY_REMOTE_PORTS[$i]}"
    done
    echo ""
    echo -e "  ${YELLOW}Следующий шаг — NPM на VPS:${NC}"
    for i in "${!PROXY_NAMES[@]}"; do
        echo -e "    Proxy Host: <домен> → http://127.0.0.1:${PROXY_REMOTE_PORTS[$i]}"
    done
    echo ""
    echo -e "  Дашборд туннелей: ${CYAN}http://${VPS_HOST}:7500${NC}"
    echo ""
    echo -e "  Логи:   docker logs -f ${CONTAINER_NAME}"
    echo -e "  Стоп:   docker stop ${CONTAINER_NAME} && docker rm ${CONTAINER_NAME}"
    echo ""

# ══════════════════════════════════════════════════════════════════════════════
else
# ══════════════════════════════════════════════════════════════════════════════
# РЕЖИМ СЕРВЕРА (frps)

    log_step "Параметры FRP-сервера"

    FRP_BIND_PORT="$(read_default "Bind-порт (для frpc)" "7000")"
    FRP_DASH_PORT="$(read_default "Порт дашборда"        "7500")"
    FRP_DASH_USER="$(read_default "Пользователь дашборда" "admin")"

    FRP_DASH_PASS="$(read_default "Пароль дашборда (Enter = сгенерировать)")"
    if [[ -z "$FRP_DASH_PASS" ]]; then
        FRP_DASH_PASS="$(openssl rand -base64 16 | tr -d '=+/')"
        log_info "Пароль сгенерирован: ${YELLOW}${FRP_DASH_PASS}${NC}"
    fi

    FRP_TOKEN="$(read_default "Токен аутентификации (Enter = сгенерировать)")"
    if [[ -z "$FRP_TOKEN" ]]; then
        FRP_TOKEN="$(openssl rand -base64 32 | tr -d '=+/')"
        log_info "Токен сгенерирован: ${YELLOW}${FRP_TOKEN}${NC}"
    fi

    # ── Генерация frp/frps.toml ───────────────────────────────────────────────
    log_step "Генерация frp/frps.toml"
    FRP_CONFIG="${FRP_DIR}/frps.toml"

    cat > "$FRP_CONFIG" <<EOF
# frps.toml — конфигурация FRP-сервера
# Сгенерировано frp-setup.sh $(date -u '+%Y-%m-%d %H:%M:%S UTC')
# Содержит токен и пароль — не коммитить в git.

bindPort = ${FRP_BIND_PORT}

[auth]
method = "token"
token  = "${FRP_TOKEN}"

[webServer]
addr     = "0.0.0.0"
port     = ${FRP_DASH_PORT}
user     = "${FRP_DASH_USER}"
password = "${FRP_DASH_PASS}"

[log]
to    = "console"
level = "info"

[transport]
maxPoolCount = 10
tcpMux       = true
EOF

    chmod 600 "$FRP_CONFIG"
    log_info "frp/frps.toml создан (права: 600)"

    # ── Запуск контейнера frps ────────────────────────────────────────────────
    log_step "Запуск контейнера frps"
    CONTAINER_NAME="frps"

    if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
        log_warn "Контейнер ${CONTAINER_NAME} уже существует — пересоздание..."
        docker stop "$CONTAINER_NAME" 2>/dev/null || true
        docker rm "$CONTAINER_NAME"
    fi

    docker run -d \
        --name "$CONTAINER_NAME" \
        --restart unless-stopped \
        --network host \
        -v "${FRP_CONFIG}:/etc/frp/frps.toml:ro" \
        snowdreamtech/frps:latest

    log_info "frps запущен"

    # ── Сводка (сервер) ───────────────────────────────────────────────────────
    VM_IP="$(hostname -I | awk '{print $1}')"
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║           frps успешно настроен!                 ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  Bind-порт: ${YELLOW}${FRP_BIND_PORT}${NC}"
    echo -e "  Дашборд:   ${CYAN}http://${VM_IP}:${FRP_DASH_PORT}${NC}"
    echo -e "  Логин:     ${YELLOW}${FRP_DASH_USER}${NC}"
    echo -e "  Пароль:    ${YELLOW}${FRP_DASH_PASS}${NC}"
    echo ""
    echo -e "  Токен для frpc: ${YELLOW}${FRP_TOKEN}${NC}"
    echo ""
    echo -e "  Логи:   docker logs -f ${CONTAINER_NAME}"
    echo -e "  Стоп:   docker stop ${CONTAINER_NAME} && docker rm ${CONTAINER_NAME}"
    echo ""

fi
