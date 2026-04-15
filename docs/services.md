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

## vm-db-01 (192.168.1.36)

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
  - На vm-db-01 все сервисы изолированы в Docker network `db-net`
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
  - Доступен на LAN: `http://192.168.1.36:5050`
- **Документация:** https://www.pgadmin.org/docs/pgadmin4/latest/

### frpc (FRP-клиент)

- **Назначение:** Создаёт исходящий туннель от vm-db-01 к frps на VPS, пробрасывая локальные порты для доступа из интернета через NPM.
- **Образ:** `snowdreamtech/frpc:latest`
- **Сеть:** `network_mode: host` — контейнер видит `127.0.0.1` хоста, что позволяет подключаться к Vaultwarden и pgAdmin по их локальным портам.
- **Конфиг:** `frpc/frpc.toml` (генерируется `frpc-setup.sh`, права 600, не коммитится в git)
- **Volumes:** `./frpc.toml:/etc/frp/frpc.toml:ro`
- **Healthcheck:** `pgrep frpc` каждые 30с
- **Туннели (remotePort на VPS → localPort на vm-db-01):**
  - `18080` → `8080` (Vaultwarden)
  - `15050` → `5050` (pgAdmin)
- **Установка:** `sudo bash vm-db-01/frpc-setup.sh` — интерактивный скрипт, запрашивает IP VPS, токен, порты.
- **Документация:** [github.com/fatedier/frp](https://github.com/fatedier/frp)

---

## vps-ru-proxy (Timeweb VPS, Debian 12)

Стек развёртывается скриптом `vps-ru-proxy/setup.sh`. Конфиги и образы — в `vps-ru-proxy/`.

### Nginx Proxy Manager

- **Назначение:** SSL-терминация (Let's Encrypt), HTTP/HTTPS reverse proxy по доменным именам.
- **Образ:** `jc21/nginx-proxy-manager:latest`
- **Порты:** `80:80`, `443:443`, `81:81` (UI администрирования)
- **Сеть:** `proxy-net` (bridge)
- **Volumes:** `./npm/data:/data`, `./npm/letsencrypt:/etc/letsencrypt`
- **БД:** SQLite — файл `/data/database.sqlite` внутри volume `./npm/data`. MariaDB не нужна.
- **Особенности:**
  - Первый вход: `admin@example.com` / `changeme` — сменить сразу.
  - Proxy Host для туннельных сервисов: Scheme `http`, Forward Hostname — имя контейнера `frps`, WebSockets включить для Vaultwarden.
  - `Force SSL` включать только после получения сертификата Let's Encrypt.
- **Документация:** [nginxproxymanager.com](https://nginxproxymanager.com/guide/)

### frps (FRP-сервер)

- **Назначение:** Принимает входящие туннельные соединения от frpc на vm-db-01.
- **Образ:** `snowdreamtech/frps:latest`
- **Порты:** `7000:7000` (bind port для frpc), `7500:7500` (веб-дашборд)
- **Сеть:** `proxy-net` (bridge)
- **Конфиг:** `frps/frps.toml` (генерируется из шаблона `frps.toml` через `envsubst` в setup.sh; содержит токен — не коммитить).
- **Volumes:** `./frps/frps.toml:/etc/frp/frps.toml:ro`
- **Переменные:** `FRP_TOKEN`, `FRP_DASHBOARD_PASSWORD` — из `.env`.
- **Особенности:**
  - Веб-дашборд доступен напрямую по `http://VPS_IP:7500` и через NPM как `https://frp-ui.gv-services.net.ru`.
  - При проксировании через NPM Forward Hostname = `frps` (container DNS в proxy-net), Scheme = `http`.
- **Документация:** [github.com/fatedier/frp](https://github.com/fatedier/frp)
