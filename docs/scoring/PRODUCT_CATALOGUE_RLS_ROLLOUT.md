# Product Catalogue RLS Rollout

Scope: only `20260814010000_restrict_product_catalogue_writes.sql`.

This is a controlled manual production procedure. It does not apply the pending
score-v2 migration, rewrite score evidence, or touch historical audit rows. Do
not use `supabase db push` because this repository has historical migration
gaps.

## Access Contract

The existing `anyone can select products` RLS policy and existing SELECT grants
are intentionally unchanged, so `anon` and `authenticated` clients keep public
catalogue reads.

The migration removes the two development INSERT/UPDATE policies and revokes
INSERT, UPDATE, and DELETE from `PUBLIC`, `anon`, and `authenticated`. It then
grants INSERT/UPDATE back to `authenticated`; RLS admits only sessions for which
`public.is_freshscan_admin()` reads `app_metadata.role = admin`. DELETE remains
denied. The table privileges for `service_role` are explicit because trusted
backend and CLI ingestion bypass RLS but still require PostgreSQL privileges.

Allowed writers:

- Authenticated admins using staging approval, submission approval, OCR draft
  approval, or admin-only OFF enrichment. Each application path invokes
  `ProductScoringLifecycleService` after the product write.
- Service-role web scraper auto-approval, OFF/import tools, category-tag
  maintenance, and scoring CLIs. Scoring-relevant tools invoke the Dart
  lifecycle bridge.
- `postgres`, for controlled database administration and migrations.

Denied writers:

- Anonymous clients.
- Authenticated non-admin users.
- Consumer OFF preview/barcode flows; they remain read-only.
- Any unknown write policy. The migration aborts with
  `unexpected_products_write_policy` instead of preserving an unreviewed
  bypass.

The immutable audit table remains inaccessible directly. Current snapshot reads
use `get_current_product_score_audit_snapshot`; trusted writes use
`record_product_score_audit_snapshot`, whose security-definer gate accepts only
service role or a trusted admin and whose version/reconciliation checks remain
unchanged.

## Preflight

1. Deploy the application and operator scripts containing the centralized
   lifecycle first. Stop product import/approval workers for the migration
   window.
2. Set `SUPABASE_DB_URL` in the trusted operator shell without echoing it.
3. Record the migration checksum locally:

```bash
sha256sum supabase/migrations/20260814010000_restrict_product_catalogue_writes.sql
```

4. Run these read-only checks against production. The products policy result
   must contain only the public SELECT policy and the two known development
   write policies. Any other write policy is a stop condition.

```bash
psql "$SUPABASE_DB_URL" -X -v ON_ERROR_STOP=1 <<'SQL'
SELECT policyname, cmd, roles, qual, with_check
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'products'
ORDER BY cmd, policyname;

SELECT
  to_regprocedure('public.is_freshscan_admin()') IS NOT NULL AS admin_gate_exists,
  has_function_privilege(
    'authenticated',
    'public.is_freshscan_admin()',
    'EXECUTE'
  ) AS authenticated_can_check_admin;

SELECT
  position(
    'etiketly_score_v2' IN pg_get_functiondef(
      'public.record_product_score_audit_snapshot(uuid,text,integer,text,text,text,text,text,jsonb)'::regprocedure
    )
  ) > 0 AS audit_rpc_is_v2,
  position(
    'nutrition_quality_transform_v2' IN pg_get_functiondef(
      'public.record_product_score_audit_snapshot(uuid,text,integer,text,text,text,text,text,jsonb)'::regprocedure
    )
  ) > 0 AS audit_rpc_uses_v2_transform;

SELECT count(*) AS trusted_admin_count
FROM auth.users
WHERE raw_app_meta_data ->> 'role' = 'admin';
SQL
```

Abort if the v2 RPC is absent, the admin gate/grant is absent, no intended admin
is provisioned, or an unexpected products write policy exists.

