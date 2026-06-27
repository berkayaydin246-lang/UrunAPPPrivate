-- Migration: Add ingredient explanation metadata fields
-- Purpose: Support educational ingredient cards with calm, factual explanations
-- Fields: ingredient_type, short_purpose, short_risk_summary, caution_groups, processing_role, category_tags

ALTER TABLE ingredients
  ADD COLUMN IF NOT EXISTS ingredient_type TEXT,
  ADD COLUMN IF NOT EXISTS short_purpose TEXT,
  ADD COLUMN IF NOT EXISTS short_risk_summary TEXT,
  ADD COLUMN IF NOT EXISTS caution_groups TEXT[],
  ADD COLUMN IF NOT EXISTS processing_role TEXT,
  ADD COLUMN IF NOT EXISTS category_tags TEXT[];

-- Indexes for array columns (GIN) to support full-text and array searches
CREATE INDEX IF NOT EXISTS idx_ingredients_caution_groups ON ingredients USING GIN (caution_groups);
CREATE INDEX IF NOT EXISTS idx_ingredients_category_tags ON ingredients USING GIN (category_tags);
