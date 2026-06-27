-- Add category_tags column to products for strict deterministic category filtering.
--
-- category_tags stores canonical internal tags such as:
--   et_sarkuteri, cikolata_gofret, soslar
-- It is used as a fast candidate pre-filter before the relevance engine.

ALTER TABLE products
  ADD COLUMN IF NOT EXISTS category_tags TEXT[];

CREATE INDEX IF NOT EXISTS idx_products_category_tags
  ON products USING GIN(category_tags);

-- Optional SQL-only baseline backfill (lightweight).
-- For richer deterministic tagging, run scripts/backfill_search_keywords.py
-- which also populates search_keywords using the same normalizer rules.
UPDATE products
SET category_tags = ARRAY[
  CASE
    WHEN (
      COALESCE(name, '') ILIKE '%salam%'
      OR COALESCE(name, '') ILIKE '%sucuk%'
      OR COALESCE(name, '') ILIKE '%sosis%'
      OR COALESCE(name, '') ILIKE '%jambon%'
      OR COALESCE(name, '') ILIKE '%pastırma%'
      OR COALESCE(name, '') ILIKE '%pastirma%'
    ) THEN 'et_sarkuteri'
    ELSE NULL
  END,
  CASE
    WHEN (
      COALESCE(name, '') ILIKE '%ketçap%'
      OR COALESCE(name, '') ILIKE '%ketcap%'
      OR COALESCE(name, '') ILIKE '%ketchup%'
      OR COALESCE(name, '') ILIKE '%mayonez%'
      OR COALESCE(name, '') ILIKE '%mayonnaise%'
    ) THEN 'soslar'
    ELSE NULL
  END
]
WHERE category_tags IS NULL;

UPDATE products
SET category_tags = ARRAY_REMOVE(category_tags, NULL)
WHERE category_tags IS NOT NULL;

-- Keep empty arrays as NULL so overlap queries remain selective.
UPDATE products
SET category_tags = NULL
WHERE category_tags = '{}';
