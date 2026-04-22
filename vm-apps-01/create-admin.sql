-- SQL скрипт для создания администратора в Planka
-- Выполнить в pgAdmin или psql

INSERT INTO "user_account" (
  email,
  password,
  role,
  name,
  subscribe_to_own_cards,
  subscribe_to_card_when_commenting,
  turn_off_recent_card_highlighting,
  enable_favorites_by_default,
  default_editor_mode,
  default_home_view,
  default_projects_order,
  is_sso_user,
  is_deactivated
) VALUES (
  'gv-it-lab@yandex.ru',
  '$2a$12$hd5pAQfntQ7QplJNH4aWbuBSU2klRnree.87.tMdTwsBEldef0UGK',
  'ADMIN',
  'Administrator',
  false,
  false,
  false,
  false,
  'REGULAR',
  'BOARDS',
  'BY_NAME',
  false,
  false
);
