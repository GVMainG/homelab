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

**Где проявляется:** vm-db-02

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
| Init-скрипты не выполнились (первый старт с ошибками) | Удалить volume: `docker volume rm vm-db-02_postgres-data`, перезапустить |
| Неправильный `DATABASE_URL` в Vaultwarden | Проверить `.env`: `DATABASE_URL=postgresql://vw_user:PASSWORD@postgres:5432/vaultwarden` |
| Пользователь `vw_user` не создан | Подключиться через pgAdmin или `docker exec -it postgres psql -U admin` и создать вручную |
| PostgreSQL слушает только localhost | Проверить `docker-compose.yml`: `ports: "5432:5432"` должен быть без `127.0.0.1:` |

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

**Где проявляется:** vm-db-02

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
- Проверить `.env` на vm-db-02: правильные `VW_DB_USER`, `VW_DB_PASSWORD`, `VW_DB_NAME`
- Если пароль неверный — исправить в `.env`, `docker compose up -d`

---

## Nginx Proxy Manager не проксирует запросы

**Симптом:** `https://vw.home.loc` возвращает 502 Bad Gateway или timeout.

**Где проявляется:** vm-proxy-02

**Диагностика:**

1. Проверить NPM health:
   ```bash
   docker compose ps npm
   docker compose logs npm | tail -30
   ```

2. Проверить что upstream (целевой сервис) доступен с proxy VM:
   ```bash
   curl http://192.168.1.36:8080/   # Vaultwarden
   curl http://192.168.1.36:5050/   # pgAdmin
   ```

3. Проверить SSL-сертификат:
   ```bash
   openssl s_client -connect vw.home.loc:443 -servername vw.home.loc </dev/null 2>/dev/null | openssl x509 -noout -dates
   ```

**Частые причины:**

| Причина | Решение |
|---|---|
| Upstream сервис (Vaultwarden) не доступен | Запустить сервис на vm-db-02, проверить фаервол |
| Неправильный IP в Proxy Host настройках | NPM UI: проверить что Forward Hostname/IP = `192.168.1.36`, правильный порт |
| SSL-сертификат истёк | Перегенерировать через NPM UI или `ssl/generate-ssl.sh` |
| Блок-лист IP / Access List | Проверить NPM UI: Proxy Host → Access List |

---

## dnsmasq не резолвит локальные домены

**Симптом:** `dig vw.home.loc @192.168.1.37` не возвращает ответ или `NXDOMAIN`.

**Где проявляется:** vm-proxy-02

**Диагностика:**

1. Проверить что dnsmasq запущен:
   ```bash
   sudo systemctl status dnsmasq
   ```

2. Проверить конфиг:
   ```bash
   sudo cat /etc/dnsmasq.d/*.conf
   # Должна быть запись вида: address=/home.loc/192.168.1.37
   ```

3. Проверить что systemd-resolved остановлен:
   ```bash
   sudo systemctl status systemd-resolved   # должен быть inactive/disabled
   ```

4. Проверить что порт 53 свободен:
   ```bash
   sudo lsof -i :53
   ```

**Решение:**

- Если dnsmasq не запущен: `sudo systemctl start dnsmasq`
- Если конфиг пуст — добавить запись и `sudo systemctl restart dnsmasq`
- Если systemd-resolved перехватывает порт 53:
  ```bash
  sudo systemctl stop systemd-resolved
  sudo systemctl disable systemd-resolved
  sudo systemctl restart dnsmasq
  ```

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
git sparse-checkout set vm-db-02   # или vm-proxy-02
git pull origin main
```

**Если конфликт локальных изменений:**
```bash
git checkout -- .   # отменить локальные изменения (НЕ .env!)
git pull origin main
```

---

## NPM показывает просроченный сертификат, но nginx работает корректно

**Симптом:** NPM UI (SSL Certificates) показывает сертификат с просроченной датой. При этом реальный TLS на 443 работает — `openssl s_client` показывает новые даты.

**Где проявляется:** vm-proxy-02

**Причина:** NPM хранит метаданные сертификата (в т.ч. `expires_on`) в SQLite-базе `/data/database.sqlite` (том `vm-proxy-02_npm-data`). Если сертификатные файлы заменить напрямую в volume (минуя NPM API), база данных не обновляется.

**Диагностика:**

1. Проверить реальные даты сертификата, который отдаёт nginx:
   ```bash
   echo | openssl s_client -connect localhost:443 -servername vw.home.loc 2>&1 | openssl x509 -noout -dates
   ```

2. Проверить что в БД NPM:
   ```bash
   docker run --rm -v vm-proxy-02_npm-data:/data python:3-alpine python3 -c "
   import sqlite3
   conn = sqlite3.connect('/data/database.sqlite')
   cur = conn.cursor()
   cur.execute('SELECT id, nice_name, expires_on FROM certificate')
   print(cur.fetchall())
   conn.close()
   "
   ```

**Решение:** Обновить `expires_on` в SQLite напрямую:

```bash
cat > /tmp/fix_cert.py << 'PYEOF'
import sqlite3
conn = sqlite3.connect("/data/database.sqlite")
cur = conn.cursor()
# Подставить реальную дату из openssl (формат: YYYY-MM-DD HH:MM:SS)
cur.execute("UPDATE certificate SET expires_on = '2036-04-11 09:35:36' WHERE id = 1")
conn.commit()
print("Updated:", cur.execute("SELECT id, nice_name, expires_on FROM certificate").fetchall())
conn.close()
PYEOF

