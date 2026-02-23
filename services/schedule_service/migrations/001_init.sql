-- Schedule Service schema
CREATE TABLE IF NOT EXISTS availability_slots (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL,
  date DATE NOT NULL,
  time_from TIME NOT NULL,
  time_to TIME NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS availability_slots_user_id_idx ON availability_slots(user_id);
CREATE INDEX IF NOT EXISTS availability_slots_date_idx ON availability_slots(date);
