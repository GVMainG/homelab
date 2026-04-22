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
- **Запуск:** `docker run --network host` — контейнер видит `127.0.0.1` хоста, что позволяет подключаться к Vaultwarden и pgAdmin по их локальным портам.
- **Конфиг:** `frp/frpc.toml` (генерируется `frp-setup.sh`, права 600, не коммитится в git)
- **Туннели (remotePort на VPS → localPort на vm-db-01):**
  - `18080` → `8080` (Vaultwarden)
  - `15050` → `5050` (pgAdmin)
- **Установка:** `sudo bash vm-db-01/frp-setup.sh` → выбрать режим `1) Клиент`, ввести IP VPS, токен, порты.
- **Управление:** `docker logs -f frpc` / `docker stop frpc && docker rm frpc`
- **Документация:** [github.com/fatedier/frp](https://github.com/fatedier/frp)

### Hawser (агент Dockhand)

- **Назначение:** Агент, который позволяет Dockhand управлять Docker на vm-db-01 удалённо (просмотр контейнеров, запуск стеков, терминал).
- **Образ:** `ghcr.io/finsys/hawser:latest`
- **Запуск:** `docker run` — два режима:
  - **Standard:** `-p 2376:2376` — агент слушает порт, Dockhand подключается (подходит для LAN)
  - **Edge:** `-e DOCKHAND_SERVER_URL=...` — агент сам подключается к Dockhand по WebSocket (подходит для NAT)
- **Установка:** `sudo bash vm-db-01/run-hawser.sh` — интерактивный выбор режима, токена, имени агента.
- **Управление:** `docker logs -f hawser` / `docker stop hawser && docker rm hawser`
- **Документация:** [github.com/Finsys/hawser](https://github.com/Finsys/hawser)

---

## vm-DevOps-01 (192.168.1.XX)

### Dockhand

- **Назначение:** Веб-интерфейс управления Docker-инфраструктурой homelab: контейнеры, Compose-стеки, логи, терминал, удалённые агенты.
- **Образ:** `fnsys/dockhand:latest` (нет стабильных версионированных тегов)
- **Порты:** `3000:3000` (веб-UI)
- **Переменные окружения:**
  - `ENCRYPTION_KEY` — AES-256 ключ для шифрования учётных данных (из `.env`). **Нельзя менять после первого запуска** — сохранённые credentials станут нечитаемыми.
  - `PUID`, `PGID` — UID/GID пользователя внутри контейнера
- **Volumes:** `dockhand-data` → `/app/data` (SQLite, git-репо стеков)
- **Healthcheck:** `wget -qO- http://localhost:3000` каждые 30с
- **Особенности:**
  - Аутентификация отключена при первом запуске — включить в Settings → Authentication
  - Управляет локальным Docker через `/var/run/docker.sock`
  - Удалённые VM управляются через агентов Hawser (`run-hawser.sh`)
- **Документация:** [github.com/Finsys/dockhand](https://github.com/Finsys/dockhand)

### frpc (FRP-клиент, Dockhand → VPS)

- **Назначение:** Создаёт исходящий туннель от vm-DevOps-01 к frps на VPS для доступа к Dockhand UI из интернета.
- **Образ:** `snowdreamtech/frpc:latest`
- **Запуск:** `docker run --network host`
- **Конфиг:** `frp/frpc.toml` (генерируется `frp-setup.sh`, права 600)
- **Туннели (remotePort на VPS → localPort на vm-DevOps-01):**
  - `13000` → `3000` (Dockhand)
- **Установка:** `sudo bash vm-DevOps-01/frp-setup.sh` → выбрать `1) Клиент`
- **Документация:** [github.com/fatedier/frp](https://github.com/fatedier/frp)

---

## vm-apps-01 (192.168.1.YY)

### MeTube

- **Назначение:** Веб-интерфейс для загрузки видео с YouTube и других видеоплатформ, основан на yt-dlp.
- **Образ:** `ghcr.io/alexta69/metube:latest`
- **Порты:** `8081:8081` (веб-UI)
- **Переменные окружения:**
  - `YTDL_FORMAT` — формат загрузки видео (по умолчанию `bestvideo+bestaudio/best`)
  - `YTDL_EXTRACT_AUDIO_FORMAT` — формат извлекаемого звука (mp3, m4a, opus, vorbis, wav, aac)
  - `YTDL_EXTRACT_AUDIO_QUALITY` — качество звука в кбит/с (128, 192, 256, 320)
  - `YTDL_KEEP_ORIGINAL_AUDIO` — сохранять оригинальный звук при извлечении (true/false)
  - `YTDL_PREFER_FFI` — использовать новый движок выбора формата (true/false)
- **Volumes:** `metube-downloads` → `/downloads` (хранение загруженных видео)
- **Healthcheck:** `curl -f http://localhost:8081/` каждые 30с
- **Особенности:**
  - Нет зависимостей от БД
  - Веб-интерфейс доступен на LAN: `http://192.168.1.YY:8081`
  - Загруженные видео сохраняются в Docker volume для сохранения при обновлении контейнера
- **Управление:** `docker compose logs -f metube` / `docker compose ps`
- **Документация:** [github.com/alexta69/metube](https://github.com/alexta69/metube)

### Planka

- **Назначение:** Kanban-доска для управления проектами и задачами (аналог Trello).
- **Образ:** `plankanban/planka:1.122.0`
- **Порты:** `8082:1337` (веб-UI)
- **БД:** PostgreSQL (на vm-db-01, заводская БД `planka`, пользователь `planka_user`)
- **Переменные окружения:**
  - `DATABASE_URL` — строка подключения к PostgreSQL: `postgresql://planka_user:PASSWORD@192.168.1.36:5432/planka`
  - `BASE_URL` — базовый URL приложения для фронтенда (например, `192.168.1.YY:8082`)
  - `SECRET_KEY` — ключ для шифрования сессий (генерируется при первом запуске)
- **Volumes:** `planka-attachments` → `/app/attachments` (загруженные файлы, аватары, изображения доски)
- **Зависимости:** PostgreSQL на vm-db-01
- **Healthcheck:** `wget -qO- http://localhost:1337/health` каждые 30с
- **Инициализация БД:**
  - При первом запуске на vm-db-01 запустить скрипт инициализации: `docker compose up -d` автоматически создаёт пользователя и БД из `init-scripts/02-init-planka-db.sql`
  - Сама Planka инициализирует schema при первом подключении
- **Особенности:**
  - Веб-интерфейс доступен на LAN: `http://192.168.1.YY:8082`
  - При обновлении версии могут требоваться миграции БД (читать release notes)
  - `SECRET_KEY` нельзя менять после первого запуска — encrypted данные станут нечитаемыми
- **Управление:** `docker compose logs -f planka` / `docker compose ps`
- **Документация:** [github.com/plankanban/planka](https://github.com/plankanban/planka)

---

## vps-ru-proxy (Timeweb VPS, Debian 12)

Стек развёртывается скриптом `vps-ru-proxy/first-deployment.sh`. Конфиги и образы — в `vps-ru-proxy/`.

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

- **Назначение:** Принимает входящие туннельные соединения от frpc на LAN-VM, открывает remotePort для каждого туннеля.
- **Образ:** `snowdreamtech/frps:latest`
- **Запуск:** `docker run --network host` — все порты напрямую на хосте VPS.
- **Порты (хост):** `7000` (bind port для frpc), `7500` (веб-дашборд), динамические remotePort (18080, 15050, 13000 и т.д.)
- **Конфиг:** `frp/frps.toml` (генерируется `frp-setup.sh`, права 600, содержит токен — не коммитить).
- **Установка:** `sudo bash vps-ru-proxy/frp-setup.sh` → выбрать `2) Сервер`, токен и пароль дашборда генерируются автоматически.
- **Особенности:**
  - Веб-дашборд: `http://VPS_IP:7500` / `https://frp-ui.gv-services.net.ru`
  - frps работает в `--network host`, NPM — в bridge `proxy-net`. Для проксирования туннелей в NPM использовать IP хоста VPS (не `frps` и не `127.0.0.1`): Forward Hostname = `VPS_IP`, Port = `<remotePort>`.
- **Управление:** `docker logs -f frps` / `docker stop frps && docker rm frps`
- **Документация:** [github.com/fatedier/frp](https://github.com/fatedier/frp)
