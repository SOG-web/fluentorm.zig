-- Migration: post_categories_alter_column_id
-- Table: post_categories
-- Type: alter_column

ALTER TABLE post_categories ALTER COLUMN id SET DEFAULT gen_random_uuid();
