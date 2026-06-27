-- Development-safe RLS for product_staging.
--
-- The initial product_staging policies were `TO authenticated` only. The Flutter
-- app talks to Supabase with the anon key, so the admin approval flow (running as
-- anon during development) could INSERT/UPDATE `products` (which already has anon
-- dev policies) but its UPDATE of product_staging.status was silently filtered by
-- RLS — leaving approved rows stuck at status = 'pending'.
--
-- These policies mirror the products dev policies in 20260531000000_rls_dev_policies.sql
-- so the staging review/approval flow works end-to-end during development.
--
-- TODO (before production): restrict INSERT/UPDATE on product_staging to an admin
-- role or the service role only, and remove the anon policies below.

ALTER TABLE product_staging ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "authenticated can select product_staging" ON product_staging;
DROP POLICY IF EXISTS "dev: select product_staging" ON product_staging;
CREATE POLICY "dev: select product_staging"
  ON product_staging FOR SELECT
  TO authenticated, anon
  USING (true);

DROP POLICY IF EXISTS "authenticated can insert product_staging" ON product_staging;
DROP POLICY IF EXISTS "dev: insert product_staging" ON product_staging;
CREATE POLICY "dev: insert product_staging"
  ON product_staging FOR INSERT
  TO authenticated, anon
  WITH CHECK (true);

DROP POLICY IF EXISTS "authenticated can update product_staging" ON product_staging;
DROP POLICY IF EXISTS "dev: update product_staging" ON product_staging;
CREATE POLICY "dev: update product_staging"
  ON product_staging FOR UPDATE
  TO authenticated, anon
  USING (true)
  WITH CHECK (true);
