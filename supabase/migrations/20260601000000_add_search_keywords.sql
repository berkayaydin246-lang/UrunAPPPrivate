-- Add search_keywords column to products for improved full-text / keyword search.
--
-- search_keywords stores an array of normalized tokens (lowercase, ASCII-safe
-- variants for Turkish characters, common synonyms) built from the product name
-- and brand at import time.
--
-- The GIN index enables efficient PostgreSQL array-overlap (&&) queries:
--   SELECT * FROM products WHERE search_keywords && ARRAY['cikolata','gofret'];

ALTER TABLE products
  ADD COLUMN IF NOT EXISTS search_keywords TEXT[];

CREATE INDEX IF NOT EXISTS idx_products_search_keywords
  ON products USING GIN(search_keywords);

-- ── Lightweight SQL backfill ────────────────────────────────────────────────
-- Populate normalized_name where it is still NULL (guards against legacy rows
-- imported before this column was reliably set).
-- search_keywords requires Dart-side logic (Turkish synonym expansion); the
-- full backfill is in scripts/backfill_search_keywords.py.

UPDATE products
SET normalized_name = LOWER(
  TRIM(
    REGEXP_REPLACE(name, '[[:space:]]+', ' ', 'g')
  )
)
WHERE normalized_name IS NULL AND name IS NOT NULL;
