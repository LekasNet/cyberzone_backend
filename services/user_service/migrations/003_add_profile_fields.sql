-- Add nickname and phone to users
ALTER TABLE users ADD COLUMN IF NOT EXISTS nickname TEXT NULL;
ALTER TABLE users ADD COLUMN IF NOT EXISTS phone TEXT NULL;
