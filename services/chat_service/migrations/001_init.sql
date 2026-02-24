-- Chat Service schema
CREATE TABLE IF NOT EXISTS chats (
  id UUID PRIMARY KEY,
  event_id UUID NULL,
  type TEXT NOT NULL DEFAULT 'event',
  title TEXT NULL,
  created_by UUID NULL,
  is_active BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS chat_messages (
  id UUID PRIMARY KEY,
  chat_id UUID NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
  user_id UUID NULL,
  text TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS chats_event_id_unique
  ON chats(event_id)
  WHERE event_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS chats_event_id_idx ON chats(event_id);
CREATE INDEX IF NOT EXISTS chats_type_idx ON chats(type);
CREATE INDEX IF NOT EXISTS chat_messages_chat_id_idx ON chat_messages(chat_id);
CREATE INDEX IF NOT EXISTS chat_messages_created_at_idx ON chat_messages(created_at);
