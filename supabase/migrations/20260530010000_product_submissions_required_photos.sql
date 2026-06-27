-- Expand product_submissions for required photo-based review quality.

ALTER TABLE product_submissions
  ADD COLUMN IF NOT EXISTS front_image_url TEXT,
  ADD COLUMN IF NOT EXISTS label_image_url TEXT,
  ADD COLUMN IF NOT EXISTS extracted_ingredients_text TEXT,
  ADD COLUMN IF NOT EXISTS extracted_nutrition JSONB,
  ADD COLUMN IF NOT EXISTS extraction_status TEXT NOT NULL DEFAULT 'not_started',
  ADD COLUMN IF NOT EXISTS extraction_error TEXT;

-- Keep extraction status deterministic and auditable.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'product_submissions_extraction_status_check'
  ) THEN
    ALTER TABLE product_submissions
      ADD CONSTRAINT product_submissions_extraction_status_check
      CHECK (extraction_status IN ('not_started', 'pending', 'success', 'failed'));
  END IF;
END
$$;

-- Bucket for missing product submission photos.
INSERT INTO storage.buckets (id, name, public)
VALUES ('product-submissions', 'product-submissions', true)
ON CONFLICT (id) DO NOTHING;
