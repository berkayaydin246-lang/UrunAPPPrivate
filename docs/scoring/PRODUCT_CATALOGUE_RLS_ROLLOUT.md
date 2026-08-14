# Product Catalogue RLS Rollout

Scope: only `20260814010000_restrict_product_catalogue_writes.sql`.

This is a controlled manual production procedure. It does not apply the pending
score-v2 migration, rewrite score evidence, or touch historical audit rows. Do
not use `supabase db push` because this repository has historical migration
gaps.

## Access Contract

The existing `anyone can select products` RLS policy and existing SELECT grants
are intentionally unchanged, so `anon` and `authenticated` clients keep public
catalogue reads. Production preflight also found three dashboard-era policies,
`Allow products select`, `Allow products insert`, and `Allow products update`.
Their commands, roles, modes, and predicates were independently verified as
exact duplicates of the canonical development policies. The migration removes
only those named duplicates; it does not tolerate arbitrary policy drift.

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
unchanged. The migration removes a verified direct `anon` EXECUTE grant from
the write RPC, revokes `PUBLIC` as defense in depth, and preserves EXECUTE for
`authenticated`, `service_role`, and `postgres`. It does not change the write
RPC body or any access to the audit read RPC.

Production also has verified direct `anon` EXECUTE drift on the four historical
admin functions listed below. Their definitions and internal authorization
gates match the reviewed repository migration, so this known pre-migration ACL
state is accepted only for this controlled remediation. The pending migration
revokes `PUBLIC` and `anon`, restores EXECUTE for `authenticated`,
`service_role`, and `postgres`, and does not replace any function body.

Pre-migration ACL state accepted by this rollout:

| Function | PUBLIC | anon | authenticated | service_role | postgres |
| --- | --- | --- | --- | --- | --- |
| `is_freshscan_admin()` | false | true | true | true | true |
| `admin_get_product_report(uuid)` | false | true | true | true | true |
| `admin_list_product_reports(text,integer,timestamptz,uuid)` | false | true | true | true | true |
| `admin_update_product_report(uuid,text,text)` | false | true | true | true | true |
| `record_product_score_audit_snapshot(uuid,text,integer,text,text,text,text,text,jsonb)` | false | true | true | true | true |

Post-migration ACL state required for all five functions is `PUBLIC=false`,
`anon=false`, `authenticated=true`, `service_role=true`, and `postgres=true`.
The audit read RPC is outside this ACL repair and remains unchanged.

## Historical Migration Drift

Production migration history does not contain `20260626010000`, and that row
must not be repaired. Read-only inspection independently verified that its four
runtime functions exist with the expected security and authorization semantics:

- `public.is_freshscan_admin()`
- `public.admin_list_product_reports(text,integer,timestamptz,uuid)`
- `public.admin_get_product_report(uuid)`
- `public.admin_update_product_report(uuid,text,text)`

This rollout depends on the runtime `is_freshscan_admin()` function, not the
historical bookkeeping row. Never use `supabase migration repair`, `supabase db
push`, or a manual insert into `supabase_migrations.schema_migrations` to close
this documented gap.

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
   must contain exactly the three canonical development policies and their
   three verified `Allow products ...` duplicates. Their paired commands,
   roles, permissive modes, `qual`, and `with_check` values must still match.
   Any other policy is a stop condition.