## Controlled Apply

Apply exactly this one reviewed file, not the migration directory:

```bash
psql "$SUPABASE_DB_URL" \
  -X \
  -v ON_ERROR_STOP=1 \
  -f supabase/migrations/20260814010000_restrict_product_catalogue_writes.sql
```

The file contains `BEGIN`/`COMMIT`; any unexpected policy or SQL error rolls the
whole change back. Record the operator, UTC time, git commit, and checksum in the
release log. Do not manually mark unrelated migrations as applied.

## Post-Apply Verification

Run the following read-only checks before restarting imports:

```bash
psql "$SUPABASE_DB_URL" -X -v ON_ERROR_STOP=1 <<'SQL'
SELECT policyname, cmd, roles, qual, with_check
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'products'
ORDER BY cmd, policyname;

SELECT
  has_table_privilege('anon', 'public.products', 'SELECT') AS anon_select,
  has_table_privilege('anon', 'public.products', 'INSERT') AS anon_insert,
  has_table_privilege('anon', 'public.products', 'UPDATE') AS anon_update,
  has_table_privilege('authenticated', 'public.products', 'SELECT') AS auth_select,
  has_table_privilege('authenticated', 'public.products', 'INSERT') AS auth_insert_before_rls,
  has_table_privilege('authenticated', 'public.products', 'UPDATE') AS auth_update_before_rls,
  has_table_privilege('authenticated', 'public.products', 'DELETE') AS auth_delete,
  has_table_privilege('service_role', 'public.products', 'INSERT') AS service_insert,
  has_table_privilege('service_role', 'public.products', 'UPDATE') AS service_update;

SELECT
  has_table_privilege('anon', 'public.product_score_audit_snapshots', 'SELECT') AS anon_audit_select,
  has_table_privilege('authenticated', 'public.product_score_audit_snapshots', 'INSERT') AS auth_audit_insert,
  has_function_privilege(
    'authenticated',
    'public.record_product_score_audit_snapshot(uuid,text,integer,text,text,text,text,text,jsonb)',
    'EXECUTE'
  ) AS auth_can_call_guarded_audit_rpc;
SQL
```

Expected values: public SELECT values are true; anon writes and authenticated
DELETE are false; authenticated INSERT/UPDATE table privileges are true but are
restricted by the admin-only RLS predicates; service-role INSERT/UPDATE are
true; direct audit table privileges are false; guarded audit RPC execution is
true.

Then perform these application checks without creating arbitrary production
data:

1. Anonymous and authenticated non-admin users can open/search an existing
   product but cannot edit it.
2. A non-admin barcode scan returns an existing local product or read-only OFF
   preview without a products write request.
3. Use the next legitimate admin staging approval as the canary. Confirm its
   structured lifecycle result, persisted evidence when applicable, and matching
   current v2 audit snapshot.
4. Run one intended service-role importer in dry-run first. Resume real workers
   only after the canary passes.

## Fail-Closed Rollback

If admin product writes malfunction, pause approvals/importers and apply this
transaction. It removes app-admin writes while preserving public reads and
trusted service-role recovery tools. It deliberately does not restore the
unsafe anonymous development policies.

```sql
BEGIN;

DROP POLICY IF EXISTS "admins can insert products" ON public.products;
DROP POLICY IF EXISTS "admins can update products" ON public.products;

REVOKE INSERT, UPDATE, DELETE ON TABLE public.products FROM PUBLIC;
REVOKE INSERT, UPDATE, DELETE ON TABLE public.products FROM anon;
REVOKE INSERT, UPDATE, DELETE ON TABLE public.products FROM authenticated;
GRANT INSERT, UPDATE ON TABLE public.products TO service_role;

COMMIT;
```

After correcting the integration problem, rerun preflight and the single
migration file. Never roll back by recreating `WITH CHECK (true)` policies or by
granting catalogue writes to `anon`.
