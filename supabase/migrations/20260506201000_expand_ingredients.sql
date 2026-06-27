-- Migration: expand ingredients table with richer metadata
ALTER TABLE ingredients
  ADD COLUMN IF NOT EXISTS aliases TEXT[],
  ADD COLUMN IF NOT EXISTS common_names TEXT[],
  ADD COLUMN IF NOT EXISTS english_names TEXT[],
  ADD COLUMN IF NOT EXISTS additive_group TEXT,
  ADD COLUMN IF NOT EXISTS child_warning TEXT,
  ADD COLUMN IF NOT EXISTS source_references TEXT[];

-- Indexes for new array columns (GIN) to allow searching if needed
CREATE INDEX IF NOT EXISTS idx_ingredients_aliases ON ingredients USING GIN (aliases);
CREATE INDEX IF NOT EXISTS idx_ingredients_common_names ON ingredients USING GIN (common_names);
CREATE INDEX IF NOT EXISTS idx_ingredients_english_names ON ingredients USING GIN (english_names);
