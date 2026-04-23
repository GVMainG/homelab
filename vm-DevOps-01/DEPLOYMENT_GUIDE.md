# Deployment Guide — Homepage через Dockhand

Как эффективно деплоить и управлять конфигами Homepage используя Dockhand.

## 🚀 Способ 1: Stack Manager в Dockhand (Рекомендуется)

**Преимущества:**
- ✅ Управление конфигами в UI
- ✅ История изменений
- ✅ Горячая перезагрузка
- ✅ Удобный git-интеграция (опционально)

**Шаги:**

1. **Открыть Dockhand** → **Stacks**

2. **Create Stack** → выбрать **From Docker Compose**

3. **Paste** содержимое `docker-compose.yml`:
   ```yaml
   services:
     homepage:
       image: ghcr.io/gethomepage/homepage:latest
       container_name: homepage
       restart: unless-stopped
       ports:
         - "3001:3000"
       volumes:
         - homepage-config:/app/config
         - /var/run/docker.sock:/var/run/docker.sock:ro
       environment:
         PUID: 1000
         PGID: 1000
   
   volumes:
     homepage-config:
   ```

4. **Добавить конфиги как файлы стека:**
   - Нажать **+ Add File**
   - Тип: `Config`
   - Имя: `services.yml`
   - Содержимое: скопировать из `config/services.yml`
   - Повторить для `settings.yml` и `bookmarks.yml`

5. **Deploy** → Dockhand создаст stack и инициализирует конфиги

6. **При изменении конфигов:**
   - Отредактировать файл в Dockhand UI
   - **Save**
   - Dockhand автоматически обновит контейнер

---

## 🔧 Способ 2: Терминал контейнера (Быстрый редакт)

**Когда использовать:** быстрые изменения, срочные правки

**Шаги:**

1. **Dockhand** → **Containers** → найти `homepage`

2. **Клик на контейнер** → вкладка **Terminal**

3. **Отредактировать конфиг:**
   ```bash
   apk add nano  # установить редактор (если нужно)
   nano /app/config/services.yml
   ```
   или
   ```bash
   vi /app/config/services.yml
   ```

4. **Сохранить** (`:wq` в vi, Ctrl+O → Enter в nano)

5. **Выход** из терминала

6. **Homepage перезагружается автоматически** (за 5-10 секунд)

---

## 📂 Способ 3: Через том на хосте (Для batch-изменений)

**Когда использовать:** большие изменения, синхронизация с git

**Шаги:**

1. **Найти том контейнера:**
   ```bash
   docker volume inspect vm-devops-01_homepage-config
   ```
   
   Скопировать значение `Mountpoint` (e.g., `/var/lib/docker/volumes/vm-devops-01_homepage-config/_data`)

2. **SSH на vm-DevOps-01**, перейти в том:
   ```bash
   cd /var/lib/docker/volumes/vm-devops-01_homepage-config/_data
   ls -la
   ```

3. **Отредактировать конфиги:**
   ```bash
   nano services.yml
   nano settings.yml
   ```

4. **Перезагрузить контейнер:**
   ```bash
   docker compose restart homepage
   ```

---

## 🔄 Способ 4: Git + Dockhand (CI/CD интеграция)

**Когда использовать:** версионирование конфигов, автоматические обновления

**Шаги:**

1. **В Dockhand** → **Stacks** → **Import from Git**

2. **Указать Git URL:**
   ```
   https://github.com/GVMainG/homelab.git
   ```

3. **Branch:** `main`

4. **Stack path:** `vm-DevOps-01`

5. **Dockhand будет:**
   - Клонировать репо в `/dockhand-data/git-repos`
   - Использовать `docker-compose.yml` из этой директории
   - Использовать конфиги из `config/` директории

6. **При push в git:**
   ```bash
   git add vm-DevOps-01/config/
   git commit -m "chore: update homepage config"
   git push origin main
   ```
   
   Нажать в Dockhand **Pull & Redeploy** → контейнер обновится автоматически

---

## 📋 Сравнение способов

| Способ | Скорость | Удобство | Версионирование | Рекомендуется для |
|--------|----------|----------|-----------------|------------------|
| **Stack Manager** | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | Git + UI | Основной деплой |
| **Терминал** | ⭐⭐⭐⭐ | ⭐⭐⭐ | Нет | Срочные правки |
| **Том на хосте** | ⭐⭐ | ⭐⭐ | Git | Batch-изменения |
| **Git + Dockhand** | ⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | GitOps workflow |

---

## 🔍 Проверка изменений

После любого способа обновления проверить:

```bash
# На хосте (vm-DevOps-01)
docker compose logs -f homepage

# В браузере
# Перезагрузить страницу: Ctrl+Shift+R (жесткая перезагрузка)
# https://homepage.gv-services.net.ru
```

---

## ⚠️ Частые ошибки

### Homepage не применяет изменения
- Жесткая перезагрузка браузера: **Ctrl+Shift+R**
- Проверить логи: `docker compose logs -f homepage`
- Перезагрузить контейнер: `docker compose restart homepage`

### Конфиг не валиден (YAML синтаксис)
- Проверить отступы (2 пробела, не табы)
- Использовать YAML валидатор: https://www.yamllint.com/

### Иконка не отображается
- Проверить иконку в MDI: https://materialdesignicons.com/
- Правильный формат: `mdi-icon-name` (без префикса)

---

## 📚 Полезные ссылки

- [Homepage документация](https://gethomepage.github.io/en/installation/configuration/)
- [MDI иконки](https://materialdesignicons.com/)
- [YAML синтаксис](https://yaml.org/)
- [Dockhand документация](https://github.com/fnsys/dockhand)

---

## 💾 Backup & Restore

**Backup конфигов:**
```bash
docker cp homepage:/app/config ./homepage-config-backup
```

**Restore конфигов:**
```bash
docker cp ./homepage-config-backup/. homepage:/app/config/
docker compose restart homepage
```
