-- Migration: users_alter_column_id
-- Table: users
-- Type: alter_column

ALTER TABLE users ALTER COLUMN id SET DEFAULT gen_random_uuid();
