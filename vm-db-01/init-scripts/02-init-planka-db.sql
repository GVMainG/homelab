-- Создание базы данных и пользователя для Planka
-- Читает переменные окружения PLANKA_DB_USER, PLANKA_DB_PASSWORD, PLANKA_DB_NAME из контейнера
-- Выполняется автоматически при первом старте через docker-entrypoint-initdb.d

\getenv planka_db_user     PLANKA_DB_USER
\getenv planka_db_password PLANKA_DB_PASSWORD
\getenv planka_db_name     PLANKA_DB_NAME

CREATE USER :planka_db_user WITH ENCRYPTED PASSWORD :'planka_db_password';
CREATE DATABASE :planka_db_name OWNER :planka_db_user;
GRANT ALL PRIVILEGES ON DATABASE :planka_db_name TO :planka_db_user;
\connect :planka_db_name
GRANT ALL ON SCHEMA public TO :planka_db_user;
