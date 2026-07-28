-- Add colors to roles and disciplines
ALTER TABLE roles ADD COLUMN IF NOT EXISTS color TEXT NULL;
ALTER TABLE disciplines ADD COLUMN IF NOT EXISTS color TEXT NULL;

UPDATE roles SET color = '#E53935' WHERE color IS NULL AND name = 'Commentator';
UPDATE roles SET color = '#1E88E5' WHERE color IS NULL AND name = 'Analyst';
UPDATE roles SET color = '#8E24AA' WHERE color IS NULL AND name = 'Judge';
UPDATE roles SET color = '#43A047' WHERE color IS NULL AND name = 'Observer';
UPDATE roles SET color = '#FB8C00' WHERE color IS NULL AND name = 'Sound Engineer';
UPDATE roles SET color = '#6D4C41' WHERE color IS NULL AND name = 'Operator';
UPDATE roles SET color = '#3949AB' WHERE color IS NULL AND name = 'Photographer';
UPDATE roles SET color = '#D81B60' WHERE color IS NULL AND name = 'Cosplayer';

UPDATE disciplines SET color = '#1B5E20' WHERE color IS NULL AND name = 'CS';
UPDATE disciplines SET color = '#B71C1C' WHERE color IS NULL AND name = 'Dota';
UPDATE disciplines SET color = '#0D47A1' WHERE color IS NULL AND name = 'LoL';
