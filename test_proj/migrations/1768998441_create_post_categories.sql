-- Migration: create_post_categories
-- Table: post_categories
-- Type: create_table

CREATE TABLE IF NOT EXISTS post_categories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id UUID NOT NULL DEFAULT gen_random_uuid(),
  category_id UUID NOT NULL DEFAULT gen_random_uuid(),
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
