# Admin: Product Submissions

When a barcode scan returns no result, the app offers a one-tap "Ürünü İncelemeye Gönder" button.
The submission is written to the `product_submissions` table.

## Table: product_submissions

| Column                   | Type        | Notes                                         |
|--------------------------|-------------|-----------------------------------------------|
| id                       | UUID        | PK, auto-generated                            |
| barcode                  | TEXT        | NOT NULL                                      |
| product_name             | TEXT        | Optional; user-provided                       |
| brand                    | TEXT        | Optional; user-provided                       |
| image_url                | TEXT        | Legacy front image URL                        |
| front_image_url          | TEXT        | Product front photo                           |
| label_image_url          | TEXT        | Ingredients/nutrition label photo             |
| extracted_ingredients_text | TEXT      | OCR extracted ingredients text (if available) |
| extracted_nutrition      | JSONB       | Nutrition extraction result (if available)    |
| extraction_status        | TEXT        | not_started / pending / success / failed      |
| extraction_error         | TEXT        | Extraction failure detail                      |
| notes                    | TEXT        | Optional; user notes                          |
| submitted_by             | UUID        | FK → auth.users(id), nullable (anon allowed)  |
| status                   | TEXT        | pending / approved / rejected / duplicate     |
| source                   | TEXT        | barcode_missing (default)                     |
| created_at               | TIMESTAMPTZ |                                               |
| updated_at               | TIMESTAMPTZ | Auto-updated via trigger                      |

## Duplicate prevention

A unique partial index on `(barcode) WHERE status = 'pending'` prevents multiple pending entries for the same barcode. The app checks for an existing pending row before inserting and shows a "zaten inceleme listesinde" message to the user.

## Admin SQL queries

### View pending submissions (newest first)
```sql
SELECT id, barcode, product_name, brand, submitted_by, created_at
FROM product_submissions
WHERE status = 'pending'
ORDER BY created_at DESC;
```

### Review-ready pending list (photos + extraction)
```sql
select barcode, product_name, brand, front_image_url, label_image_url,
       extracted_ingredients_text, extracted_nutrition, status, extraction_status, created_at
from product_submissions
where status = 'pending'
order by created_at desc;
```

### Mark a submission as approved
```sql
UPDATE product_submissions
SET status = 'approved'
WHERE barcode = '<barcode>';
```

### Mark as rejected
```sql
UPDATE product_submissions
SET status = 'rejected'
WHERE id = '<uuid>';
```

### Count pending by barcode (find most-requested missing products)
```sql
SELECT barcode, product_name, COUNT(*) AS request_count
FROM product_submissions
GROUP BY barcode, product_name
ORDER BY request_count DESC;
```

### All submissions for a specific barcode
```sql
SELECT *
FROM product_submissions
WHERE barcode = '<barcode>'
ORDER BY created_at DESC;
```

### Cleanup: mark all pending for an approved barcode as duplicate
```sql
UPDATE product_submissions
SET status = 'duplicate'
WHERE barcode = '<barcode>'
  AND status = 'pending';
```

---

## Admin approval flow

The in-app admin review UI is available at:
- **List**: `/internal/product-submissions`
- **Detail**: `/internal/product-submissions/<id>`

The detail page lets the admin edit `product_name`, `brand`, and `ingredients_text` before approving.
Tapping **Onayla** calls `approveProductSubmission` which:

1. Reads `product_submissions` by `id` (requires `status = pending`).
2. Checks `products` for a row with the same `barcode`.
3. **If not found**: inserts a new product with `verification_status = user_submitted`.
4. **If found**: enriches only null/empty fields (never overwrites verified data).
5. Sets `product_submissions.status = approved`.

After approval the barcode scanner finds the product in the `products` table and
navigates to the product detail page instead of the "not found" screen.

### Verify a product was created after approval
```sql
SELECT barcode, name, brand, image_url, ingredients_text,
       nutrition_text, verification_status, source
FROM products
WHERE barcode = '<barcode>';
```

### List all approved submissions with their resulting products
```sql
SELECT ps.id          AS submission_id,
       ps.barcode,
       ps.product_name AS submitted_name,
       ps.updated_at  AS approved_at,
       p.id           AS product_id,
       p.name         AS product_name,
       p.verification_status
FROM product_submissions ps
LEFT JOIN products p ON p.barcode = ps.barcode
WHERE ps.status = 'approved'
ORDER BY ps.updated_at DESC;
```

### List rejected submissions
```sql
SELECT id, barcode, product_name, notes AS rejection_reason, updated_at
FROM product_submissions
WHERE status = 'rejected'
ORDER BY updated_at DESC;
```

### Find products from user submissions that still need verification
```sql
SELECT id, barcode, name, brand, verification_status, created_at
FROM products
WHERE source = 'user_submission'
  AND verification_status = 'user_submitted'
ORDER BY created_at DESC;
```

### Promote a user-submitted product to verified (after manual review)
```sql
UPDATE products
SET verification_status = 'verified'
WHERE barcode = '<barcode>'
  AND source = 'user_submission';
```