```bash
psql "$SUPABASE_DB_URL" -X -v ON_ERROR_STOP=1 <<'SQL'
BEGIN TRANSACTION READ ONLY;

SELECT policyname, cmd, roles, permissive, qual, with_check
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'products'
ORDER BY cmd, policyname;

WITH allowed(policyname) AS (
  VALUES
    ('Allow products insert'),
    ('Allow products select'),
    ('Allow products update'),
    ('anyone can select products'),
    ('dev: authenticated can insert products'),
    ('dev: authenticated can update products')
), actual AS (
  SELECT policyname
  FROM pg_policies
  WHERE schemaname = 'public' AND tablename = 'products'
)
SELECT
  NOT EXISTS (SELECT * FROM allowed EXCEPT SELECT * FROM actual)
    AS no_reviewed_policy_missing,
  NOT EXISTS (SELECT * FROM actual EXCEPT SELECT * FROM allowed)
    AS no_unknown_policy;

WITH pairs(allow_name, canonical_name) AS (
  VALUES
    ('Allow products insert', 'dev: authenticated can insert products'),
    ('Allow products select', 'anyone can select products'),
    ('Allow products update', 'dev: authenticated can update products')
), policies AS (
  SELECT
    policyname,
    cmd,
    ARRAY(SELECT role FROM unnest(roles) role ORDER BY role) AS roles,
    permissive,
    qual,
    with_check
  FROM pg_policies
  WHERE schemaname = 'public' AND tablename = 'products'
)
SELECT
  pairs.allow_name,
  pairs.canonical_name,
  allow_policy.cmd IS NOT DISTINCT FROM canonical.cmd
    AND allow_policy.roles IS NOT DISTINCT FROM canonical.roles
    AND allow_policy.permissive IS NOT DISTINCT FROM canonical.permissive
    AND allow_policy.qual IS NOT DISTINCT FROM canonical.qual
    AND allow_policy.with_check IS NOT DISTINCT FROM canonical.with_check
    AS definitions_match
FROM pairs
LEFT JOIN policies allow_policy
  ON allow_policy.policyname = pairs.allow_name
LEFT JOIN policies canonical
  ON canonical.policyname = pairs.canonical_name;

SELECT
  to_regprocedure('public.is_freshscan_admin()') IS NOT NULL AS admin_gate_exists,
  has_function_privilege(
    'authenticated',
    'public.is_freshscan_admin()',
    'EXECUTE'
  ) AS authenticated_can_check_admin;

WITH expected(signature, security_definer, volatility) AS (
  VALUES
    ('public.is_freshscan_admin()', false, 's'),
    ('public.admin_get_product_report(uuid)', true, 'v'),
    (
      'public.admin_list_product_reports(text,integer,timestamptz,uuid)',
      true,
      'v'
    ),
    ('public.admin_update_product_report(uuid,text,text)', true, 'v')
), definitions AS (
  SELECT
    expected.signature,
    expected.security_definer,
    expected.volatility,
    p.prosecdef AS actual_security_definer,
    p.provolatile::TEXT AS actual_volatility,
    p.proconfig,
    pg_get_functiondef(p.oid) AS body
  FROM expected
  LEFT JOIN pg_proc p ON p.oid = to_regprocedure(expected.signature)
)
SELECT
  signature,
  body IS NOT NULL AS function_exists,
  actual_security_definer = security_definer AS security_mode_matches,
  actual_volatility = volatility AS volatility_matches,
  'search_path=public, pg_temp' = ANY (proconfig) AS fixed_search_path,
  position('is_freshscan_admin()' IN body) > 0
    OR signature = 'public.is_freshscan_admin()' AS has_or_is_admin_gate,
  position('not_authorized' IN body) > 0
    OR signature = 'public.is_freshscan_admin()' AS rejects_or_is_admin_gate,
  CASE
    WHEN signature = 'public.is_freshscan_admin()' THEN
      position('auth.uid() IS NOT NULL' IN body) > 0
      AND position('app_metadata' IN body) > 0
      AND position('= ''admin''' IN body) > 0
    ELSE position('IF NOT public.is_freshscan_admin()' IN body) > 0
  END AS trusted_gate_matches,
  CASE signature
    WHEN 'public.is_freshscan_admin()' THEN true
    WHEN 'public.admin_get_product_report(uuid)' THEN
      position('IF NOT public.is_freshscan_admin()' IN body) > 0
      AND position('IF NOT public.is_freshscan_admin()' IN body)
        < position('SELECT jsonb_build_object(' IN body)
    WHEN 'public.admin_list_product_reports(text,integer,timestamptz,uuid)' THEN
      position('IF NOT public.is_freshscan_admin()' IN body) > 0
      AND position('IF NOT public.is_freshscan_admin()' IN body)
        < position('SELECT COALESCE(' IN body)
    WHEN 'public.admin_update_product_report(uuid,text,text)' THEN
      position('IF NOT public.is_freshscan_admin()' IN body) > 0
      AND position('IF NOT public.is_freshscan_admin()' IN body)
        < position('SELECT status' IN body)
  END AS gate_precedes_privileged_work
FROM definitions
ORDER BY signature;

WITH definition AS (
  SELECT pg_get_functiondef(
    'public.record_product_score_audit_snapshot(uuid,text,integer,text,text,text,text,text,jsonb)'::regprocedure
  ) AS body
)
SELECT
  position('auth.role()' IN body) > 0 AS checks_auth_role,
  position('service_role' IN body) > 0 AS checks_service_role,
  position('is_freshscan_admin()' IN body) > 0 AS checks_admin_gate,
  position('not_authorized' IN body) > 0 AS rejects_untrusted_callers,
  position('42501' IN body) > 0 AS uses_authorization_sqlstate,
  position('snapshot_product_version_stale' IN body) > 0
    AS checks_product_version,
  position('snapshot_score_reconciliation_failed' IN body) > 0
    AS checks_score_reconciliation,
  position('etiketly_score_v2' IN body) > 0 AS audit_rpc_is_v2,
  position('nutrition_quality_transform_v2' IN body) > 0
    AS audit_rpc_uses_v2_transform,
  position('additive_quality_transform_v1' IN body) > 0
    AS audit_rpc_uses_additive_transform_v1
FROM definition;

WITH functions(function_name, signature) AS (
  VALUES
    ('admin gate', 'public.is_freshscan_admin()'),
    ('admin get', 'public.admin_get_product_report(uuid)'),
    (
      'admin list',
      'public.admin_list_product_reports(text,integer,timestamptz,uuid)'
    ),
    (
      'admin update',
      'public.admin_update_product_report(uuid,text,text)'
    ),
    (
      'audit write',
      'public.record_product_score_audit_snapshot(uuid,text,integer,text,text,text,text,text,jsonb)'
    )
), roles(role_name) AS (
  VALUES ('PUBLIC'), ('anon'), ('authenticated'), ('service_role'), ('postgres')
)
SELECT
  function_name,
  role_name,
  CASE
    WHEN role_name = 'PUBLIC' THEN EXISTS (
      SELECT 1
      FROM aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) acl
      WHERE acl.grantee = 0 AND acl.privilege_type = 'EXECUTE'
    )
    ELSE has_function_privilege(role_name, p.oid, 'EXECUTE')
  END AS can_execute
FROM functions
JOIN pg_proc p ON p.oid = to_regprocedure(signature)
CROSS JOIN roles
ORDER BY function_name, role_name;

SELECT
  to_regprocedure('public.is_freshscan_admin()') AS admin_gate,
  to_regprocedure(
    'public.admin_list_product_reports(text,integer,timestamptz,uuid)'
  ) AS admin_list_rpc,
  to_regprocedure('public.admin_get_product_report(uuid)') AS admin_get_rpc,
  to_regprocedure(
    'public.admin_update_product_report(uuid,text,text)'
  ) AS admin_update_rpc;

SELECT count(*) AS trusted_admin_count
FROM auth.users
WHERE raw_app_meta_data ->> 'role' = 'admin';

SELECT EXISTS (
  SELECT 1
  FROM supabase_migrations.schema_migrations
  WHERE version = '20260626010000'
) AS documented_history_row_present;

ROLLBACK;
SQL
```

