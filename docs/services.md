# Описание сервисов

## Для чего этот документ и как вести?

Этот документ — справочник по каждому сервису, работающему в homelab. Здесь фиксируется не только что сервис делает, но и как он настроен, какие использует порты, базы данных, переменные окружения и от каких других сервисов зависит.

**Что должно быть в этом документе:**

Для каждого сервиса:

- **Название и версия** (например, PostgreSQL 16.4)
- **Назначение** — зачем этот сервис нужен в инфраструктуре
- **VM-хост** — на какой виртуальной машине работает
- **Порты** — какие порты использует, куда проброшены
- **Переменные окружения** — какие использует, где берутся значения
- **Зависимости** — от каких сервисов зависит и какие сервисы зависят от него
- **Volumes** — какие Docker volumes использует, где хранятся данные на хосте
- **Healthcheck** — как проверяется работоспособность
- **Конфигурационные файлы** — пути к конфигам, краткое описание ключевых параметров
- **Особенности** — всё, что важно знать при эксплуатации

**Правила документирования:**

- Каждый сервис — отдельный подраздел второго уровня (`##`)
- Группировать сервисы по VM-хостам
- При обновлении версии сервиса — указывать дату и что изменилось
- Не дублировать информацию из `docker-compose.yml` — описывать смысл, а не копировать YAML
- Если сервис использует БД — указать какая БД и кто её владелец
- Особо отмечать параметры, которые нельзя менять без перезапуска
- Добавлять ссылки на официальную документацию сервиса

---

## vm-db-02 (192.168.1.52)

### PostgreSQL 16

- **Назначение:** Реляционная СУБД для Vaultwarden и будущего расширения
- **Образ:** `postgres:16`
- **Порты:** `5432:5432` (проброшен на LAN VM)
- **Сеть:** `db-net` (bridge)
- **Переменные окружения:**
  - `POSTGRES_USER` — суперпользователь БД (из `.env`)
  - `POSTGRES_PASSWORD` — пароль суперпользователя (из `.env`)
  - `POSTGRES_DB` — основная БД по умолчанию (из `.env`)
- **Volumes:** `postgres-data` → `/var/lib/postgresql/data`
- **Healthcheck:** `pg_isready -U $POSTGRES_USER -d $POSTGRES_DB` каждые 10с
- **Инициализация:** Скрипты из `init-scripts/` выполняются при первом старте:
  - `01-init-vaultwarden-db.sql` — создаёт пользователя `vw_user`, БД `vaultwarden`, выдаёт права
  - Использует `\getenv` для чтения переменных окружения
- **Особенности:**
  - Порт 5432 проброшен на LAN — доступен другим VM
  - На vm-db-02 все сервисы изолированы в Docker network `db-net`
  - Major upgrade (16→17) требует `pg_dumpall` — нельзя просто сменить тег образа
- **Документация:** https://hub.docker.com/_/postgres

### Vaultwarden

- **Назначение:** Легковесный совместимый менеджер паролей (Bitwarden-альтернатива)
- **Образ:** `vaultwarden/server:latest`
- **Порты:** `8080:80`
- **Сеть:** `db-net` (bridge)
- **Переменные окружения:**
  - `DATABASE_URL` — строка подключения к PostgreSQL: `postgresql://vw_user:PASSWORD@postgres:5432/vaultwarden`
  - `DOMAIN` — `https://vw.home.loc`
  - `WEBSOCKET_ENABLED=true` — включены WebSocket для real-time sync
- **Volumes:** `vaultwarden-data` → `/data`
- **Зависимости:** `depends_on: postgres (condition: service_healthy)`
- **Healthcheck:** `curl -f http://localhost:80/alive` каждые 10с
- **Особенности:**
  - Подключается к PostgreSQL по имени контейнера `postgres` (Docker DNS)
  - При смене `DATABASE_URL` требуется рестарт контейнера
- **Документация:** https://github.com/dani-garcia/vaultwarden

### pgAdmin 4

- **Назначение:** Веб-интерфейс администрирования PostgreSQL
- **Образ:** `dpage/pgadmin4:latest`
- **Порты:** `5050:80`
- **Сеть:** `db-net` (bridge)
- **Переменные окружения:**
  - `PGADMIN_DEFAULT_EMAIL` — email администратора (из `.env`, например `admin@home.loc`)
  - `PGADMIN_DEFAULT_PASSWORD` — пароль администратора (из `.env`)
- **Volumes:** `pgadmin-data` → `/var/lib/pgadmin`
- **Зависимости:** `depends_on: postgres (condition: service_healthy)`
- **Healthcheck:** `wget -qO- http://localhost:80/misc/ping` каждые 10с
- **Особенности:**
  - `start_period: 60s` — дольше прогревается, т.к. инициализирует internal БД
  - Доступен на LAN: `http://192.168.1.52:5050`
- **Документация:** https://www.pgadmin.org/docs/pgadmin4/latest/

---

## vm-proxy-02 (192.168.1.51)

### Nginx Proxy Manager

- **Назначение:** Reverse proxy с SSL-терминацией (Let's Encrypt) и веб-UI управления
- **Образ:** `jc21/nginx-proxy-manager:latest`
- **Порты:**
  - `80:80` — HTTP (редирект на HTTPS)
  - `443:443` — HTTPS (SSL termination)
  - `81:81` — Admin UI
- **Переменные окружения:**
  - `INITIAL_ADMIN_EMAIL` — email администратора для первого входа (из `.env`)
  - `INITIAL_ADMIN_PASSWORD` — пароль для первого входа (из `.env`)
  - **Важно:** после первого входа сменить пароль в UI (Admin > Change Credentials)
- **Volumes:**
  - `npm-data` → `/data` — конфигурация NPM, SQLite БД
  - `npm-letsencrypt` → `/etc/letsencrypt` — SSL-сертификаты Let's Encrypt
- **Healthcheck:** `/usr/bin/check-health` каждые 10с
- **Особенности:**
  - Версия образа `latest` — осознанный компромисс, т.к. NPM не выпускает стабильные теги регулярно
  - SSL-сертификаты можно генерировать вручную через `ssl/generate-ssl.sh` (self-signed wildcard для `*.home.loc`)
  - Обратные прокси настраиваются через Admin UI (`http://192.168.1.51:81`)
- **Документация:** https://nginxproxymanager.com/

### dnsmasq (split-DNS)

- **Назначение:** DNS-сервер с split-DNS для локального домена `*.home.loc`
- **Установка:** Не Docker-сервис, устанавливается напрямую на VM через `deploy-dnsmasq.sh`
- **Порты:** `53` (UDP/TCP)
- **Конфигурация:** Локальные DNS-записи направляют `*.home.loc` → `192.168.1.51` (NPM)
- **Особенности:**
  - Требует остановки `systemd-resolved` перед установкой
  - Временный DNS прописывается до полной настройки
  - Для каждого нового сервиса добавляется запись в конфиг dnsmasq
- **Документация:** https://thekelleys.org.uk/dnsmasq/doc.html
