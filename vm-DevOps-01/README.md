# vm-DevOps-01 — Docker Management & Dashboard

Сервисы управления Docker и дашборда для инфраструктуры.

## Сервисы

### Dockhand
Веб-интерфейс управления Docker контейнерами и Compose-стеками.
- **Порт:** 3000
- **URL:** `http://192.168.1.XX:3000` или `https://dockhand.gv-services.net.ru`
- **Функции:** запуск/остановка контейнеров, просмотр логов, терминал, управление стеками

### Homepage
Стартовая страница дашборда со ссылками на все сервисы.
- **Порт:** 3001
- **URL:** `http://192.168.1.XX:3001` или `https://homepage.gv-services.net.ru`
- **Конфиги:** `config/services.yml`, `config/settings.yml`, `config/bookmarks.yml`

## Первый запуск

```bash
# Скопировать шаблон переменных
cp .env.example .env

# Сгенерировать ENCRYPTION_KEY для Dockhand (если нужно)
openssl rand -hex 32

# Запустить сервисы
docker compose up -d

# Проверить статус
docker compose ps
```

## Управление конфигами Homepage через Dockhand

### Способ 1: Через терминал Dockhand (Рекомендуется)

1. Открыть **Dockhand** → **Containers** → **homepage**
2. Нажать на контейнер → **Terminal**
3. Отредактировать конфиги:
   ```bash
   vi /app/config/services.yml
   vi /app/config/settings.yml
   vi /app/config/bookmarks.yml
   ```
4. Сохранить (`:wq`)
5. Homepage перезагрузится автоматически

### Способ 2: Через том контейнера (через хост)

1. Найти том на хосте:
   ```bash
   docker volume inspect vm-devops-01_homepage-config
   ```
2. Конфиги находятся в директории `Mountpoint`
3. Отредактировать файлы через хост
4. Перезагрузить контейнер:
   ```bash
   docker compose restart homepage
   ```

### Способ 3: Через Dockhand Stack Manager (Best Practice)

1. В **Dockhand** → **Stacks** создать стек
2. Скопировать `docker-compose.yml` из этой директории
3. В том же Dockhand UI:
   - Добавить файл конфига `config/services.yml`
   - Добавить файл конфига `config/settings.yml`
   - Добавить файл конфига `config/bookmarks.yml`
4. Dockhand будет управлять деплоем и обновлениями конфигов

## Структура конфигов Homepage

### services.yml
Определяет сервисы, отображаемые на дашборде:
```yaml
GroupName:
  - ServiceName:
      icon: mdi-icon-name
      description: Описание
      href: https://service.url
      server: container-name
      container: container-name
```

### settings.yml
Глобальные настройки дашборда:
- Тема (light/dark)
- Цветовая схема
- Язык
- Раскладка карточек

### bookmarks.yml
Быстрые ссылки и закладки (опционально).

## Обновление конфигов

При изменении конфигов Homepage:
```bash
docker compose restart homepage
```

Изменения применяются автоматически (горячая перезагрузка).

## Доступ через Reverse Proxy

Для доступа через доменные имена добавить в **NPM (nginx-proxy-manager)**:

- **Dockhand:** `npm.gv-services.net.ru` → `http://localhost:3000`
- **Homepage:** `homepage.gv-services.net.ru` → `http://localhost:3001`

## Проверка статуса

```bash
# Все сервисы
docker compose ps

# Логи Homepage
docker compose logs -f homepage

# Логи Dockhand
docker compose logs -f dockhand
```

## Переменные окружения

Скопировать `.env.example` в `.env` и заполнить:
- `ENCRYPTION_KEY` — ключ шифрования для Dockhand
- `PUID` / `PGID` — UID/GID для доступа к томам

## Резервная копия конфигов

```bash
# Резервная копия томов
docker run --rm -v vm-devops-01_homepage-config:/src -v $(pwd):/backup \
  alpine tar czf /backup/homepage-config.tar.gz -C /src .

# Восстановление
docker run --rm -v vm-devops-01_homepage-config:/dest -v $(pwd):/backup \
  alpine tar xzf /backup/homepage-config.tar.gz -C /dest .
```
