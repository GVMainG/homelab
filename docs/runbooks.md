# Пошаговые инструкции (Runbooks)

## Для чего этот документ и как вести?

Этот документ содержит готовые пошаговые инструкции для типовых операционных задач в homelab. Каждый runbook — это рецепт, по которому можно выполнить задачу без дополнительных исследований, даже в стрессовой ситуации (например, ночью при инциденте).

**Что должно быть в этом документе:**

Для каждой операции:

- **Название** — что делает эта инструкция
- **Когда применять** — в какой ситуации этот runbook нужен
- **Предусловия** — что должно быть готово перед выполнением
- **Шаги** — нумерованный список команд и действий
- **Проверка** — как убедиться, что всё прошло успешно
- **Откат** — что делать, если что-то пошло не так

Примеры runbook'ов для добавления:

- Добавление нового сервиса в docker-compose
- Добавление нового домена/subdomain в Nginx Proxy Manager
- Создание новой VM и подключение её к инфраструктуре
- PostgreSQL major upgrade (например, 16 → 17)
- Обновление SSL-сертификатов
- Сброс пароля администратора (NPM, pgAdmin, Vaultwarden)
- Добавление нового DNS-записи в dnsmasq
- Очистка Docker volumes и unused images
- Замена IP-адреса VM

**Правила документирования:**

- Каждый runbook — отдельный подраздел (`##`) с понятным названием
- Шаги должны быть нумерованы и содержать конкретные команды (не «настройте сервис», а «выполните: ...»)
- Все команды должны быть безопасны для копи-паста (без хардкода секретов)
- В каждом runbook указывать приблизительное время выполнения
- Особо отмечать шаги, после которых откат невозможен или сложен
- Проверять каждый runbook на практике перед публикацией
- Обновлять при изменении процедур (версии, пути, команды)
- Если runbook стал неактуален — не удалять, а пометить как `DEPRECATED` с датой и причиной

---

## Обновление конфигурации из репозитория

**Когда применять:** После изменения конфигов в git, перед перезапуском сервисов.

**Предусловия:** VM имеет доступ к GitHub, git установлен, sparse checkout настроен.

**Шаги:**

1. SSH на нужную VM:
   ```bash
   ssh user-home@192.168.1.36   # vm-db-02
   ssh user-home@192.168.1.37   # vm-proxy-02
   ```

2. Перейти в директорию homelab и запустить sync:
   ```bash
   cd /opt/homelab
   bash vm-db-02/sync.sh   # или vm-proxy-02/sync.sh
   ```

3. Обновить Docker-образы и перезапустить:
   ```bash
   cd vm-db-02   # или vm-proxy-02
   docker compose pull && docker compose up -d --remove-orphans
   ```

**Проверка:**
```bash
docker compose ps    # все сервисы должны быть Up/healthy
git status           # без локальных изменений
```

**Откат:**
```bash
git checkout -- .    # отменить локальные изменения
docker compose down  # остановить, если что-то сломалось
```

---

## Развёртывание нового сервиса в docker-compose

**Когда применять:** Нужно добавить новый сервис на существующую VM.

**Предусловия:** Доступ к VM, понимание конвенций Docker Compose проекта.

**Шаги:**

1. Добавить секцию сервиса в `docker-compose.yml`:
   - Указать `image` с версией (кроме NPM)
   - Добавить `container_name`, `restart: unless-stopped`
   - Добавить `env_file: .env`
   - Настроить `ports` с префиксом `127.0.0.1:` если не нужен внешний доступ
   - Добавить `volumes` для персистентных данных
   - Подключить к `db-net`
   - Добавить `healthcheck`
   - Добавить `depends_on` с `condition: service_healthy` если нужен PostgreSQL

2. Добавить переменные в `.env.example`:
   - Все `${VAR}` из `docker-compose.yml` должны быть в `.env.example` с `CHANGE_ME`

3. Закоммитить изменения, сделать push.

