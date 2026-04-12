# vm-db-01

PostgreSQL 16 + Vaultwarden 1.32 + pgAdmin 8 на одной VM.

## Быстрый старт

```bash
# 1. Клонировать репо (sparse checkout)
git clone --filter=blob:none --sparse git@github.com:GVMainG/homelab.git
cd homelab && git sparse-checkout set vm-db-01

# 2. Развернуть
cd vm-db-01
chmod +x deploy.sh backup.sh
./deploy.sh
# → отредактировать .env (пароли), запустить повторно

# 3. Обновить
docker compose pull && docker compose up -d
```

## Порты

| Сервис        | Хост                 | Доступ        |
|---------------|----------------------|---------------|
| PostgreSQL    | `127.0.0.1:5432`     | Только localhost |
| Vaultwarden   | `0.0.0.0:8081`       | LAN (требуется firewall) |
| pgAdmin       | `0.0.0.0:5050`       | LAN (требуется firewall) |

## Файрвол (ufw)

```bash
ufw allow from 192.168.1.0/24 to any port 8081  # Vaultwarden
ufw allow from 192.168.1.0/24 to any port 5050  # pgAdmin
# PostgreSQL НЕ открываем — только 127.0.0.1
```

## Бэкап / Восстановление

```bash
# Создать бэкап (с ротацией)
./backup.sh

# Ручной бэкап одной таблицы
docker exec db-postgres pg_dump -U homelab_admin -d homelab -t users | gzip > manual.sql.gz

# Восстановить из бэкапа
gunzip -c backups/pg_backup_2026-04-12_030000.sql.gz | \
  docker exec -i db-postgres psql -U homelab_admin -d homelab
```

## Trade-offs

| Решение                      | Почему так                                    | Риск / Ограничение                              |
|------------------------------|-----------------------------------------------|------------------------------------------------|
| **Compose, не Swarm/K8s**    | Одна VM, нет нужды в оркестрации              | Нет HA — при падении VM все сервисы недоступны |
| **Named volumes** для БД     | Docker управляет правами, проще миграции      | Данные внутри `/var/lib/docker/volumes` — бэкапьте |
| **Bind mount** для бэкапов   | Прямой доступ с хоста, легко rsync на оффсайт | Нужно следить за местом на диске              |
| **Vaultwarden → SQLite**     | Проще, нет доп. зависимостей                   | Один инстанс; для кластера нужен PG backend   |
| **Port 0.0.0.0**             | Доступ с любой машины LAN                     | Без firewall — открытый порт всем              |
| **pgAdmin без master pass**  | Меньше friction при входе                      | Учётка pgAdmin — единственный барьер          |
| **ADMIN_PAGE = false**       | Меньше attack surface                         | Управление пользователями только через API    |

## Чек-лист валидации после `./deploy.sh`

- [ ] `docker compose ps` — все сервисы `Up (healthy)`
- [ ] `curl -f http://192.168.1.51:8081/alive` → `true`
- [ ] `curl -f http://192.168.1.51:5050` → 200/302 (pgAdmin login)
- [ ] `pg_isready -h 127.0.0.1 -p 5432 -U homelab_admin` → accepting
- [ ] `./backup.sh` → файл в `backups/`, размер > 0
- [ ] Firewall: `ufw status` — порты 8081, 5050 ограничены подсетью
- [ ] `.env` не закоммичен: `git ls-files .env` → пусто
