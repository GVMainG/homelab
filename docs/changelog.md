# Журнал изменений

## Для чего этот документ и как вести?

Этот документ — хронологическая летопись всех значимых изменений в инфраструктуре homelab. Он помогает отследить, что, когда и зачем менялось, а также быстро найти точку, когда была внесена проблема.

**Что должно быть в этом документе:**

- **Дата** изменения (формат: `DD-MM-YYYY`)
- **Тип изменения**: `added` / `changed` / `fixed` / `removed` / `upgraded`
- **Описание** — что именно изменилось
- **VM** — на какой виртуальной машине внесено изменение
- **Версии** — какие версии сервисов затронуты
- **Ссылка на ADR** — если изменение связано с архитектурным решением
- **Кто внёс** — опционально, если несколько человек работают с инфраструктурой

Формат записи:

```
### 2025-04-14 — Добавлена vm-db-02

- **Тип:** added
- **VM:** vm-db-02
- **Описание:** Развёрнута новая VM с PostgreSQL 16, Vaultwarden и pgAdmin
- **Версии:** postgres:16, vaultwarden/server:latest, dpage/pgadmin4:latest
```

**Правила документирования:**

- Записи ведутся в обратном хронологическом порядке (новые сверху)
- Группировать по месяцам или по VM — как удобнее для чтения
- Не писать о рестартах сервисов и плановых перезагрузках
- Фиксировать только значимые изменения: новые сервисы, версии, конфиги, сеть
- При обновлении версии сервиса — указывать старую и новую версию
- При проблемах и rollback — фиксировать обе операции
- Ссылаться на коммиты в git, если изменение зафиксировано в репозитории

---

## 2026-04

### 2026-04-15 — Стандартизация скриптов деплоя всех VM

- **Тип:** changed, removed
- **VM:** все VM (vm-db-01, vm-DevOps-01, vps-ru-proxy)
- **Описание:** Удалены `setup.sh`, `frpc-setup.sh`, `deploy.ps1`. Вместо них — единые скрипты для каждой VM: `first-deployment.sh` (начальный деплой: клонирует репо, ставит Docker, генерирует `.env`, запускает сервисы; маркер `.deployed` защищает от повторного запуска), `frp-setup.sh` (настройка FRP — выбор клиент/сервер — запускает `docker run`), `run-hawser.sh` (запуск агента Dockhand через `docker run`). Добавлен `vps-ru-proxy/sync.sh`.
- **Коммит:** 1eed800

### 2026-04-15 — Добавлена vm-DevOps-01 с Dockhand

- **Тип:** added
- **VM:** vm-DevOps-01 (новый)
- **Описание:** Создана VM для управления Docker-инфраструктурой homelab. Развёрнут Dockhand (`fnsys/dockhand:latest`) — веб-интерфейс для управления контейнерами, Compose-стеками, логами и терминалом. Порт :3000. `ENCRYPTION_KEY` (AES-256) генерируется `first-deployment.sh` — нельзя менять после первого запуска. Удалённый доступ через frpc туннель :3000 → VPS:13000. Агент Hawser на других VM подключается к Dockhand для удалённого управления.
- **Версии:** `fnsys/dockhand:latest`
- **Коммиты:** e22225c, 1eed800

### 2026-04-15 — Перевод NPM с MariaDB на встроенный SQLite

- **Тип:** changed, removed
- **VM:** vps-ru-proxy
- **Описание:** Удалён сервис `npm-db` (MariaDB) из `vps-ru-proxy/docker-compose.yml`. NPM по умолчанию использует SQLite — MariaDB была запущена, но не подключена (NPM не имел переменных `DB_MYSQL_*`). Файл `database.sqlite` (114 КБ) подтверждён в `./npm/data/`. Применить на VPS: `docker compose up -d --remove-orphans`. Опциональная очистка: `rm -rf /opt/vps-ru-proxy/npm/mysql`.
- **Коммит:** a908668

### 2026-04-14 — Добавлен VPS-стек обратного прокси и frpc-клиент на vm-db-01

- **Тип:** added
- **VM:** vps-ru-proxy (новый), vm-db-01
- **Описание:** Развёрнут стек `vps-ru-proxy/` на Timeweb VPS (Debian 12): Nginx Proxy Manager, MariaDB, frps. Сервисы объединены в сеть `proxy-net`. Развёртывание — через `deploy.ps1` (Windows) + `setup.sh` (на VPS). На vm-db-01 добавлен `frpc-setup.sh` — интерактивный скрипт настройки frpc-клиента с туннелями Vaultwarden (:8080→VPS:18080) и pgAdmin (:5050→VPS:15050). Зарегистрирован домен `gv-services.net.ru`, добавлена wildcard A-запись `*.gv-services.net.ru` → публичный IP VPS. Исправлен баг в `vm-db-01/sync.sh`: SPARSE_PATH был `vm-db-02` вместо `vm-db-01`.
- **Версии:** `snowdreamtech/frps:latest`, `snowdreamtech/frpc:latest`, `jc21/nginx-proxy-manager:latest`, `jc21/mariadb-aria:latest`
- **Коммит:** 62e70ae

### 2026-04-14 — Удалена proxy VM, оставлена только vm-db-01

