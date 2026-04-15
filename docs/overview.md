# Обзор инфраструктуры

## Для чего этот документ и как вести?

Этот документ — «карта» всей инфраструктуры homelab. Он даёт общее понимание: какие есть виртуальные машины, как они связаны, какие сервисы работают и по каким адресам доступны.

**Что должно быть в этом документе:**

- Общая схема сети (ASCII-art или ссылка на диаграмму)
- Таблица всех VM: имя, IP, роль, ОС, выделенные ресурсы (CPU/RAM/disk)
- Список всех доменных имён и DNS-записей
- Перечень всех сервисов с их портами и endpoint'ами
- Описание сетевого взаимодействия между компонентами
- Зависимости между сервисами (что от чего зависит)

**Правила документирования:**

- Обновлять при добавлении/удалении любой VM или сервиса
- IP-адреса и домены указывать в таблицах — так легче сверять
- Схему сети обновлять при каждом изменении сетевой топологии
- Все ссылки на внешние ресурсы (документация, репозитории) должны быть рабочими
- Избегать подробных инструкций по настройке — для этого есть другие документы
- Если информация уже есть в другом документе — дать ссылку, а не дублировать

---

## Схема сети

```
Internet
   │
   ▼
vps-ru-proxy (публичный IP, Timeweb VPS)
   ├── :80/:443 → Nginx Proxy Manager (SSL Let's Encrypt)
   ├── :7000     → frps (принимает FRP-туннели от LAN-VM)
   └── :7500     → frps веб-дашборд
          │
          │ FRP-туннели (исходящие от LAN-VM → VPS:7000)
          ▼
LAN (192.168.1.0/24)
   │
   ├─▶ vm-db-01 (192.168.1.36)
   │     ├── frpc (network_mode: host) — пробрасывает порты в туннель
   │     │     ├── remotePort :18080 ← localPort :8080 (Vaultwarden)
   │     │     └── remotePort :15050 ← localPort :5050 (pgAdmin)
   │     ├── :5432 → PostgreSQL 16 (проброшен на LAN)
   │     ├── :8080 → Vaultwarden
   │     └── :5050 → pgAdmin
   │           └── db-net (bridge) — изолированная сеть для db-сервисов
   │
   └─▶ vm-DevOps-01 (192.168.1.XX)
         ├── frpc (network_mode: host) — пробрасывает Dockhand в туннель
         │     └── remotePort :13000 ← localPort :3000 (Dockhand)
         └── :3000 → Dockhand UI
```

Сервисы доступны двумя путями:

- **LAN напрямую:** `http://192.168.1.36:PORT`
- **Через интернет:** через FRP-туннель → NPM → домен `*.gv-services.net.ru` (HTTPS)

## Виртуальные машины

| VM | IP | ОС | Роль | Сервисы |
|---|---|---|---|---|
| `vm-db-01` | 192.168.1.36 | Debian 12 | База данных + менеджмент | PostgreSQL 16, Vaultwarden, pgAdmin 4, frpc |
| `vm-DevOps-01` | 192.168.1.XX | Debian 12 | Docker management | Dockhand, frpc |
| `vps-ru-proxy` | публичный IP | Debian 12 (Timeweb) | Обратный прокси + FRP-сервер | NPM (SQLite), frps |

**Хост LAN-VM:** Proxmox VE, сеть `192.168.1.0/24`

**Репозиторий:** https://github.com/GVMainG/homelab.git — каждая VM использует sparse checkout своего подкаталога. Скрипт `sync.sh` автоматизирует обновление, `first-deployment.sh` — первичный деплой с нуля.

## Доменные имена (DNS)

| Домен | Резолвится на | Назначение |
|---|---|---|
| `*.gv-services.net.ru` | публичный IP VPS | Wildcard A-запись на Timeweb |
| `frp-ui.gv-services.net.ru` | публичный IP VPS | FRP веб-дашборд (через NPM → frps:7500) |

## Сервисы и endpoint'ы

| Сервис | Хост | Порт | URL | Доступ |
|---|---|---|---|---|
| PostgreSQL 16 | vm-db-01 | 5432 | `192.168.1.36:5432` | LAN |
| Vaultwarden | vm-db-01 | 8080 | `http://192.168.1.36:8080` | LAN / через туннель |
| pgAdmin | vm-db-01 | 5050 | `http://192.168.1.36:5050` | LAN / через туннель |
| Dockhand UI | vm-DevOps-01 | 3000 | `http://192.168.1.XX:3000` | LAN / через туннель |
| Nginx Proxy Manager UI | vps-ru-proxy | 81 | `http://VPS_IP:81` | публичный |
| frps веб-дашборд | vps-ru-proxy | 7500 | `http://VPS_IP:7500` / `https://frp-ui.gv-services.net.ru` | публичный |

## Зависимости

```
Vaultwarden ──postgresql://──▶ PostgreSQL (vm-db-01, db-net, db: vaultwarden, user: vw_user)
pgAdmin ────────────────────▶ PostgreSQL (vm-db-01, db-net)

frpc (vm-db-01)      ──туннель──▶ frps (vps-ru-proxy, --network host)
frpc (vm-DevOps-01)  ──туннель──▶ frps (vps-ru-proxy, --network host)
Hawser (vm-db-01)    ────────────▶ Dockhand (vm-DevOps-01, :3000)
Hawser (vm-DevOps-01)────────────▶ Dockhand (self — управляет local Docker)

NPM (vps-ru-proxy, proxy-net) ──▶ VPS_IP:<remotePort> (хост frps, --network host)

Docker networks:
  db-net    (bridge) — vm-db-01: postgres, vaultwarden, pgadmin
  proxy-net (bridge) — vps-ru-proxy: npm
  frps — standalone container (--network host) на vps-ru-proxy
  frpc — standalone container (--network host) на каждой LAN-VM
```
