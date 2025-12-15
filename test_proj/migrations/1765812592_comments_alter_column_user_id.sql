-- Migration: comments_alter_column_user_id
-- Table: comments
-- Type: alter_column

ALTER TABLE comments ALTER COLUMN user_id SET DEFAULT gen_random_uuid();
