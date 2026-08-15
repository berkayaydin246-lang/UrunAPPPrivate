-- Restrict public.product_staging to the access it actually needs before
-- release. Confirmed live production state (read-only preflight) showed RLS
-- enabled but six broad/dev policies still active, including two granting
-- anon full SELECT/UPDATE with USING (true).
--
-- Repository audit of every current product_staging access path found:
--   * Ingestion (scraper runner.py, stage_off_product.py, and the
--     import_products_from_*.py / scrape_products_from_web.py scripts) reads
--     SUPABASE_SERVICE_KEY and authenticates as service_role, which bypasses
--     RLS entirely via table grants. INSERT is service_role-only.
--   * ProductStagingApprovalRepository (lib/features/admin/repositories/
--     product_staging_approval_repository.dart) is the only live client path
--     that touches product_staging. It only ever SELECTs and UPDATEs
--     existing rows (approve/reject/needs_review, admin_notes) — it never
--     INSERTs and never DELETEs. It is reached only from the hidden
--     /internal/admin route; the Flutter route itself enforces nothing, so
--     RLS is the actual boundary and must gate on is_freshscan_admin().
--   * ProductStagingRepository (lib/features/product_staging/repositories/
--     product_staging_repository.dart), which does have an insertCandidate/
--     upsertCandidate path, is not instantiated anywhere in lib/ — dead code,
--     not a live requirement. No authenticated-admin INSERT policy is
--     created for it; if that path is wired up later, it needs its own
--     reviewed migration.
--   * No code path performs DELETE on product_staging.
--
-- Therefore: anon gets nothing. Plain authenticated (non-admin) gets nothing
-- effective. Trusted authenticated admins (is_freshscan_admin()) get SELECT +
-- UPDATE only. service_role keeps SELECT/INSERT/UPDATE for ingestion.
--
-- This migration does not touch scoring logic, product_staging data, the
-- missing 20260626010000 history gap, or 20260814010000.

BEGIN;

-- Explicitly guarantee RLS stays enabled, regardless of live drift. Not
-- FORCE ROW LEVEL SECURITY — that would also restrict the table owner and
-- would change postgres/service-role semantics beyond what this migration
-- intends.
ALTER TABLE public.product_staging ENABLE ROW LEVEL SECURITY;

-- Drop every policy name confirmed live in production.
DROP POLICY IF EXISTS "authenticated can insert product_staging" ON public.product_staging;
DROP POLICY IF EXISTS "authenticated can select product_staging" ON public.product_staging;
DROP POLICY IF EXISTS "authenticated can update product_staging" ON public.product_staging;
DROP POLICY IF EXISTS "dev anon can read product_staging" ON public.product_staging;
DROP POLICY IF EXISTS "dev anon can update product_staging" ON public.product_staging;
DROP POLICY IF EXISTS "dev authenticated can read product_staging" ON public.product_staging;

-- Also drop the migration-history policy names in case a given environment's
-- history matches the repo files rather than the confirmed live names above.
DROP POLICY IF EXISTS "dev: select product_staging" ON public.product_staging;
DROP POLICY IF EXISTS "dev: insert product_staging" ON public.product_staging;
DROP POLICY IF EXISTS "dev: update product_staging" ON public.product_staging;

-- Fail closed: product_staging must carry no policy at all until this
-- migration creates the two intended ones below. An unrecognized survivor
-- here means production drifted further than this migration accounts for —
-- stop rather than silently leaving a broader-than-intended policy active.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'product_staging'
  ) THEN
    RAISE EXCEPTION 'unexpected_product_staging_policy';
  END IF;
END;
$$;

-- Strip anon entirely — no anon workflow reads or writes product_staging.
REVOKE ALL ON TABLE public.product_staging FROM PUBLIC;
REVOKE ALL ON TABLE public.product_staging FROM anon;

-- Least privilege for authenticated: SELECT + UPDATE table grants only, so
-- RLS can admit trusted admins to the review/approval workflow. No INSERT —
-- no live authenticated/admin workflow creates staging rows. No DELETE,
-- TRUNCATE, TRIGGER, or REFERENCES — never used by any live workflow, and
-- not restored merely because Supabase previously granted them.
REVOKE ALL ON TABLE public.product_staging FROM authenticated;
GRANT SELECT, UPDATE ON TABLE public.product_staging TO authenticated;

-- service_role/backend ingestion keeps read/write access, but not the
-- DELETE/REFERENCES/TRIGGER/TRUNCATE privileges live preflight found it
-- still held. service_role bypasses RLS; these are the table grants it
-- relies on directly.
REVOKE ALL ON TABLE public.product_staging FROM service_role;
GRANT SELECT, INSERT, UPDATE ON TABLE public.product_staging TO service_role;

CREATE POLICY "admins can select product_staging"
  ON public.product_staging
  FOR SELECT
  TO authenticated
  USING (public.is_freshscan_admin());

CREATE POLICY "admins can update product_staging"
  ON public.product_staging
  FOR UPDATE
  TO authenticated
  USING (public.is_freshscan_admin())
  WITH CHECK (public.is_freshscan_admin());

COMMIT;
