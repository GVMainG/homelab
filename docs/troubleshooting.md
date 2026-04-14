# Диагностика и решение проблем

## Для чего этот документ и как вести?

Этот документ — база знаний по типовым проблемам homelab и способам их диагностики. Он помогает быстро найти корень проблемы, не начиная расследование с нуля каждый раз. Здесь фиксируются как симптомы, так и проверенные решения.

**Что должно быть в этом документе:**

Для каждой типовой проблемы:

- **Симптом** — как проявляется проблема (сообщения об ошибках, поведение)
- **Где проявляется** — на какой VM или сервисе
- **Возможные причины** — список того, что может быть источником
- **Диагностика** — команды и проверки для локализации проблемы
- **Решение** — пошаговое исправление
- **Профилактика** — как избежать повторения

Типовые проблемы для документирования:

- Сервис не стартует (`docker compose up` падает)
- Healthcheck постоянно failing
- PostgreSQL не принимает подключения
- Vaultwarden не может подключиться к БД
- Nginx Proxy Manager не проксирует запросы
- SSL-сертификат не подхватывается
- dnsmasq не резолвит домены
- Проблемы с сетью между VM
- Место на диске заполнено (Docker volumes, логи)
- Git sparse checkout не обновляется
- Proxmox VM не запускается

**Правила документирования:**

- Каждая проблема — отдельный подраздел (`##`) с кратким описанием симптома
- Писать так, чтобы человек без глубокого контекста мог понять и решить проблему
- Приводить реальные сообщения об ошибках (логи, вывод команд)
- Указывать команды диагностики с примерами вывода (как выглядит «норма» и «не норма»)
- Если решение не найдено — всё равно зафиксировать проблему с пометкой `NO SOLUTION YET`
- После решения — указывать, в какой версии/конфигурации проблема воспроизводилась
- Обновлять при каждом новом инциденте — даже если решение было найдено «на лету»
- Ссылаться на этот документ из `runbooks.md`, если по проблеме есть готовый runbook

---

## Сервис не стартует (docker compose up падает)

**Симптом:** `docker compose up -d` завершается с ошибкой, контейнер в статусе `Exit` или `Created`.

**Диагностика:**

1. Посмотреть статус сервисов:
   ```bash
   docker compose ps -a
   ```

2. Посмотреть логи проблемного сервиса:
   ```bash
   docker compose logs <service>
   ```

3. Проверить зависимости:
   ```bash
   docker compose ps postgres   # зависит ли сервис от PostgreSQL?
   ```

**Частые причины:**

| Причина | Решение |
|---|---|
| `.env` файл отсутствует | `cp .env.example .env` и заполнить |
| Переменная в `.env` пустая | Проверить все `CHANGE_ME` значения |
| Порт уже занят другой программой | `sudo lsof -i :PORT` найти конфликт, остановить или сменить порт |
| Volume не создан | `docker compose up -d` создаёт автоматически, проверить `docker volume ls` |
| Healthcheck зависшего контейнера fails | `docker compose restart <dependency>` |

---

## PostgreSQL не принимает подключения

**Симптом:** Vaultwarden или pgAdmin не могут подключиться к БД, ошибка `connection refused` или `authentication failed`.

**Где проявляется:** vm-db-01

**Диагностика:**

1. Проверить что PostgreSQL запущен:
   ```bash
   docker compose ps postgres
   docker compose logs postgres | tail -20
   ```

2. Проверить healthcheck:
   ```bash
   docker exec postgres pg_isready -U admin -d postgres
   ```

3. Проверить логи на предмет init-scripts:
   ```bash
   docker compose logs postgres | grep -i "init\|sql\|vw_user\|vaultwarden"
   ```

**Частые причины:**

| Причина | Решение |
|---|---|
| Init-скрипты не выполнились (первый старт с ошибками) | Удалить volume: `docker volume rm vm-db-01_postgres-data`, перезапустить |
| Неправильный `DATABASE_URL` в Vaultwarden | Проверить `.env`: `DATABASE_URL=postgresql://vw_user:PASSWORD@postgres:5432/vaultwarden` |
| Пользователь `vw_user` не создан | Подключиться через pgAdmin или `docker exec -it postgres psql -U admin` и создать вручную |

**Ручное создание пользователя и БД:**
```bash
docker exec -it postgres psql -U admin
CREATE USER vw_user WITH PASSWORD 'CHANGE_ME';
CREATE DATABASE vaultwarden OWNER vw_user;
GRANT ALL PRIVILEGES ON DATABASE vaultwarden TO vw_user;
\q
```

---

## Vaultwarden не может подключиться к БД

**Симптом:** Vaultwarden логи содержит `Error connecting to database`, `Connection refused`.

**Где проявляется:** vm-db-01

**Диагностика:**

1. Проверить что PostgreSQL healthy:
   ```bash
   docker compose ps postgres
   ```

2. Проверить DATABASE_URL:
   ```bash
   docker exec vaultwarden env | grep DATABASE_URL
   ```

3. Попробовать подключиться из контейнера Vaultwarden:
   ```bash
   docker exec -it vaultwarden sh
   # Внутри контейнера:
   wget -O- http://postgres:80  # должен отказать (это не HTTP)
   # Проверить DNS:
   ping postgres
   ```

