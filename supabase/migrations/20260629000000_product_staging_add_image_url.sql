-- Ensure product_staging has an image_url column aligned with products.image_url.
--
-- Background: the original product_staging schema used image_front_url for the
-- main product image.  The scraper pipeline and admin approval code now use
-- image_url (matching the products table) so the mapping is explicit and the
-- same column name is used throughout the write path.
--
-- ADD COLUMN IF NOT EXISTS is idempotent: safe on databases that already have
-- this column from an earlier deployment.

ALTER TABLE product_staging
  ADD COLUMN IF NOT EXISTS image_url TEXT;
