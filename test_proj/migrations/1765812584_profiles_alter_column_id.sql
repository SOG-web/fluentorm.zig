-- Migration: profiles_alter_column_id
-- Table: profiles
-- Type: alter_column

ALTER TABLE profiles ALTER COLUMN id SET DEFAULT gen_random_uuid();
