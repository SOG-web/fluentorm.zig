-- Migration: comments_alter_column_parent_id
-- Table: comments
-- Type: alter_column

ALTER TABLE comments ALTER COLUMN parent_id SET DEFAULT null;
