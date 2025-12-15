-- Migration: posts_alter_column_id
-- Table: posts
-- Type: alter_column

ALTER TABLE posts ALTER COLUMN id SET DEFAULT gen_random_uuid();
