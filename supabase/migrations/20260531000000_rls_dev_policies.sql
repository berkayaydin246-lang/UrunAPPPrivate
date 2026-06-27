-- =============================================================================
-- Development-safe RLS policies for product_submissions and products.
--
-- TODO (before production):
--   - Replace open UPDATE/INSERT policies on `products` with admin-role-only
--     or service-role-only policies.  Client-side product insert/update should
--     be locked down so only verified admin actions can modify the products table.
--   - Restrict UPDATE on `product_submissions` to admin role.
--   - Remove the `anon` role from any write policies.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- product_submissions — add missing SELECT and UPDATE policies
-- ---------------------------------------------------------------------------

-- SELECT: allow authenticated and anon clients to read their own submissions
-- (during development, open to all authenticated/anon for admin review flow).
DROP POLICY IF EXISTS "dev: select product submissions" ON product_submissions;
CREATE POLICY "dev: select product submissions"
  ON product_submissions FOR SELECT
  TO authenticated, anon
  USING (true);

-- UPDATE: required for the approval flow (status = 'approved' / 'rejected')
-- and for enriching existing pending rows with new photo uploads.
-- TODO: restrict to admin role before production.
DROP POLICY IF EXISTS "dev: update product submissions" ON product_submissions;
CREATE POLICY "dev: update product submissions"
  ON product_submissions FOR UPDATE
  TO authenticated, anon
  USING (true)
  WITH CHECK (true);

-- ---------------------------------------------------------------------------
-- products — enable RLS and add dev-safe policies
--
-- The products table had no RLS before this migration.  Enabling it here and
-- immediately adding SELECT/INSERT/UPDATE policies so the app continues to
-- read products and the admin approval flow can write new product rows.
-- ---------------------------------------------------------------------------

ALTER TABLE products ENABLE ROW LEVEL SECURITY;

-- SELECT: all app users must be able to read products.
DROP POLICY IF EXISTS "anyone can select products" ON products;
CREATE POLICY "anyone can select products"
  ON products FOR SELECT
  TO authenticated, anon
  USING (true);

-- INSERT: admin approval flow inserts products from approved submissions.
-- TODO: restrict to admin/service-role before production.
DROP POLICY IF EXISTS "dev: authenticated can insert products" ON products;
CREATE POLICY "dev: authenticated can insert products"
  ON products FOR INSERT
  TO authenticated, anon
  WITH CHECK (true);

-- UPDATE: admin approval flow updates existing products with missing fields.
-- TODO: restrict to admin/service-role before production.
DROP POLICY IF EXISTS "dev: authenticated can update products" ON products;
CREATE POLICY "dev: authenticated can update products"
  ON products FOR UPDATE
  TO authenticated, anon
  USING (true)
  WITH CHECK (true);

-- ---------------------------------------------------------------------------
-- Data cleanup: clear stale extraction_error on rows that succeeded.
-- A re-extraction that succeeds does not always clear the previous error text.
-- ---------------------------------------------------------------------------

UPDATE product_submissions
SET extraction_error = NULL
WHERE extraction_status = 'success'
  AND extraction_error IS NOT NULL;
