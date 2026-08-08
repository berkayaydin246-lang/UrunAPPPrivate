-- Optional nutrition-label image for manual review and structured OCR.
-- Existing submissions remain valid and continue using label_image_url.

ALTER TABLE product_submissions
  ADD COLUMN IF NOT EXISTS nutrition_image_url TEXT;

COMMENT ON COLUMN product_submissions.nutrition_image_url IS
  'Optional product nutrition-table image uploaded for OCR and admin review.';