- **Тип:** removed
- **VM:** vm-proxy-02, vm-db-02 → переименована в vm-db-01
- **Описание:** Удалены vm-proxy-02 (NPM, dnsmasq, Homepage) и vm-db-02 переименована в vm-db-01. Теперь одна VM с PostgreSQL, Vaultwarden, pgAdmin. Сервисы доступны напрямую по IP `192.168.1.36` без reverse proxy и SSL-терминации.

### 2026-04-14 — Исправлены метаданные SSL-сертификата в NPM

- **Тип:** fixed
- **VM:** vm-proxy-02
- **Описание:** После перегенерации SSL-сертификата NPM UI показывал просроченную дату, хотя nginx реально отдавал новый сертификат. Проблема: NPM хранит `expires_on` в SQLite (`/data/database.sqlite`, таблица `certificate`), файлы заменили напрямую в volume, минуя обновление БД. Исправлено Python-скриптом через `docker run python:3-alpine`, том `vm-proxy-02_npm-data`. После обновления записи NPM перезапущен.

### 2026-04-14 — Перегенерация просроченного SSL-сертификата *.home.loc

- **Тип:** fixed
- **VM:** vm-proxy-02
- **Описание:** Истёк самоподписанный wildcard сертификат `*.home.loc` (выпущен на 1 год, просрочен 2026-04-13). Запущен `vm-proxy-02/ssl/generate-ssl.sh`, новый сертификат выпущен на 10 лет (notAfter: 2036-04-11). Файлы заменены напрямую в Docker volume `vm-proxy-02_npm-data` через alpine-контейнер, выполнен `nginx -s reload` внутри NPM. CA-сертификат установлен в Trusted Root на Windows PC (Cert:\LocalMachine\Root, thumbprint E6FB4285D74806654389F8D19554D788895F9713, expires 2036).

### 2026-04-14 — Добавлен Homepage dashboard на vm-proxy-02

- **Тип:** added
- **VM:** vm-proxy-02
- **Описание:** Развёрнут Homepage (ghcr.io/gethomepage/homepage:latest) на порту 3000. Конфиги в `vm-proxy-02/configs/homepage/` (services, widgets, settings, bookmarks, docker.yaml). NPM и Homepage объединены в сеть `proxy-net`. Исправлены IP-адреса VM во всех docs (vm-db-02: 192.168.1.52→192.168.1.36, vm-proxy-02: 192.168.1.51→192.168.1.37), исправлен SSH-пользователь (gv→user-home).
- **Коммит:** 415a8d2

### 2026-04-14 — Добавлена документация проекта

- **Тип:** added
- **VM:** all
- **Описание:** Создана полная документация в `docs/`: overview, services, changelog, decisions, runbooks, troubleshooting, vm-setup. Обновлён `QWEN.md`.
- **Коммит:** 1fa026e

### 2026-04-14 — Развёрнуты vm-db-02 и vm-proxy-02

- **Тип:** added
- **VM:** vm-db-02, vm-proxy-02
- **Описание:** Добавлена вторая пара VM для homelab. vm-db-02 (192.168.1.36): PostgreSQL 16, Vaultwarden, pgAdmin на сети db-net. vm-proxy-02 (192.168.1.37): Nginx Proxy Manager + dnsmasq.
- **Версии:** postgres:16, vaultwarden/server:latest, dpage/pgadmin4:latest, jc21/nginx-proxy-manager:latest
- **Коммит:** 5786f5b

### 2026-04-14 — Добавлен QWEN.md

- **Тип:** added
- **VM:** all
- **Описание:** Добавлен файл контекста для Qwen Code с описанием структуры репозитория.
- **Коммит:** 98fe0f1

### 2026-04-14 — Исправлена настройка DNS на vm-proxy-01

- **Тип:** fixed
- **VM:** vm-proxy-01
- **Описание:** Прописан временный DNS перед остановкой systemd-resolved.
- **Коммит:** 664f035

### 2026-04-14 — Добавлен sync.sh для vm-proxy-01

- **Тип:** added
- **VM:** vm-proxy-01
- **Описание:** Скрипт `sync.sh` автоматизирует git sparse checkout обновление.
- **Коммит:** 1dd9447

### 2026-04-14 — Добавлены Split-DNS и NPM на vm-proxy-01

- **Тип:** added
- **VM:** vm-proxy-01
- **Описание:** Развёрнуты dnsmasq (split-DNS для *.home.loc) и Nginx Proxy Manager.
- **Коммит:** 4be87ae

### 2025-xx-xx — Развёрнута vm-db-01 (legacy)

- **Тип:** added
- **VM:** vm-db-01
- **Описание:** Первая VM с PostgreSQL 16.4, Vaultwarden 1.32.5, pgAdmin 8.12. Сервисы на сети db-internal.
- **Версии:** postgres:16.4, vaultwarden/server:1.32.5, dpage/pgadmin4:8.12
- **Коммит:** c50b00e

### 2025-xx-xx — Развёрнута vm-proxy-01 (legacy)

- **Тип:** added
- **VM:** vm-proxy-01
- **Описание:** Первая proxy VM с dnsmasq и Nginx Proxy Manager. IP: 192.168.1.50
