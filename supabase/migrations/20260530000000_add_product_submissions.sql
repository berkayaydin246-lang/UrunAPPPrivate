-- Product submissions: barcode-missing flow with photo upload and automatic OCR extraction.
-- Separate from user_submissions (which is a full form with images and OCR text).

CREATE TABLE IF NOT EXISTS product_submissions (
  id                        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  barcode                   TEXT NOT NULL,
  product_name              TEXT,
  brand                     TEXT,
  -- image_url kept for backward-compat; front_image_url is the preferred column.
  image_url                 TEXT,
  front_image_url           TEXT,
  label_image_url           TEXT,
  -- OCR / extraction outputs (populated automatically after photo upload)
  extracted_ingredients_text TEXT,
  extracted_nutrition        JSONB,
  extraction_status          TEXT NOT NULL DEFAULT 'not_started'
                               CHECK (extraction_status IN ('not_started', 'success', 'failed')),
  extraction_error           TEXT,
  notes                     TEXT,
  submitted_by              UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  status                    TEXT NOT NULL DEFAULT 'pending'
                              CHECK (status IN ('pending', 'approved', 'rejected', 'duplicate')),
  source                    TEXT NOT NULL DEFAULT 'barcode_missing',
  created_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at                TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Prevent duplicate pending submissions for the same barcode.
-- Application logic checks first so we avoid a DB error surfacing to the user.
-- When a pending row already exists, the new submission UPDATES it (new photos + re-extraction).
CREATE UNIQUE INDEX IF NOT EXISTS product_submissions_pending_barcode_unique
  ON product_submissions (barcode)
  WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS product_submissions_barcode_idx   ON product_submissions (barcode);
CREATE INDEX IF NOT EXISTS product_submissions_status_idx    ON product_submissions (status);
CREATE INDEX IF NOT EXISTS product_submissions_created_idx   ON product_submissions (created_at DESC);

-- Auto-update updated_at on any modification.
CREATE OR REPLACE FUNCTION update_product_submissions_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER product_submissions_updated_at
  BEFORE UPDATE ON product_submissions
  FOR EACH ROW EXECUTE FUNCTION update_product_submissions_updated_at();

-- RLS: authenticated users may insert; read/update reserved for admins via service role.
ALTER TABLE product_submissions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "authenticated users can insert product submissions"
  ON product_submissions FOR INSERT
  TO authenticated
  WITH CHECK (true);