docker run --rm \
  -v vm-proxy-02_npm-data:/data \
  -v /tmp/fix_cert.py:/tmp/fix_cert.py \
  python:3-alpine python3 /tmp/fix_cert.py

cd /opt/homelab/vm-proxy-02
docker compose restart npm
```

**Профилактика:** При замене сертификата использовать NPM API (`PUT /api/nginx/certificates/{id}`) или UI — тогда БД обновляется автоматически. При ручной замене файлов — всегда обновлять БД.

---

## DNS *.home.loc не резолвится на Windows PC с v2rayN/sing-box

**Симптом:** `https://vw.home.loc` не открывается. `nslookup vw.home.loc` возвращает `NXDOMAIN` или отвечает не тот DNS.

**Где проявляется:** Windows-клиент с v2rayN (xray core + sing-box TUN mode)

**Причина:** sing-box в TUN-режиме создаёт виртуальный адаптер (`singbox_tun`) и перехватывает **весь** DNS-трафик через `action: hijack-dns`. Запросы для `*.home.loc` не имеют правила с локальным DNS-сервером → уходят на внешний DNS (8.8.8.8) → `NXDOMAIN`. Смена DNS-сервера в настройках сетевого адаптера не помогает — sing-box перехватывает раньше.

**Диагностика:**

1. Проверить какой DNS реально используется:
   ```powershell
   nslookup vw.home.loc
   # Если "Server: dns.google" или 8.8.8.8 — sing-box перехватывает
   ```

2. Проверить есть ли адаптер sing-box:
   ```powershell
   Get-NetAdapter | Where-Object {$_.InterfaceDescription -like "*sing*" -or $_.Name -like "*tun*"}
   ```

**Решение (постоянное):** Прописать записи в `C:\Windows\System32\drivers\etc\hosts` — hosts-файл Windows проверяется ДО DNS и НЕ перехватывается sing-box:

```hosts
192.168.1.37 vw.home.loc
192.168.1.37 pgadmin.home.loc
192.168.1.37 home.home.loc
```

Редактировать через PowerShell (требует прав администратора):

```powershell
# Запустить PowerShell как администратор:
Add-Content -Path "C:\Windows\System32\drivers\etc\hosts" -Value "`n192.168.1.37 vw.home.loc`n192.168.1.37 pgadmin.home.loc`n192.168.1.37 home.home.loc"
```

**Установить CA-сертификат в Windows Trusted Root:**

```powershell
# Запустить PowerShell как администратор:
Import-Certificate -FilePath "C:\path\to\homelab-ca.crt" -CertStoreLocation Cert:\LocalMachine\Root
```

CA-сертификат: `vm-proxy-02/ssl/certs/ca.crt` (генерируется `generate-ssl.sh`, не хранится в git — взять с VM из `/opt/homelab/vm-proxy-02/ssl/certs/ca.crt`).

**Профилактика:** При добавлении нового сервиса `newservice.home.loc` — добавить строку в hosts-файл на каждом Windows-клиенте.

---

## Permission denied при git pull на VM (репо склонирован от root)

**Симптом:** `bash sync.sh` или `git pull` на VM падает с `cannot open '.git/FETCH_HEAD': Permission denied`.

**Где проявляется:** vm-db-02 или vm-proxy-02

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
