-- User Service schema
CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY,
  email TEXT NOT NULL UNIQUE,
  first_name TEXT NULL,
  last_name TEXT NULL,
  institute TEXT NULL,
  "group" TEXT NULL,
  avatar_url TEXT NULL,
  is_admin BOOLEAN NOT NULL DEFAULT false,
  is_super_admin BOOLEAN NOT NULL DEFAULT false,
  is_banned BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS roles (
  id UUID PRIMARY KEY,
  name TEXT NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS disciplines (
  id UUID PRIMARY KEY,
  name TEXT NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS user_roles (
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role_id UUID NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
  PRIMARY KEY (user_id, role_id)
);

CREATE TABLE IF NOT EXISTS user_disciplines (
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  discipline_id UUID NOT NULL REFERENCES disciplines(id) ON DELETE CASCADE,
  PRIMARY KEY (user_id, discipline_id)
);

CREATE INDEX IF NOT EXISTS users_email_idx ON users(email);
CREATE INDEX IF NOT EXISTS user_roles_role_id_idx ON user_roles(role_id);
CREATE INDEX IF NOT EXISTS user_disciplines_discipline_id_idx ON user_disciplines(discipline_id);
