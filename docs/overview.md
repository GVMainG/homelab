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
vm-proxy-02 (192.168.1.37)
   ├── :80   → Nginx Proxy Manager (HTTP redirect)
   ├── :443  → Nginx Proxy Manager (SSL termination)
   ├── :81   → NPM Admin UI
   └── :53   → dnsmasq (split-DNS: *.home.loc → 192.168.1.37)
         │
         ▼
vm-db-02 (192.168.1.36)
   ├── :5432 → PostgreSQL 16 (проброшен на LAN)
   ├── :8080 → Vaultwarden (password manager)
   └── :5050 → pgAdmin (PostgreSQL web UI)
   └── Все три сервиса на изолированной Docker сети: db-net
```

**Примечание:** Также существуют vm-db-01 (192.168.1.51) и vm-proxy-01 (192.168.1.50) — первые экземпляры VM. Текущая рабочая пара — vm-db-02 / vm-proxy-02.

## Виртуальные машины

| VM | IP | ОС | Роль | Сервисы |
|---|---|---|---|---|
| `vm-db-02` | 192.168.1.36 | Linux | База данных + менеджмент | PostgreSQL 16, Vaultwarden (latest), pgAdmin 4 (latest) |
| `vm-proxy-02` | 192.168.1.37 | Linux | Reverse proxy + DNS | Nginx Proxy Manager (latest), dnsmasq (split-DNS) |
| `vm-db-01` | 192.168.1.51 | Linux | База данных + менеджмент (legacy) | PostgreSQL 16.4, Vaultwarden 1.32.5, pgAdmin 8.12 |
| `vm-proxy-01` | 192.168.1.50 | Linux | Reverse proxy + DNS (legacy) | Nginx Proxy Manager (latest), dnsmasq (split-DNS) |

**Хост:** Proxmox VE, сеть LAN `192.168.1.0/24`

**Репозиторий:** https://github.com/GVMainG/homelab.git — каждая VM использует sparse checkout (`git sparse-checkout set <vm-name>`), клонируя только свой подкаталог. Скрипт `sync.sh` автоматизирует обновление.

## Доменные имена (DNS)

| Домен | Резолвится на | Назначение |
|---|---|---|
| `*.home.loc` | 192.168.1.37 | Wildcard DNS через dnsmasq на vm-proxy-02 |
| `vw.home.loc` | 192.168.1.37 | Vaultwarden (через NPM reverse proxy на vm-db-02:8080) |

## Сервисы и endpoint'ы

| Сервис | VM | Порт | URL | Доступ |
|---|---|---|---|---|
| PostgreSQL 16 | vm-db-02 | 5432 (проброшен на LAN) | `192.168.1.36:5432` | LAN |
| Vaultwarden | vm-db-02 | 8080 | `http://192.168.1.36:8080` | LAN |
| pgAdmin | vm-db-02 | 5050 | `http://192.168.1.36:5050` | LAN |
| Nginx Proxy Manager | vm-proxy-02 | 81 | `http://192.168.1.37:81` | LAN (admin UI) |
| Nginx Proxy Manager | vm-proxy-02 | 443 | `https://*.home.loc` | Internet/LAN (SSL) |
| dnsmasq | vm-proxy-02 | 53 | — | LAN (DNS) |

## Зависимости

```
Nginx Proxy Manager (vm-proxy-02) ──reverse proxy──▶ Vaultwarden (vm-db-02:8080)
                                                     ▶ pgAdmin     (vm-db-02:5050)

Vaultwarden ──postgresql://──▶ PostgreSQL (vm-db-02:5432, db: vaultwarden, user: vw_user)

dnsmasq (vm-proxy-02) ── DNS resolution ──▶ *.home.loc → 192.168.1.37 (NPM)

Docker network: db-net (bridge) — объединяет все 3 сервиса на vm-db-02
```
