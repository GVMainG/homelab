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

**Предусловия:** VPS на Debian 12 с SSH-доступом от root.

**Шаги:**

1. Bootstrap одной командой на VPS:

   ```bash
   bash <(curl -fsSL https://raw.githubusercontent.com/GVMainG/homelab/main/vps-ru-proxy/first-deployment.sh)
   ```

   Скрипт выполнит: клонирование репо (sparse checkout), `apt upgrade`, установку Docker, fail2ban, запуск NPM.

2. После завершения — запустить FRP-сервер:

   ```bash
   sudo bash /opt/homelab/vps-ru-proxy/frp-setup.sh
   # Выбрать: 2) Сервер
   # Токен и пароль дашборда будут сгенерированы автоматически — сохранить их
   ```

**Проверка:**

```bash
# NPM запущен
docker compose -f /opt/homelab/vps-ru-proxy/docker-compose.yml ps
# NPM UI: http://VPS_IP:81

# frps запущен
docker ps | grep frps
# frps dashboard: http://VPS_IP:7500
```

**Откат:** `docker compose down` (NPM) + `docker stop frps && docker rm frps`. Удалить `/opt/homelab/vps-ru-proxy`.

---

## Настройка FRP-туннеля на LAN-VM

**Когда применять:** Подключение vm-db-01 или vm-DevOps-01 к VPS-туннелю после развёртывания vps-ru-proxy.

**Предусловия:** frps на VPS запущен, известны IP VPS и FRP_TOKEN (из вывода `frp-setup.sh` на VPS).

**Шаги:**

1. SSH на VM:

   ```bash
   ssh user-home@192.168.1.36   # vm-db-01
   # или ssh user-home@192.168.1.XX   # vm-DevOps-01
   ```

2. Запустить интерактивный скрипт:

   ```bash
   sudo bash /opt/homelab/vm-db-01/frp-setup.sh
   # Выбрать: 1) Клиент
   # Ввести: IP VPS, FRP_TOKEN, порты (дефолты: vaultwarden=18080, pgadmin=15050)
   ```

   Скрипт создаст `frp/frpc.toml` (права 600) и запустит `docker run frpc --network host`.

**Проверка:**

```bash
docker ps | grep frpc
docker logs -f frpc
# На VPS: http://VPS_IP:7500 — в дашборде должны появиться активные туннели
```

**Откат:** `docker stop frpc && docker rm frpc`

---

## Первичный деплой новой VM (first-deployment.sh)

**Когда применять:** Создание новой VM в Proxmox и первичное развёртывание сервисов.

**Предусловия:** VM на Debian 12, SSH-доступ от root, интернет.

**Шаги:**

1. Bootstrap одной командой (запускать **от root** прямо на VM):

   ```bash
   # vm-db-01
   bash <(curl -fsSL https://raw.githubusercontent.com/GVMainG/homelab/main/vm-db-01/first-deployment.sh)

   # vm-DevOps-01
   bash <(curl -fsSL https://raw.githubusercontent.com/GVMainG/homelab/main/vm-DevOps-01/first-deployment.sh)
   ```

   Скрипт: клонирует репо (sparse checkout в `/opt/homelab`), обновляет систему, ставит Docker, генерирует `.env`, запускает `docker compose up -d`.

2. Записать учётные данные из вывода скрипта.

3. Опционально — настроить FRP и Hawser:

   ```bash
   sudo bash /opt/homelab/<vm>/frp-setup.sh    # настроить туннель
   sudo bash /opt/homelab/<vm>/run-hawser.sh   # подключить к Dockhand
   ```

**Проверка:**

```bash
docker compose -f /opt/homelab/<vm>/docker-compose.yml ps
# Все сервисы: Up/healthy
ls /opt/homelab/<vm>/.deployed   # маркер деплоя должен существовать
```

**Особенность:** При повторном запуске `first-deployment.sh` показывает предупреждение и требует подтверждения. Для обновления конфигов используйте `sync.sh`.

**Откат:** `docker compose down`, удалить `.deployed` маркер, повторить при необходимости.

---

## Добавление агента Dockhand (Hawser) на VM

**Когда применять:** Подключение vm-db-01 или другой VM к Dockhand для удалённого управления.

**Предусловия:** Dockhand запущен на vm-DevOps-01, Docker установлен на целевой VM.

**Шаги:**

1. SSH на целевую VM:

   ```bash
   ssh user-home@192.168.1.36
   ```

2. Запустить скрипт:

   ```bash
   sudo bash /opt/homelab/vm-db-01/run-hawser.sh
   # Выбрать режим:
   #   1) Standard — если VM в той же LAN, что и Dockhand
   #   2) Edge     — если VM за NAT или нет прямого доступа от Dockhand
   # Ввести токен (придумать любой) и имя агента
   ```

3. В Dockhand UI (`http://192.168.1.XX:3000`): **Agents → Add Agent**
   - Режим Standard: Host = IP VM, Port = 2376, Token = (указанный токен)
   - Режим Edge: агент подключается сам, появится в списке автоматически

**Проверка:**

```bash
docker ps | grep hawser
docker logs -f hawser
# В Dockhand UI: агент отображается в Agents со статусом Connected
```

**Откат:** `docker stop hawser && docker rm hawser`

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
