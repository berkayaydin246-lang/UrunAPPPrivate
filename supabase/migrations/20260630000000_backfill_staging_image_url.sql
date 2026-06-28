-- Backfill product_staging.image_url from image_front_url for rows where
-- image_front_url is populated but the compatibility alias is still null.
-- Safe: only updates the alias column; never touches image_front_url.

UPDATE product_staging
SET image_url = image_front_url
WHERE source = 'web_scraper:migros'
  AND image_url IS NULL
  AND image_front_url IS NOT NULL;