All independent body and historical-function definition markers must be true.
For each of the four historical admin functions and the audit write RPC, the
accepted pre-migration EXECUTE matrix is `PUBLIC=false`, `anon=true`,
`authenticated=true`, `service_role=true`, and `postgres=true`. The direct anon
grants are known drift corrected by this migration and are not a preflight stop
condition while the reviewed definitions and internal gates match. Abort if a
runtime admin function is absent, a definition/gate is invalid, no intended
admin is provisioned, paired product policies differ, or any policy outside the
six reviewed names exists. The documented history-row result is expected to be
false and is not a blocker when the runtime dependencies pass; do not repair it.

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
BEGIN TRANSACTION READ ONLY;

SELECT policyname, cmd, roles, permissive, qual, with_check
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
    'anon',
    'public.record_product_score_audit_snapshot(uuid,text,integer,text,text,text,text,text,jsonb)',
    'EXECUTE'
  ) AS anon_can_call_audit_write_rpc,
  has_function_privilege(
    'authenticated',
    'public.record_product_score_audit_snapshot(uuid,text,integer,text,text,text,text,text,jsonb)',
    'EXECUTE'
  ) AS auth_can_call_guarded_audit_rpc,
  has_function_privilege(
    'service_role',
    'public.record_product_score_audit_snapshot(uuid,text,integer,text,text,text,text,text,jsonb)',
    'EXECUTE'
  ) AS service_can_call_audit_write_rpc,
  has_function_privilege(
    'anon',
    'public.get_current_product_score_audit_snapshot(uuid,text,text,text,text,text)',
    'EXECUTE'
  ) AS anon_can_call_audit_read_rpc,
  has_function_privilege(
    'authenticated',
    'public.get_current_product_score_audit_snapshot(uuid,text,text,text,text,text)',
    'EXECUTE'
  ) AS auth_can_call_audit_read_rpc;

