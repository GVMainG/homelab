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

## Развёртывание VPS-стека (vps-ru-proxy)

**Когда применять:** Первичная установка на новом VPS или полная переустановка.

**Предусловия:** Windows ПК с OpenSSH, VPS на Debian 12 с SSH-доступом от root.

**Шаги:**

1. На Windows — скопировать файлы и запустить setup.sh:

   ```powershell
   cd C:\путь\к\homelab
   .\vps-ru-proxy\deploy.ps1
   # Скрипт интерактивно запросит IP VPS, пользователя, SSH-ключ
   # На вопрос "Запустить setup.sh?" ответить Y
   ```

2. setup.sh выполнит на VPS: apt upgrade, установку Docker, генерацию `.env` (токен FRP, пароль дашборда), настройку frps из шаблона, fail2ban, запуск `docker compose up -d`.

3. После завершения setup.sh запишет вывод — сохранить `FRP_TOKEN` и `FRP_DASHBOARD_PASSWORD`.

**Проверка:**

```bash
ssh root@VPS_IP "cd /opt/vps-ru-proxy && docker compose ps"
# Все сервисы: npm (healthy), frps (Up)
# NPM UI: http://VPS_IP:81
# frps dashboard: http://VPS_IP:7500
```

**Откат:** `docker compose down` на VPS. Удалить `/opt/vps-ru-proxy`.

---

## Настройка frpc на vm-db-01

**Когда применять:** Подключение vm-db-01 к VPS-туннелю после развёртывания vps-ru-proxy.

**Предусловия:** VPS-стек запущен, известны IP VPS и FRP_TOKEN (из вывода setup.sh или `/opt/vps-ru-proxy/.env`).

**Шаги:**

1. SSH на vm-db-01:

   ```bash
   ssh user-home@192.168.1.36
   cd /opt/homelab
   ```

2. Запустить интерактивный скрипт:

   ```bash
   sudo bash vm-db-01/frpc-setup.sh
   # Ввести: IP VPS, FRP_TOKEN, порты (дефолты: 7000, 18080, 15050)
   ```

3. Скрипт создаст `vm-db-01/frpc/frpc.toml` (права 600) и `frpc/docker-compose.yml`, запустит контейнер.

**Проверка:**

```bash
docker compose -f /opt/homelab/vm-db-01/frpc/docker-compose.yml ps
docker compose -f /opt/homelab/vm-db-01/frpc/docker-compose.yml logs -f
# На VPS: http://VPS_IP:7500 — в дашборде должны появиться активные туннели
```

**Откат:** `docker compose -f frpc/docker-compose.yml down`

---

## Добавление нового Proxy Host в NPM

**Когда применять:** Нужно опубликовать новый сервис через домен.

**Предусловия:** DNS A-запись на VPS_IP уже настроена, сервис запущен.

**Шаги:**

1. Открыть NPM: `http://VPS_IP:81`

2. Proxy Hosts → Add Proxy Host:
   - **Domain Names:** `subdomain.gv-services.net.ru`
   - **Scheme:** `http`
   - **Forward Hostname:** имя контейнера на proxy-net (например `frps`) или `127.0.0.1` для сервисов на хосте
   - **Forward Port:** порт сервиса
   - **WebSockets Support:** включить для Vaultwarden

3. Вкладка **SSL**:
   - SSL Certificate → Request a new SSL Certificate
   - Force SSL: включить только после успешного получения сертификата
   - Email для Let's Encrypt: указать реальный

4. Сохранить. NPM автоматически получит сертификат через HTTP-01 challenge.

**Проверка:** Открыть `https://subdomain.gv-services.net.ru` — сертификат валиден, сервис отвечает.

**Типичные ошибки:**

- **502/503** — NPM не может достучаться до upstream. Проверить: `docker exec <npm-container> curl http://<hostname>:<port>`
- **DNS не резолвится** — ждать TTL (обычно 5–60 мин после добавления A-записи)
- **Let's Encrypt rate limit** — максимум 5 cert на домен/час; при ошибке подождать

---

## Обновление конфигурации из репозитория

**Когда применять:** После изменения конфигов в git, перед перезапуском сервисов.

**Предусловия:** VM имеет доступ к GitHub, git установлен, sparse checkout настроен.

**Шаги:**

1. SSH на vm-db-01:

   ```bash
   ssh user-home@192.168.1.36
   ```

2. Перейти в директорию homelab и запустить sync:

   ```bash
   cd /opt/homelab
   bash vm-db-01/sync.sh
   ```

3. Обновить Docker-образы и перезапустить:

   ```bash
   cd vm-db-01
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

**Когда применять:** Нужно добавить новый сервис на vm-db-01.

**Предусловия:** Доступ к VM, понимание конвенций Docker Compose проекта.

**Шаги:**

1. Добавить секцию сервиса в `docker-compose.yml`:
   - Указать `image` с версией
   - Добавить `container_name`, `restart: unless-stopped`
   - Добавить `env_file: .env`
   - Настроить `ports` с нужным портом
   - Добавить `volumes` для персистентных данных
   - Подключить к `db-net`
   - Добавить `healthcheck`
   - Добавить `depends_on` с `condition: service_healthy` если нужен PostgreSQL

2. Добавить переменные в `.env.example`:
   - Все `${VAR}` из `docker-compose.yml` должны быть в `.env.example` с `CHANGE_ME`

3. Закоммитить изменения, сделать push.

4. На VM:

   ```bash
   bash vm-db-01/sync.sh
   cd vm-db-01
   docker compose up -d --remove-orphans
   docker compose ps
   ```

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

**Предусловия:** Доступ к vm-db-01, достаточно места на диске.

**Шаги:**

1. SSH на vm-db-01:

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

## Очистка Docker (unused images, volumes, logs)

**Когда применять:** Место на диске заполнено, плановая очистка.

**Предусловия:** Доступ к vm-db-01.

**Шаги:**

1. SSH на vm-db-01:

   ```bash
   ssh user-home@192.168.1.36
   ```

2. Проверить использование места:

   ```bash
   df -h
   docker system df
   ```

3. Очистить:

   ```bash
   # Удалить unused images
   docker image prune -a

   # Удалить unused volumes (ОСТОРОЖНО — данные будут потеряны!)
   docker volume prune

   # Очистить старые бэкапы PostgreSQL (оставить последние 7 дней)
   find /opt/homelab/backups/ -name "*.sql" -mtime +7 -delete
   ```

**Проверка:** `df -h` — место освободилось.

**Откат:** Удалённые images будут скачаны заново при `docker compose pull`. Volumes восстановить из backup.
