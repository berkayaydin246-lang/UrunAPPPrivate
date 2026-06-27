# Search Keywords Backfill

## Background

`products.search_keywords TEXT[]` stores normalised token arrays used by the
category-browse and keyword-overlap search queries. `products.category_tags
TEXT[]` stores deterministic internal category labels (for example
`et_sarkuteri`, `soslar`) used as a strict pre-filter before relevance scoring.

Products imported via Open Food Facts after the `20260601000000_add_search_keywords.sql`
and `20260601010000_add_category_tags.sql` migrations get these fields
populated automatically at import time.

Products that existed before these migrations may have `search_keywords = NULL`
or `category_tags = NULL` and will be weaker in category filtering until
backfilled.

---

## Option 1 — Python script (recommended)

Requires Python 3.10+ and the `requests` package.

```bash
# Install dependency
pip install requests python-dotenv

# Set credentials (or add to .env)
export SUPABASE_URL=https://your-project.supabase.co
export SUPABASE_SERVICE_KEY=your-service-role-key

# Dry run first
python3 scripts/backfill_search_keywords.py --dry-run

# Apply
python3 scripts/backfill_search_keywords.py
```

The script processes products in batches, skips rows that already have
both `search_keywords` and `category_tags` set, and also backfills
`normalized_name` where missing.

---

## Option 2 — SQL (basic, no synonym expansion)

Run in the Supabase SQL editor. This sets a minimal normalized name and
keywords but does **not** add full synonym coverage and rich category-tag
inference used by the Python script.

```sql
UPDATE products
SET
  normalized_name = LOWER(TRIM(REGEXP_REPLACE(name, '[[:space:]]+', ' ', 'g'))),
  search_keywords = ARRAY[
    LOWER(TRIM(name)),
    LOWER(COALESCE(brand, ''))
  ],
  category_tags = ARRAY[
    CASE
      WHEN (LOWER(name) LIKE '%salam%' OR LOWER(name) LIKE '%sucuk%' OR LOWER(name) LIKE '%sosis%')
        THEN 'et_sarkuteri'
      ELSE NULL
    END
  ]
WHERE search_keywords IS NULL
  AND name IS NOT NULL;

UPDATE products
SET category_tags = ARRAY_REMOVE(category_tags, NULL)
WHERE category_tags IS NOT NULL;

UPDATE products
SET category_tags = NULL
WHERE category_tags = '{}';
```

---

## When to re-run

Re-run the script (or a targeted UPDATE) any time:

- A batch of products is imported without going through the Flutter app
- The synonym table in `ProductNameNormalizer` is expanded
- A new category is added with new keywords that should match existing products

---

## Audit: Incorrect Meat Category Assignments

Use this query to spot products currently tagged as `et_sarkuteri` that are
likely not meat/deli products (for example chocolate, sauce, biscuit words).

```sql
SELECT id, name, brand, category_tags
FROM products
WHERE category_tags @> ARRAY['et_sarkuteri']
  AND (
    LOWER(name) LIKE '%cikolata%'
    OR LOWER(name) LIKE '%çikolata%'
    OR LOWER(name) LIKE '%biskuvi%'
    OR LOWER(name) LIKE '%bisküvi%'
    OR LOWER(name) LIKE '%gofret%'
    OR LOWER(name) LIKE '%ketcap%'
    OR LOWER(name) LIKE '%ketçap%'
    OR LOWER(name) LIKE '%mayonez%'
    OR LOWER(COALESCE(brand, '')) = 'eti'
  )
ORDER BY name;
```

To remove obviously incorrect tags after manual review:

```sql
UPDATE products
SET category_tags = ARRAY_REMOVE(category_tags, 'et_sarkuteri')
WHERE id IN (
  -- paste reviewed ids here
  '00000000-0000-0000-0000-000000000000'
);
```
