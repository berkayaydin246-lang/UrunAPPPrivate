-- product_staging: holding area for external/manual/user-submitted product
-- candidates BEFORE they enter the clean `products` catalog.
--
-- Open Food Facts (and future market connectors) have inconsistent data quality,
-- so every candidate is staged here for deterministic quality scoring and admin
-- review. Nothing in this table is shown to end users. Admin approval (a later
-- task) is what promotes a staged row into `products`.
--
-- This table is intentionally separate from `product_submissions`
-- (user photo submissions). They are NOT merged in this task.

CREATE TABLE IF NOT EXISTS product_staging (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Core
  barcode TEXT,
  name TEXT,
  brand TEXT,
  category_suggestion TEXT,
  category_tags TEXT[],
  search_keywords TEXT[],

  -- Images
  image_front_url TEXT,
  image_front_storage_path TEXT,
  image_ingredients_url TEXT,
  image_nutrition_url TEXT,

  -- Extracted data
  ingredients_text TEXT,
  nutrition_json JSONB,

  -- Source tracking
  -- examples: open_food_facts, manual_seed, user_submission, migros, trendyol
  source TEXT NOT NULL,
  source_url TEXT,
  raw_source_payload JSONB,

  -- Field-level source tracking
  name_source TEXT,
  brand_source TEXT,
  image_source TEXT,
  ingredients_source TEXT,
  nutrition_source TEXT,
  category_source TEXT,

  -- Quality / review
  quality_score INT NOT NULL DEFAULT 0,
  missing_fields TEXT[] NOT NULL DEFAULT '{}',
  status TEXT NOT NULL DEFAULT 'pending',
  admin_notes TEXT,

  -- Timestamps
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT product_staging_status_check CHECK (
    status IN (
      'pending', 'needs_review', 'approved',
      'rejected', 'duplicate', 'insufficient_data'
    )
  ),
  CONSTRAINT product_staging_quality_score_check CHECK (
    quality_score BETWEEN 0 AND 100
  )
);

-- Indexes
-- NOTE: barcode is intentionally NOT unique. Multiple sources may submit
-- candidates for the same barcode; dedupe/merge happens in the service layer
-- (ProductStagingRepository.upsertCandidate matches on barcode + source).
CREATE INDEX IF NOT EXISTS idx_product_staging_barcode
  ON product_staging (barcode);
CREATE INDEX IF NOT EXISTS idx_product_staging_barcode_source
  ON product_staging (barcode, source);
CREATE INDEX IF NOT EXISTS idx_product_staging_status
  ON product_staging (status);
CREATE INDEX IF NOT EXISTS idx_product_staging_source
  ON product_staging (source);
CREATE INDEX IF NOT EXISTS idx_product_staging_created_at
  ON product_staging (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_product_staging_category_tags
  ON product_staging USING GIN (category_tags);
CREATE INDEX IF NOT EXISTS idx_product_staging_search_keywords
  ON product_staging USING GIN (search_keywords);

-- Keep updated_at fresh on every UPDATE (reuses the shared trigger function
-- defined in the init schema migration).
DROP TRIGGER IF EXISTS product_staging_update_timestamp ON product_staging;
CREATE TRIGGER product_staging_update_timestamp
  BEFORE UPDATE ON product_staging
  FOR EACH ROW EXECUTE FUNCTION update_timestamp();

-- ── Row Level Security ──────────────────────────────────────────────────────
-- product_staging must NOT be writable by anon users.
-- For now, authenticated users may select/insert/update.
--
-- TODO (before production): restrict INSERT/UPDATE to an admin role or the
-- service role only. Authenticated end-users should not be able to write
-- staging candidates directly once admin-role infrastructure exists.
-- Do NOT add anon insert/update policies.

ALTER TABLE product_staging ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "authenticated can select product_staging" ON product_staging;
CREATE POLICY "authenticated can select product_staging"
  ON product_staging FOR SELECT
  TO authenticated
  USING (true);

DROP POLICY IF EXISTS "authenticated can insert product_staging" ON product_staging;
CREATE POLICY "authenticated can insert product_staging"
  ON product_staging FOR INSERT
  TO authenticated
  WITH CHECK (true);

DROP POLICY IF EXISTS "authenticated can update product_staging" ON product_staging;
CREATE POLICY "authenticated can update product_staging"
  ON product_staging FOR UPDATE
  TO authenticated
  USING (true)
  WITH CHECK (true);
