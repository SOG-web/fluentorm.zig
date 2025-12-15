-- Migration: post_categories_alter_column_category_id
-- Table: post_categories
-- Type: alter_column

ALTER TABLE post_categories ALTER COLUMN category_id SET DEFAULT gen_random_uuid();
