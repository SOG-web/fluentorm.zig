-- Migration: comments_alter_column_id
-- Table: comments
-- Type: alter_column

ALTER TABLE comments ALTER COLUMN id SET DEFAULT gen_random_uuid();
