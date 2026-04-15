#!/usr/bin/env bash
# run-hawser.sh — запустить агента Dockhand (Hawser) как Docker-контейнер.
# Идемпотентен: при повторном запуске пересоздаёт контейнер.
#
# Два режима:
#   Standard — агент слушает порт 2376, Dockhand подключается к нему (LAN).
#   Edge     — агент сам подключается к Dockhand по WebSocket (NAT/VPN).
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
log_step "Режим агента"
echo "  1) Standard — агент слушает порт 2376, Dockhand подключается к нему (LAN)"
echo "  2) Edge     — агент сам подключается к Dockhand через WebSocket (NAT-friendly)"
echo ""
MODE="$(read_default "Выберите режим (1/2)" "1")"

# ── Параметры ─────────────────────────────────────────────────────────────────
log_step "Параметры агента"

TOKEN="$(read_default "Токен")"
if [[ -z "$TOKEN" ]]; then
    log_error "Токен обязателен."
    exit 1
fi

AGENT_NAME="$(read_default "Имя агента" "$(hostname)")"
STACKS_DIR="$(read_default "Директория стеков" "$SCRIPT_DIR")"

DOCKHAND_URL=""
if [[ "$MODE" == "2" ]]; then
    DOCKHAND_URL="$(read_default "URL Dockhand (например: http://192.168.1.XX:3000)")"
    if [[ -z "$DOCKHAND_URL" ]]; then
        log_error "URL Dockhand обязателен для Edge-режима."
        exit 1
    fi
fi

# ── Запуск контейнера ─────────────────────────────────────────────────────────
log_step "Запуск контейнера hawser"

CONTAINER_NAME="hawser"
if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    log_warn "Контейнер ${CONTAINER_NAME} уже существует — пересоздание..."
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    docker rm "$CONTAINER_NAME"
fi

if [[ "$MODE" == "1" ]]; then
    docker run -d \
        --name "$CONTAINER_NAME" \
        --restart unless-stopped \
        -p 2376:2376 \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v "${STACKS_DIR}:/stacks" \
        -e TOKEN="$TOKEN" \
        -e AGENT_NAME="$AGENT_NAME" \
        -e STACKS_DIR=/stacks \
        ghcr.io/finsys/hawser:latest
    log_info "Hawser запущен в Standard-режиме (порт 2376)"
else
    docker run -d \
        --name "$CONTAINER_NAME" \
        --restart unless-stopped \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v "${STACKS_DIR}:/stacks" \
        -e TOKEN="$TOKEN" \
        -e AGENT_NAME="$AGENT_NAME" \
        -e STACKS_DIR=/stacks \
        -e DOCKHAND_SERVER_URL="$DOCKHAND_URL" \
        ghcr.io/finsys/hawser:latest
    log_info "Hawser запущен в Edge-режиме"
fi

# ── Итоговая сводка ───────────────────────────────────────────────────────────
VM_IP="$(hostname -I | awk '{print $1}')"

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║            Hawser запущен!                       ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Агент:  ${GREEN}${AGENT_NAME}${NC}"
if [[ "$MODE" == "1" ]]; then
    echo -e "  Режим:  Standard"
    echo -e "  Адрес:  ${YELLOW}${VM_IP}:2376${NC}"
    echo ""
    echo -e "  В Dockhand: Agents → Add Agent"
    echo -e "    Host:  ${VM_IP}"
    echo -e "    Port:  2376"
    echo -e "    Token: ${YELLOW}(указанный токен)${NC}"
else
    echo -e "  Режим:  Edge"
    echo -e "  Dockhand: ${YELLOW}${DOCKHAND_URL}${NC}"
fi
echo ""
echo -e "  Логи:   docker logs -f ${CONTAINER_NAME}"
echo -e "  Стоп:   docker stop ${CONTAINER_NAME} && docker rm ${CONTAINER_NAME}"
echo ""
