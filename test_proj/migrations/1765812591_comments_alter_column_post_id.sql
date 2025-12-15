-- Migration: comments_alter_column_post_id
-- Table: comments
-- Type: alter_column

ALTER TABLE comments ALTER COLUMN post_id SET DEFAULT gen_random_uuid();
