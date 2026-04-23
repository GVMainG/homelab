# Quickstart — Homepage & Dockhand

## 🚀 Первый запуск

```bash
cd vm-DevOps-01
cp .env.example .env
docker compose up -d
```

## 🌐 Доступ

- **Dockhand:** http://192.168.1.XX:3000
- **Homepage:** http://192.168.1.XX:3001

Через Reverse Proxy:
- **Dockhand:** https://dockhand.gv-services.net.ru
- **Homepage:** https://homepage.gv-services.net.ru

## ✏️ Редактирование конфигов Homepage

### Вариант 1: Через Dockhand UI Terminal (самый быстрый)
```bash
# В Dockhand:
# 1. Containers → homepage → Terminal
# 2. Скопировать команду ниже:
vi /app/config/services.yml
# 3. Сохранить: :wq (Enter)
```

### Вариант 2: На хосте
```bash
# На vm-DevOps-01:
docker volume inspect vm-devops-01_homepage-config
# Скопировать Mountpoint путь
cd /var/lib/docker/volumes/vm-devops-01_homepage-config/_data
nano services.yml
# Сохранить: Ctrl+O, Enter, Ctrl+X

# Перезагрузить:
docker compose restart homepage
```

## 📝 Конфиги

| Файл | Назначение |
|------|-----------|
| `config/services.yml` | Сервисы на дашборде |
| `config/settings.yml` | Тема, язык, раскладка |
| `config/bookmarks.yml` | Быстрые ссылки |

## 🔍 Проверка статуса

```bash
docker compose ps              # все сервисы
docker compose logs -f homepage # логи Homepage
docker compose logs -f dockhand # логи Dockhand
```

## 🔄 Перезагрузка

```bash
docker compose restart homepage    # только Homepage
docker compose restart             # все сервисы
docker compose down && up -d       # полный перезапуск
```

## 📚 Полезное

- **Иконки:** https://materialdesignicons.com/
- **Документация Homepage:** https://gethomepage.github.io/
- **YAML валидатор:** https://www.yamllint.com/

## 🛠️ Troubleshooting

```bash
# Homepage не обновляется?
docker compose restart homepage
# Браузер: Ctrl+Shift+R

# Ошибка в конфиге?
docker compose logs -f homepage

# Проверить конфиг на валидность?
docker exec homepage cat /app/config/services.yml
```

## 🆚 Dockhand vs Manual

| Задача | Dockhand | Manual |
|--------|----------|--------|
| Просмотр логов | ✅ UI | Терминал |
| Управление контейнерами | ✅ UI | docker ps/rm |
| Редактирование конфигов | ✅ Stack Manager | vi/nano |
| Управление стеками | ✅ UI | docker compose |

**Рекомендация:** Используй Dockhand для всего. Он проще и удобнее. 🎯