WITH functions(function_name, signature) AS (
  VALUES
    ('admin gate', 'public.is_freshscan_admin()'),
    ('admin get', 'public.admin_get_product_report(uuid)'),
    (
      'admin list',
      'public.admin_list_product_reports(text,integer,timestamptz,uuid)'
    ),
    (
      'admin update',
      'public.admin_update_product_report(uuid,text,text)'
    ),
    (
      'audit write',
      'public.record_product_score_audit_snapshot(uuid,text,integer,text,text,text,text,text,jsonb)'
    )
), roles(role_name) AS (
  VALUES ('PUBLIC'), ('anon'), ('authenticated'), ('service_role'), ('postgres')
)
SELECT
  function_name,
  role_name,
  CASE
    WHEN role_name = 'PUBLIC' THEN EXISTS (
      SELECT 1
      FROM aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) acl
      WHERE acl.grantee = 0 AND acl.privilege_type = 'EXECUTE'
    )
    ELSE has_function_privilege(role_name, p.oid, 'EXECUTE')
  END AS can_execute
FROM functions
JOIN pg_proc p ON p.oid = to_regprocedure(signature)
CROSS JOIN roles
ORDER BY function_name, role_name;

ROLLBACK;
SQL
```

The final products policy set must be exactly `anyone can select products`,
`admins can insert products`, and `admins can update products`. Public SELECT
values are true; anon writes and authenticated DELETE are false;
authenticated INSERT/UPDATE table privileges are true but restricted by the
admin-only RLS predicates; service-role INSERT/UPDATE are true. Direct audit
table privileges remain false. Audit write RPC execution must be
`anon=false`, `authenticated=true`, and `service_role=true`; audit read RPC
execution remains true for both anon and authenticated. For all five functions
in the ACL matrix, execution must be `PUBLIC=false`, `anon=false`,
`authenticated=true`, `service_role=true`, and `postgres=true`.

The historical function definitions must remain unchanged after migration:

- `is_freshscan_admin()` is `SECURITY INVOKER`, `STABLE`, has fixed
  `search_path = public, pg_temp`, and checks the trusted JWT
  `app_metadata.role = admin` claim with a non-null `auth.uid()`.
- The three admin report RPCs are `SECURITY DEFINER`, have the same fixed
  search path, and perform the admin gate before any privileged SELECT or
  UPDATE operation.

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