**Решение:**

- Убедиться, что оба сервиса в одной сети `db-net`
- Проверить `.env` на vm-db-01: правильные `VW_DB_USER`, `VW_DB_PASSWORD`, `VW_DB_NAME`
- Если пароль неверный — исправить в `.env`, `docker compose up -d`

---

## Git sparse checkout не обновляется

**Симптом:** `bash sync.sh` не подтягивает новые файлы или ошибка checkout.

**Диагностика:**

1. Проверить статус sparse checkout:
   ```bash
   git sparse-checkout list
   ```

2. Проверить статус репозитория:
   ```bash
   git status
   git fetch origin
   ```

**Решение:**

```bash
# Сбросить sparse checkout и пересоздать
git sparse-checkout disable
git sparse-checkout set vm-db-01
git pull origin main
```

**Если конфликт локальных изменений:**
```bash
git checkout -- .   # отменить локальные изменения (НЕ .env!)
git pull origin main
```

---

## Permission denied при git pull на VM (репо склонирован от root)

**Симптом:** `bash sync.sh` или `git pull` на VM падает с `cannot open '.git/FETCH_HEAD': Permission denied`.

**Где проявляется:** vm-db-01

**Причина:** Репозиторий был первоначально склонирован под `root` (`sudo git clone ...`). Текущий пользователь (`user-home`) не имеет прав на запись.

**Диагностика:**
```bash
ls -la /opt/homelab/.git/FETCH_HEAD
# Если owner root, root — это причина
```

**Решение:**
```bash
sudo git pull   # один раз вручную от root
sudo chown -R user-home:user-home /opt/homelab
# Теперь git pull работает без sudo
```

---

## NPM возвращает 503 для proxy host туннельного сервиса

**Симптом:** Браузер показывает `HTTP ERROR 503` при обращении к домену через NPM. Прямой доступ по IP:PORT работает.

**Где проявляется:** vps-ru-proxy (NPM → frps → frpc-туннель)

**Диагностика:**

1. Проверить, что все контейнеры запущены:

   ```bash
   cd /opt/vps-ru-proxy && docker compose ps
   ```

2. Проверить container-to-container связность (заменить `<npm>` на реальное имя контейнера):

   ```bash
   docker compose ps   # узнать имена контейнеров
   docker exec <npm-container> curl -v http://frps:7500
   ```

3. Проверить настройки Proxy Host в NPM UI (`http://VPS_IP:81`):
   - Scheme должен быть `http` (не `https`)
   - Forward Hostname: `frps` (имя контейнера в proxy-net)
   - Force SSL: выключить до получения сертификата

**Частые причины:**

| Причина | Решение |
| --- | --- |
| Scheme = `https` вместо `http` | NPM делает TLS к frps, frps не ожидает TLS → сменить на `http` |
| Force SSL включён без сертификата | NPM закрывает соединение → выключить Force SSL |
| frps не запущен | `docker compose logs frps` → перезапустить |
| NPM не может резолвить `frps` | Оба сервиса должны быть в `proxy-net` — проверить `docker inspect` |

---

## Docker Hub rate limit при docker compose up

**Симптом:** `docker compose up` падает с ошибкой `toomanyrequests: You have reached your pull rate limit`.

**Где проявляется:** VPS при первом развёртывании или обновлении образов.

**Решение:**

```bash
docker login
# Ввести логин/пароль Docker Hub
docker compose up -d
```

Бесплатный аккаунт Docker Hub снимает лимит анонимных pull (100 запросов/6 часов по IP).
`setup.sh` автоматически предлагает `docker login` перед запуском стека.

---

## curl в PowerShell не работает с флагами (-v, -H)

**Симптом:** `curl -v -H "Host: ..."` в PowerShell вызывает ошибку или неожиданное поведение.

**Причина:** В PowerShell `curl` — псевдоним (`alias`) для `Invoke-WebRequest`, у которого другой синтаксис.

**Решение:** Использовать `curl.exe` явно:

```powershell
curl.exe -v -H "Host: frp-ui.gv-services.net.ru" http://VPS_IP
```

Или выполнить команду через SSH на VPS:

```powershell
ssh root@VPS_IP "curl -v -H 'Host: frp-ui.gv-services.net.ru' http://127.0.0.1"
```

---

## Место на диске заполнено (Docker volumes, логи)

**Симптом:** `No space left on device`, Docker не запускается.

**Диагностика:**

1. Проверить место:
   ```bash
   df -h
   du -sh /var/lib/docker/volumes/* | sort -h | tail -10
   docker system df
   ```

2. Проверить логи Docker:
   ```bash
   sudo journalctl --disk-usage
   ```

**Решение:**

```bash
# Удалить unused images
docker image prune -a

# Удалить unused volumes (ОСТОРОЖНО — данные будут потеряны!)
docker volume prune

# Очистить Docker logs
sudo journalctl --vacuum-size=100M

# Очистить старые бэкапы PostgreSQL (оставить последние 7 дней)
find /opt/homelab/backups/ -name "*.sql" -mtime +7 -delete
```
