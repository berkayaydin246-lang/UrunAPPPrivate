"""Automatic web product discovery / scraping pipeline.

This package crawls *configured* product source URLs, extracts product data
(name, brand, image, ingredients, nutrition, category, barcode when present),
normalizes and quality-scores it, and stages the result in `product_staging`
for admin review.

Hard rules (see docs/PRODUCT_DATABASE_SEEDING.md):
  * Candidates are written to `product_staging` ONLY — never to `products`.
  * Nothing is auto-approved. Missing data is never invented.
  * Scraping is polite: rate limited, controlled by config, no anti-bot bypass,
    no authenticated/private pages.

The package is intentionally self-contained; it reuses the existing
`ProductCandidate` shape (the same columns the barcode importer writes) so
scraped rows show up in the existing admin staging UI unchanged.
"""

__all__ = [
    "base",
    "source_config",
    "extractors",
    "image_scoring",
    "nutrition_parser",
    "ingredient_parser",
    "runner",
]
