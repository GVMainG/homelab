#!/usr/bin/env bash
# Развёртывание dnsmasq для Split-DNS на Debian 12 / Ubuntu 22.04
# Запуск: chmod +x deploy-dnsmasq.sh && sudo ./deploy-dnsmasq.sh
set -euo pipefail

# ──────────────────────────────── Переменные ────────────────────────────────
PROXY_IP="192.168.1.50"
LAN_IFACE=""           # Автоопределение ниже (или задать вручную: eth0, ens18...)
DNS_UPSTREAMS="1.1.1.1 8.8.8.8"
TARGET_DOMAIN="host.loc"
LAN_SUBNET="192.168.1.6/24"

# ──────────────────────────────── Проверка root ─────────────────────────────
if [[ $EUID -ne 0 ]]; then
  echo "Ошибка: скрипт требует прав root. Запустите: sudo ./deploy-dnsmasq.sh"
  exit 1
fi

# ──────────────────────────────── Рабочая директория ────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_SRC="${SCRIPT_DIR}/configs/dnsmasq"

echo "==> Рабочая директория: ${SCRIPT_DIR}"

# ──────────────────────────────── Проверка исходников ───────────────────────
if [[ ! -d "${CONFIG_SRC}" ]]; then
  echo "Ошибка: не найдена директория с конфигами ${CONFIG_SRC}"
  exit 1
fi

# ──────────────────────────────── Автоопределение интерфейса ────────────────
if [[ -z "${LAN_IFACE}" ]]; then
  LAN_IFACE=$(ip -br addr show 2>/dev/null | awk '$2 == "UP" && $1 != "lo" {print $1; exit}')
  if [[ -z "${LAN_IFACE}" ]]; then
    # Fallback: первый интерфейс, кроме lo
    LAN_IFACE=$(ip -br addr show 2>/dev/null | awk '$1 != "lo" {print $1; exit}')
  fi
  if [[ -z "${LAN_IFACE}" ]]; then
    echo "❌ Не удалось определить сетевой интерфейс. Укажите LAN_IFACE вручную."
    exit 1
  fi
  echo "==> Определён интерфейс: ${LAN_IFACE}"
else
  echo "==> Используем заданный интерфейс: ${LAN_IFACE}"
fi

# ──────────────────────────────── Временный DNS для apt ─────────────────────
# resolv.conf — это symlink на /run/systemd/resolve/stub-resolv.conf (127.0.0.53).
# Перед остановкой resolved нужно прописать реальный upstream, иначе apt
# не сможет резолвить зеркала.
echo "==> Подготовка временного DNS..."
DNS_FIRST=$(echo "${DNS_UPSTREAMS}" | awk '{print $1}')
rm -f /etc/resolv.conf
cat > /etc/resolv.conf <<EOF
# Временный DNS до запуска dnsmasq
nameserver ${DNS_FIRST}
nameserver 127.0.0.1
options timeout:2 attempts:3
EOF
echo "   Временный nameserver: ${DNS_FIRST}"

# ──────────────────────────────── Остановка systemd-resolved ────────────────
echo "==> Остановка и маскировка systemd-resolved (конфликт с портом 53)..."
if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
  systemctl disable --now systemd-resolved
  systemctl mask systemd-resolved
  echo "   systemd-resolved остановлен и замаскирован."
else
  echo "   systemd-resolved не активен — пропуск."
fi

# ──────────────────────────────── Установка dnsmasq ────────────────────────
echo "==> Установка dnsmasq..."
apt-get update -qq
if ! apt-get install -y -qq dnsmasq; then
  echo "❌ Ошибка установки dnsmasq. Проверьте:"
  echo "   1. Интернет-соединение (ping 1.1.1.1)"
  echo "   2. DNS (ping github.com)"
  echo "   3. /etc/resolv.conf: nameserver ${DNS_FIRST}"
  exit 1
fi
echo "   dnsmasq установлен."

# ──────────────────────────────── Подготовка конфигов ──────────────────────
DNSMASQ_D="/etc/dnsmasq.d"
mkdir -p "${DNSMASQ_D}"

# Бэкап и замена конфигов (идемпотентно)
for conf in 00-main.conf 01-split-dns.conf; do
  src="${CONFIG_SRC}/${conf}"
  dst="${DNSMASQ_D}/${conf}"
  if [[ -f "${src}" ]]; then
    # Подстановка переменных через envsubst (только известные переменные)
    if [[ -f "${dst}" ]]; then
      cp -p "${dst}" "${dst}.bak"
    fi
    envsubst '${PROXY_IP} ${LAN_IFACE} ${DNS_UPSTREAMS} ${TARGET_DOMAIN}' \
      < "${src}" > "${dst}"
    echo "   Установлен: ${conf}"
  else
    echo "   ПРЕДУПРЕЖДЕНИЕ: исходный файл ${src} отсутствует, пропуск."
  fi
done

# Отключаем стандартный dnsmasq.conf (используем только dnsmasq.d/)
if [[ -f /etc/dnsmasq.conf ]]; then
  # Убедиться что пустой или закомментирован — оставляем, dnsmasq.d приоритетнее
  :
fi

# ──────────────────────────────── Настройка интерфейса ─────────────────────
DEFAULT_FILE="/etc/default/dnsmasq"
mkdir -p "$(dirname "${DEFAULT_FILE}")"

cat > "${DEFAULT_FILE}" <<EOF
# Сгенерировано deploy-dnsmasq.sh
ENABLED=1
DNSMASQ_EXCEPT="lo"
DNSMASQ_OPTS="--interface=${LAN_IFACE} --bind-interfaces"
EOF
echo "==> Настроен ${DEFAULT_FILE}"

# ──────────────────────────────── Запуск сервиса ───────────────────────────
echo "==> Включение и перезапуск dnsmasq..."
systemctl daemon-reload
systemctl enable --now dnsmasq
systemctl restart dnsmasq

# ──────────────────────────────── Проверка статуса ─────────────────────────
echo ""
echo "=============================================="
echo "       ИТОГОВАЯ СВОДКА"
echo "=============================================="
echo "VM IP          : $(ip -4 -br addr show "${LAN_IFACE}" 2>/dev/null | awk '{print $3}' || 'N/A') (статический)"
echo "Интерфейс      : ${LAN_IFACE}"
echo "DNS-порт       : 53 (UDP/TCP)"
echo "Upstream DNS   : ${DNS_UPSTREAMS}"
echo "Split-DNS      : *.${TARGET_DOMAIN} -> ${PROXY_IP}"
echo "NPM-порт       : 80, 81, 443 (Docker)"
echo "=============================================="

if systemctl is-active --quiet dnsmasq; then
  echo "✅ dnsmasq активен (pid $(cat /run/dnsmasq/dnsmasq.pid 2>/dev/null || N/A))"
else
  echo "❌ dnsmasq НЕ активен! Проверьте: journalctl -u dnsmasq --no-pager -n 30"
  exit 1
fi

echo ""
echo "Команды проверки:"
echo "  dig @192.168.1.50 test.${TARGET_DOMAIN}      # должен вернуть ${PROXY_IP}"
echo "  dig @192.168.1.50 google.com                 # должен резолвить через upstream"
echo "  systemctl status dnsmasq                     # статус сервиса"
echo "  docker compose up -d                          # запуск NPM"
