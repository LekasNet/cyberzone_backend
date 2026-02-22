-- Rating Service schema
CREATE TABLE IF NOT EXISTS ratings (
  id UUID PRIMARY KEY,
  event_id UUID NOT NULL,
  user_id UUID NOT NULL,
  rated_by UUID NOT NULL,
  score INTEGER NOT NULL,
  comment TEXT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (event_id, user_id)
);

CREATE INDEX IF NOT EXISTS ratings_user_id_idx ON ratings(user_id);
CREATE INDEX IF NOT EXISTS ratings_event_id_idx ON ratings(event_id);
