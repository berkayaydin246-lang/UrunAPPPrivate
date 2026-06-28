-- Backfill products.image_url for already-approved Migros rows whose staging
-- entry has image_front_url but products ended up with a null image_url.
-- Matched on source_url (most stable key). Never overwrites existing images.

UPDATE products p
SET image_url = s.image_front_url
FROM product_staging s
WHERE p.source = 'web_scraper:migros'
  AND s.source = 'web_scraper:migros'
  AND p.source_url = s.source_url
  AND (p.image_url IS NULL OR p.image_url = '')
  AND s.image_front_url IS NOT NULL
  AND s.image_front_url != '';
