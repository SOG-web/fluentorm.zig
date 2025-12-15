-- Migration: posts_alter_column_user_id
-- Table: posts
-- Type: alter_column

ALTER TABLE posts ALTER COLUMN user_id SET DEFAULT gen_random_uuid();
