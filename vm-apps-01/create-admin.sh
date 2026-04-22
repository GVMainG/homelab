#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Проверка .env
if [[ ! -f .env ]]; then
  echo "Ошибка: файл .env не найден в $SCRIPT_DIR"
  exit 1
fi

# Проверка зависимостей
if ! command -v python3 &> /dev/null; then
  echo "Ошибка: python3 не найден"
  exit 1
fi

if ! python3 -c "import bcrypt" 2>/dev/null; then
  echo "Ошибка: Python модуль bcrypt не установлен"
  echo "Установи: pip install bcrypt"
  exit 1
fi

# Загружаем переменные из .env
source .env

# Проверяем что заполнены
[[ -n "${ADMIN_EMAIL:-}" ]] || { echo "Ошибка: ADMIN_EMAIL не заполнен в .env"; exit 1; }
[[ -n "${ADMIN_PASSWORD:-}" ]] || { echo "Ошибка: ADMIN_PASSWORD не заполнен в .env"; exit 1; }
[[ -n "${PLANKA_DB_NAME:-}" ]] || { echo "Ошибка: PLANKA_DB_NAME не заполнен в .env"; exit 1; }

echo "Создаю админа в Planka..."
echo "Email: $ADMIN_EMAIL"

# Хешируем пароль bcrypt
HASH=$(ADMIN_PASSWORD="$ADMIN_PASSWORD" python3 << 'EOF'
import bcrypt
import os
pwd = os.environ['ADMIN_PASSWORD'].encode('utf-8')
hashed = bcrypt.hashpw(pwd, bcrypt.gensalt()).decode('utf-8')
print(hashed)
EOF
)

# Вставляем в БД с безопасным экранированием (используя psql переменные)
docker exec postgres psql -U admin -d "$PLANKA_DB_NAME" \
  -v email="$ADMIN_EMAIL" \
  -v pass="$HASH" << 'SQL'
INSERT INTO "user" (id, email, password, name, is_admin, created_at, updated_at)
VALUES (
  gen_random_uuid(),
  :'email',
  :'pass',
  'Administrator',
  true,
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP
)
ON CONFLICT (email) DO UPDATE
SET password = :'pass', is_admin = true, updated_at = CURRENT_TIMESTAMP;
SQL

echo ""
echo "✓ Админ успешно создан!"
echo "  Email: $ADMIN_EMAIL"
echo "  Пароль: (из ADMIN_PASSWORD в .env)"
echo ""
echo "Войти: http://192.168.1.39:3000"
