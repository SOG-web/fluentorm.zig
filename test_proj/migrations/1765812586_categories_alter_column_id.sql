-- Migration: categories_alter_column_id
-- Table: categories
-- Type: alter_column

ALTER TABLE categories ALTER COLUMN id SET DEFAULT gen_random_uuid();
