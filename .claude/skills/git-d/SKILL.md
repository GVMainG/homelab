# git-d

## Описание

Скилл для анализа изменений, подготовки описания коммита (commit message) и вывода результата в чат. **Не выполняет коммит автоматически** — только показывает черновик для подтверждения.

## Вызов

Команда: `/git-d`

## Порядок работы

### Шаг 1 — Сбор информации об изменениях

```bash
# Какие файлы изменены (staged и unstaged)
git status --short

# Diff staged изменений
git diff --staged

# Diff unstaged изменений (если staged пусто)
git diff HEAD

# Последние 3 коммита для определения стиля сообщений
git log -n 3 --oneline

# Детали последнего коммита (формат, sign-off и т.д.)
git log -n 1 --format="%B"
```

### Шаг 2 — Анализ изменений

На основе diff определить:

- **Тип изменений:** `feat` / `fix` / `docs` / `refactor` / `chore` / `style` / `test` / `ci`
- **Затронутые VM:** `vm-db-02`, `vm-proxy-02`, или обе
- **Затронутые сервисы:** postgres, vaultwarden, pgadmin, npm
- **Scope:** что именно изменилось (конфиг, скрипт, документация)

### Шаг 3 — Формирование commit message

Формат (Conventional Commits):

```
<type>(<scope>): <description>

<body>

<footer>
```

**Правила:**

- **type:** `feat`, `fix`, `docs`, `refactor`, `chore`, `test`, `ci`
- **scope:** имя VM или сервиса (`vm-db-02`, `vm-proxy-02`, `postgres`, `npm`)
- **description:** краткое описание, начинающееся с глагола, без точки в конце, не более 72 символов
- **body:** подробности, список конкретных изменений (по одному на строку), только если изменений много
- **footer:** `BREAKING CHANGE:` если есть обратная несовместимость; ссылки на issue если есть
- Стиль должен соответствовать последним 3 коммитам в репозитории

Если в проекте уже принят другой стиль (видно из `git log`) — следовать ему.

### Шаг 4 — Вывод в чат

Показать пользователю результат в формате:

```
📝 Proposed commit message:

---
<type>(<scope>): <description>

<body>
---

Staged files: <N> | Unstaged files: <N>
Changed: <краткий перечень файлов>
```

И спросить: «Подтвердить коммит с этим сообщением?»

### Шаг 5 — По подтверждению

Если пользователь подтвердил — выполнить:

```bash
git add -A && git commit -m "<message>"
```

И показать результат:

```
✅ Committed: <short-hash> <description>
```

Если пользователь попросил изменить — отредактировать сообщение и повторить шаг 4.

## Пример

**Пользователь:** `/git-d`

**Агент собирает:**
```
git status → M vm-db-02/docker-compose.yml
git diff → добавлен healthcheck для vaultwarden
git log → стиль: "feat(vm-db-02): add pgAdmin service"
```

**Выводит:**
```
📝 Proposed commit message:

---
feat(vm-db-02): add healthcheck for vaultwarden service

- Add curl-based healthcheck to docker-compose.yml
- Interval: 10s, timeout: 5s, retries: 5
---

Staged files: 0 | Unstaged files: 1
Changed: vm-db-02/docker-compose.yml

Подтвердить коммит?
```

## Нюансы

- Если изменений нет — сообщить: «Нет изменений для коммита»
- Если изменения слишком крупные — разбить на несколько логических коммитов и предложить пользователю
- Если есть `.env` или секреты в staged — предупредить и НЕ коммитить
- Всегда проверять `.gitignore` на предмет закоммиченных секретов
