-- Migration: post_categories_alter_column_post_id
-- Table: post_categories
-- Type: alter_column

ALTER TABLE post_categories ALTER COLUMN post_id SET DEFAULT gen_random_uuid();
