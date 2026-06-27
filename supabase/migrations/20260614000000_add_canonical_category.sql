-- Add canonical_category and canonical_subcategory columns (nullable).
-- These are reserved for future server-side classification.
-- The app computes them client-side from category_tags + product name;
-- these columns are intentionally not backfilled here and will be
-- populated by future scraper runs and approval flows.

ALTER TABLE products
  ADD COLUMN IF NOT EXISTS canonical_category    TEXT,
  ADD COLUMN IF NOT EXISTS canonical_subcategory TEXT;

CREATE INDEX IF NOT EXISTS idx_products_canonical_category
  ON products(canonical_category)
  WHERE canonical_category IS NOT NULL;
