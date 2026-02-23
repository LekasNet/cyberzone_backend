-- Notification Service schema
CREATE TABLE IF NOT EXISTS notifications_tokens (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL,
  device_token TEXT NOT NULL UNIQUE,
  platform TEXT NOT NULL,
  last_used_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS notifications_tokens_user_id_idx ON notifications_tokens(user_id);
CREATE INDEX IF NOT EXISTS notifications_tokens_last_used_at_idx ON notifications_tokens(last_used_at);
