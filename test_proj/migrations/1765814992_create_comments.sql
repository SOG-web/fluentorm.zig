-- Migration: create_comments
-- Table: comments
-- Type: create_table

CREATE TABLE IF NOT EXISTS comments (
  id UUID PRIMARY KEY DEFAULT 'gen_random_uuid()',
  post_id UUID NOT NULL DEFAULT 'gen_random_uuid()',
  user_id UUID NOT NULL DEFAULT 'gen_random_uuid()',
  parent_id UUID DEFAULT 'gen_random_uuid()',
  content TEXT NOT NULL DEFAULT 'name',
  is_approved BOOLEAN NOT NULL DEFAULT true,
  like_count INT NOT NULL DEFAULT 0,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  deleted_at TIMESTAMP
);
