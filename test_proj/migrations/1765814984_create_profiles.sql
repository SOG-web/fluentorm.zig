-- Migration: create_profiles
-- Table: profiles
-- Type: create_table

CREATE TABLE IF NOT EXISTS profiles (
  id UUID PRIMARY KEY DEFAULT 'gen_random_uuid()',
  user_id UUID NOT NULL UNIQUE DEFAULT 'gen_random_uuid()',
  bio TEXT,
  avatar_url TEXT,
  website TEXT,
  location TEXT,
  date_of_birth TIMESTAMP,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
