-- Remove the original development-only catalogue write policies before release.
-- Service-role operations bypass RLS; authenticated Flutter writes require the
-- trusted app_metadata admin claim checked by is_freshscan_admin().

BEGIN;

-- Production preflight proved these dashboard-era policies are exact
-- duplicates of the canonical development policies below.
DROP POLICY IF EXISTS "Allow products insert"
  ON public.products;
DROP POLICY IF EXISTS "Allow products select"
  ON public.products;
DROP POLICY IF EXISTS "Allow products update"
  ON public.products;

DROP POLICY IF EXISTS "dev: authenticated can insert products"
  ON public.products;
DROP POLICY IF EXISTS "dev: authenticated can update products"
  ON public.products;
DROP POLICY IF EXISTS "admins can insert products"
  ON public.products;
DROP POLICY IF EXISTS "admins can update products"
  ON public.products;

-- Fail closed if production has an untracked permissive write policy. The
-- controlled rollout must inspect and reconcile it instead of silently leaving
-- a lifecycle bypass in place.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'products'
      AND cmd IN ('ALL', 'INSERT', 'UPDATE', 'DELETE')
  ) THEN
    RAISE EXCEPTION 'unexpected_products_write_policy';
  END IF;
END;
$$;

REVOKE INSERT, UPDATE, DELETE ON TABLE public.products FROM PUBLIC;
REVOKE INSERT, UPDATE, DELETE ON TABLE public.products FROM anon;
REVOKE INSERT, UPDATE, DELETE ON TABLE public.products FROM authenticated;

-- Authenticated needs table privileges before RLS can admit trusted admins.
-- Service-role tools use these grants and bypass RLS, but remain required to
-- invoke the source-neutral scoring lifecycle after every relevant write.
GRANT INSERT, UPDATE ON TABLE public.products TO authenticated;
GRANT INSERT, UPDATE ON TABLE public.products TO service_role;

CREATE POLICY "admins can insert products"
  ON public.products
  FOR INSERT
  TO authenticated
  WITH CHECK (public.is_freshscan_admin());

CREATE POLICY "admins can update products"
  ON public.products
  FOR UPDATE
  TO authenticated
  USING (public.is_freshscan_admin())
  WITH CHECK (public.is_freshscan_admin());

-- The function body remains unchanged. Restrict invocation to the roles that
-- are admitted by its service-role/admin authorization gate.
REVOKE EXECUTE ON FUNCTION public.record_product_score_audit_snapshot(
  UUID, TEXT, INTEGER, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB
) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.record_product_score_audit_snapshot(
  UUID, TEXT, INTEGER, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB
) FROM anon;
GRANT EXECUTE ON FUNCTION public.record_product_score_audit_snapshot(
  UUID, TEXT, INTEGER, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB
) TO authenticated, service_role, postgres;

COMMIT;
