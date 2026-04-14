-- Создание базы данных и пользователя для Vaultwarden
-- Читает переменные окружения VW_DB_USER, VW_DB_PASSWORD, VW_DB_NAME из контейнера
-- Требует PostgreSQL >= 9.6 (\getenv поддерживается в postgres:16)
-- Выполняется автоматически при первом старте через docker-entrypoint-initdb.d

\getenv vw_db_user     VW_DB_USER
\getenv vw_db_password VW_DB_PASSWORD
\getenv vw_db_name     VW_DB_NAME

CREATE USER :vw_db_user WITH ENCRYPTED PASSWORD :'vw_db_password';
CREATE DATABASE :vw_db_name OWNER :vw_db_user;
GRANT ALL PRIVILEGES ON DATABASE :vw_db_name TO :vw_db_user;
\connect :vw_db_name
GRANT ALL ON SCHEMA public TO :vw_db_user;