4. На VM:
   ```bash
   bash vm-db-02/sync.sh
   cd vm-db-02
   # Проверить что .env содержит все новые переменные
   docker compose up -d --remove-orphans
   docker compose ps
   ```

5. Добавить запись в `dnsmasq` (если нужен домен):
   - На vm-proxy-02: отредактировать конфиг dnsmasq, добавить `address=/newservice.home.loc/192.168.1.37`
   - Перезапустить: `sudo systemctl restart dnsmasq`

6. Настроить reverse proxy в NPM UI (`http://192.168.1.37:81`).

**Проверка:**
```bash
docker compose ps              # новый сервис в статусе Up/healthy
curl http://192.168.1.36:PORT  # сервис отвечает
```

**Откат:**
```bash
docker compose rm -sf <service>   # удалить контейнер
# Удалить секцию из docker-compose.yml, sync, docker compose up -d
```

---

## Создание бэкапа PostgreSQL

**Когда применять:** Перед изменениями, плановый бэкап, перед upgrade.

**Предусловия:** Доступ к vm-db-02, достаточно места на диске.

**Шаги:**

1. SSH на vm-db-02:
   ```bash
   ssh user-home@192.168.1.36
   ```

2. Создать бэкап:
   ```bash
   docker exec postgres pg_dumpall -U admin > /opt/homelab/backups/full-$(date +%Y%m%d-%H%M%S).sql
   ```

3. Проверить размер файла:
   ```bash
   ls -lh /opt/homelab/backups/
   ```

**Проверка:** Файл бэкапа существует, размер > 0, можно восстановить:
```bash
head -5 /opt/homelab/backups/full-YYYYMMDD.sql
```

**Откат:** Не применимо — бэкап не изменяет данные.

---

## Сброс пароля администратора Nginx Proxy Manager

**Когда применять:** Забыт пароль от Admin UI NPM.

**Предусловия:** Доступ к vm-proxy-02.

**Шаги:**

1. SSH на vm-proxy-02:
   ```bash
   ssh user-home@192.168.1.37
   cd /opt/homelab/vm-proxy-02
   ```

2. Остановить NPM:
   ```bash
   docker compose down
   ```

3. Сбросить пароль через SQLite (NPM хранит в `/data/database.sqlite`):
   ```bash
   docker run --rm -v npm-data:/data alpine sh -c "apk add sqlite && sqlite3 /data/database.sqlite \"UPDATE user SET password='\\$argon2id\\$v=19\\$m=65536,t=3,p=4\\$...' WHERE email='admin@home.loc';\""
   ```
   **ИЛИ** проще — удалить БД и пересоздать (потеря конфигов proxy):
   ```bash
   docker volume rm vm-proxy-02_npm-data
   docker compose up -d
   # Войти с INITIAL_ADMIN_EMAIL/INITIAL_ADMIN_PASSWORD из .env
   ```

**Проверка:** `http://192.168.1.37:81` — вход работает.

**Откат:** Если удалена БД — воссоздать reverse proxy записи через UI.

---

## Добавление нового домена в dnsmasq

**Когда применять:** Новый сервис needs DNS-запись вида `service.home.loc`.

**Предусловия:** Доступ к vm-proxy-02, root.

**Шаги:**

1. SSH на vm-proxy-02:
   ```bash
   ssh user-home@192.168.1.37
   ```

2. Добавить запись в конфиг dnsmasq (файл зависит от конфигурации, обычно `/etc/dnsmasq.d/01-split-dns.conf`):
   ```bash
   sudo nano /etc/dnsmasq.d/01-split-dns.conf
   # Добавить: address=/newservice.home.loc/192.168.1.37
   ```

3. Перезапустить dnsmasq:
   ```bash
   sudo systemctl restart dnsmasq
   ```

**Проверка:**
```bash
dig newservice.home.loc @192.168.1.37   # должен вернуть 192.168.1.37
```

**Откат:** Удалить строку из конфига, `sudo systemctl restart dnsmasq`.
