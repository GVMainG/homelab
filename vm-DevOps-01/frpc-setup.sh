#!/usr/bin/env bash
# frpc-setup.sh — настройка FRP-клиента на vm-DevOps-01.
# Генерирует frpc/frpc.toml и frpc/docker-compose.yml, запускает контейнер.
# Идемпотентен: повторный запуск обновляет конфигурацию.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

FRPC_DIR="${SCRIPT_DIR}/frpc"
FRPC_CONFIG="${FRPC_DIR}/frpc.toml"
FRPC_COMPOSE="${FRPC_DIR}/docker-compose.yml"

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

# ── Проверка root ─────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    log_error "Запустите от root: sudo bash $0"
    exit 1
fi

# ── Утилита: ввод с дефолтом ──────────────────────────────────────────────────
read_default() {
    local prompt="$1"
    local default="${2:-}"
    local value
    if [[ -n "$default" ]]; then
        read -r -p "  ${prompt} [${default}]: " value
    else
        read -r -p "  ${prompt}: " value
    fi
    echo "${value:-$default}"
}

# ── Шаг 1: Проверка Docker ────────────────────────────────────────────────────
log_step "Проверка Docker"
if ! command -v docker &>/dev/null; then
    log_error "Docker не установлен. Сначала запустите setup.sh."
    exit 1
fi
log_info "Docker: $(docker --version)"

# ── Шаг 2: Параметры FRP-сервера (VPS) ───────────────────────────────────────
log_step "Параметры FRP-сервера (VPS)"
echo "  (Значения берутся из вывода setup.sh на VPS или из /opt/vps-ru-proxy/.env)"
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

# ── Шаг 3: Сервисы для проброса ──────────────────────────────────────────────
log_step "Сервисы для проброса через туннель"
echo "  remotePort — порт на VPS, на который NPM будет проксировать трафик."
echo ""

PROXY_NAMES=()
PROXY_LOCAL_PORTS=()
PROXY_REMOTE_PORTS=()

add_preset() {
    local name="$1"
    local local_port="$2"
    local default_remote="$3"
    local desc="$4"

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

# Предустановленный сервис: Dockhand
add_preset "dockhand" "3000" "13000" "Dockhand UI"

# Произвольные сервисы
echo "  Добавить ещё сервис?"
while true; do
    read -r -p "  [y/N]: " add_more
    if [[ "${add_more,,}" != "y" ]]; then
        break
    fi
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

# ── Шаг 4: Проверка существующей конфигурации ─────────────────────────────────
log_step "Подготовка директории"

SKIP_CONFIG=false
if [[ -f "$FRPC_CONFIG" ]]; then
    log_warn "frpc/frpc.toml уже существует."
    read -r -p "  Перезаписать? [y/N]: " answer
    if [[ "${answer,,}" != "y" ]]; then
        log_info "Конфигурация сохранена без изменений."
        SKIP_CONFIG=true
    fi
fi

mkdir -p "$FRPC_DIR"

# ── Шаг 5: Генерация frpc.toml ────────────────────────────────────────────────
if [[ "$SKIP_CONFIG" == "false" ]]; then
    log_step "Генерация frpc/frpc.toml"

    {
        cat <<EOF
# frpc.toml — конфигурация FRP-клиента (vm-DevOps-01)
# Сгенерировано frpc-setup.sh $(date -u '+%Y-%m-%d %H:%M:%S UTC')
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
    } > "$FRPC_CONFIG"

    chmod 600 "$FRPC_CONFIG"
    log_info "frpc/frpc.toml создан (права: 600)"
fi

# ── Шаг 6: Генерация docker-compose.yml ──────────────────────────────────────
log_step "Генерация frpc/docker-compose.yml"

cat > "$FRPC_COMPOSE" <<'EOF'
# docker-compose.yml для frpc (vm-DevOps-01)
# network_mode: host — frpc видит 127.0.0.1 хоста,
# что позволяет подключаться к Dockhand и другим сервисам по локальным портам.
services:
  frpc:
    image: snowdreamtech/frpc:latest
    container_name: frpc-devops
    restart: unless-stopped
    network_mode: host
    volumes:
      - ./frpc.toml:/etc/frp/frpc.toml:ro
    healthcheck:
      test: ["CMD", "pgrep", "frpc"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 10s
EOF

log_info "frpc/docker-compose.yml создан"

# ── Шаг 7: Запуск ─────────────────────────────────────────────────────────────
log_step "Запуск frpc"
docker compose -f "$FRPC_COMPOSE" up -d
log_info "frpc запущен"

# ── Итоговая сводка ───────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║           frpc успешно настроен!                  ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════╝${NC}"
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
echo -e "  Полезные команды:"
echo -e "    Логи:   ${YELLOW}docker compose -f ${FRPC_COMPOSE} logs -f${NC}"
echo -e "    Статус: ${YELLOW}docker compose -f ${FRPC_COMPOSE} ps${NC}"
echo -e "    Стоп:   ${YELLOW}docker compose -f ${FRPC_COMPOSE} down${NC}"
echo ""
