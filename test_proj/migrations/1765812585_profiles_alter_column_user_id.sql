-- Migration: profiles_alter_column_user_id
-- Table: profiles
-- Type: alter_column

ALTER TABLE profiles ALTER COLUMN user_id SET DEFAULT gen_random_uuid();
