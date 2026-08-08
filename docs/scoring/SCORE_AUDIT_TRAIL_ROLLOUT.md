# Score Audit Trail Production Rollout

Status: production migration and production backfill are not executed. This is
the controlled Phase 2B-11B operator package for project
`dzsmkmwatwvuxigynimq`.

## Safety Boundary

- Do not run `supabase db push`.
- Do not apply or repair any older pending migration.
- Apply only
  `supabase/migrations/20260808020000_add_product_score_audit_snapshots.sql`.
- Do not run backfill until the migration and every post-check below pass.
- Never put `SUPABASE_SERVICE_ROLE_KEY` in Flutter, source control, command-line
  arguments, screenshots, or logs.
- The migration does not change products or scoring mathematics. The backfill
  can only call the audit insert RPC with `controlled_backfill`.

The migration was 292 lines at preflight and is 303 lines after the reviewed
exact-current-input RPC defect fix. Its SHA-256 is:

```text
4d388d8c011c8d4e9be94b66f85694cf20fbf1287e0f1f849bf99fa6c47a37c8
```

Recompute this immediately before manual application:

```bash
sha256sum supabase/migrations/20260808020000_add_product_score_audit_snapshots.sql
```

## Reviewed Objects

The migration creates one table,
`public.product_score_audit_snapshots`, with a UUID primary key, restricted UUID
foreign key to `public.products(id)`, fingerprint/version/trigger/payload checks,
and a six-column idempotency unique constraint named
`product_score_audit_snapshots_current_input_key`.

It creates one explicit lookup index,
`product_score_audit_snapshots_product_created_idx`, one immutable-row trigger,
`product_score_audit_snapshots_immutable`, and three functions:

- `public.prevent_score_audit_snapshot_mutation()`
- `public.record_product_score_audit_snapshot(uuid,text,integer,text,text,text,text,text,jsonb)`
- `public.get_current_product_score_audit_snapshot(uuid,text,text,text,text,text)`

The primary key and unique constraint also create their backing indexes. RLS is
enabled with deliberately zero policies. Direct table privileges are revoked
from `PUBLIC`, `anon`, `authenticated`, and `service_role`; only `postgres` has
direct table privileges. The read RPC is executable by `anon`, `authenticated`,
`service_role`, and `postgres`. The write RPC is executable by `authenticated`,
`service_role`, and `postgres`, but its body admits only `auth.role() =
'service_role'` or `public.is_freshscan_admin()`.

All three functions use a fixed `search_path = public, pg_temp`. The trigger and
both RPCs are `SECURITY DEFINER`; the current-read RPC exposes only the snapshot
matching the supplied product, fingerprint, and version tuple, not history or
trigger/admin metadata. This avoids an append-only A-to-B-to-A reversion trap
where latest-by-time would return B even though the idempotent A row already
exists. The trigger rejects every `UPDATE` and `DELETE`, and the foreign key
uses `ON DELETE RESTRICT`.

## Remote Preflight Observed 2026-08-08

Read-only `supabase migration list --linked` and a linked `public` schema dump
showed:

- `20260808010000`: local and remote migration-history entries both present.
- `20260808020000`: local entry present; remote entry absent.
- The audit table, functions, trigger, explicit index, constraints, and policies
  do not exist remotely.
- `products.scoring_evidence`, `product_staging.scoring_evidence`, and
  `product_submissions.scoring_evidence` exist remotely as nullable `jsonb`.
- `public.products(id)` is a UUID primary key, and `products.updated_at` is
  `timestamptz`.
- `public.is_freshscan_admin()` exists and checks server-managed JWT
  `app_metadata.role = 'admin'`.

Migration application has no observed object-name collision. It assumes the
Supabase roles, `auth.role()`, `gen_random_uuid()`, `products`, and
`is_freshscan_admin()` remain present. It also requires a non-null
`products.updated_at` for each product that will be captured. The remote column
is nullable, so the null-row check below must return zero before backfill.

The remote schema currently also contains pre-existing broad `products` update
policies for `anon`/`authenticated`. They cannot forge an audit row because the
new table/RPC gates remain closed, and any product mutation makes an old audit
stale, but they are a separate catalogue-integrity/availability risk. Do not
silently change them as part of this migration rollout.

## Pre-Checks

Run this read-only SQL in Dashboard SQL Editor. Stop if `audit_table` or any
audit function is non-null, if a required evidence column is missing/not
`jsonb`, if `is_freshscan_admin` is missing, or if `null_updated_at_products` is
not zero.

```sql
select
  to_regclass('public.product_score_audit_snapshots') as audit_table,
  to_regprocedure('public.prevent_score_audit_snapshot_mutation()')
    as mutation_function,
  to_regprocedure(
    'public.record_product_score_audit_snapshot(uuid,text,integer,text,text,text,text,text,jsonb)'
  ) as write_rpc,
  to_regprocedure(
    'public.get_current_product_score_audit_snapshot(uuid,text,text,text,text,text)'
  ) as read_rpc,
  to_regprocedure('public.is_freshscan_admin()') as admin_gate;

select table_name, column_name, data_type, is_nullable
from information_schema.columns
where table_schema = 'public'
  and column_name = 'scoring_evidence'
  and table_name in ('products', 'product_staging', 'product_submissions')
order by table_name;

select count(*) as null_updated_at_products
from public.products
where updated_at is null;
```

## Exact Manual Application

1. Open Supabase Dashboard for project `dzsmkmwatwvuxigynimq` and select SQL
   Editor.
2. Run the pre-checks above and retain the result with the rollout record.
3. Open a new SQL Editor query and enter `BEGIN;`.
4. Paste the complete, unchanged contents of
   `supabase/migrations/20260808020000_add_product_score_audit_snapshots.sql`
   immediately after it.
5. Add `COMMIT;` after the final grant and run the single script.
6. If any statement fails, do not add compensating DDL. Ensure the transaction
   is rolled back, investigate, and rerun pre-checks.
7. Run every post-check below before considering migration-history repair or
   backfill.

The migration statements are correctly ordered and can be pasted as-is. The
explicit `BEGIN`/`COMMIT` wrapper is required for this manual procedure so a
partial object set cannot be committed by separate SQL Editor executions.

## Post-Migration Verification SQL

All queries below are read-only.

```sql
-- 1. Table and exact columns/types.
select to_regclass('public.product_score_audit_snapshots') as audit_table;

select
  a.attnum,
  a.attname as column_name,
  pg_catalog.format_type(a.atttypid, a.atttypmod) as data_type,
  a.attnotnull as not_null,
  pg_get_expr(d.adbin, d.adrelid) as default_expression
from pg_attribute a
join pg_class c on c.oid = a.attrelid
join pg_namespace n on n.oid = c.relnamespace
left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
where n.nspname = 'public'
  and c.relname = 'product_score_audit_snapshots'
  and a.attnum > 0
  and not a.attisdropped
order by a.attnum;

-- 2. Primary key, FK, checks, and six-column unique constraint.
select conname, contype, pg_get_constraintdef(oid) as definition
from pg_constraint
where conrelid = 'public.product_score_audit_snapshots'::regclass
order by contype, conname;

-- 3. Explicit and constraint-backed indexes.
select indexname, indexdef
from pg_indexes
where schemaname = 'public'
  and tablename = 'product_score_audit_snapshots'
order by indexname;

-- 4. RLS must be on and there must be zero policies.
select
  c.relrowsecurity as rls_enabled,
  c.relforcerowsecurity as force_rls,
  count(p.policyname) as policy_count
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
left join pg_policies p
  on p.schemaname = n.nspname and p.tablename = c.relname
where n.nspname = 'public'
  and c.relname = 'product_score_audit_snapshots'
group by c.relrowsecurity, c.relforcerowsecurity;

-- 5. Append-only trigger must be enabled for UPDATE OR DELETE.
select tgname, tgenabled, pg_get_triggerdef(oid) as definition
from pg_trigger
where tgrelid = 'public.product_score_audit_snapshots'::regclass
  and not tgisinternal;

-- 6. Function existence, owner, SECURITY DEFINER, volatility and search_path.
select
  p.oid::regprocedure as function_signature,
  pg_get_userbyid(p.proowner) as owner,
  p.prosecdef as security_definer,
  p.provolatile as volatility,
  p.proconfig as function_config
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'prevent_score_audit_snapshot_mutation',
    'record_product_score_audit_snapshot',
    'get_current_product_score_audit_snapshot'
  )
order by p.proname;

-- 7. No direct table operation may be available to mobile/service roles.
with roles(role_name) as (
  values ('anon'), ('authenticated'), ('service_role')
)
select
  role_name,
  has_table_privilege(role_name, 'public.product_score_audit_snapshots', 'SELECT')
    as can_select,
  has_table_privilege(role_name, 'public.product_score_audit_snapshots', 'INSERT')
    as can_insert,
  has_table_privilege(role_name, 'public.product_score_audit_snapshots', 'UPDATE')
    as can_update,
  has_table_privilege(role_name, 'public.product_score_audit_snapshots', 'DELETE')
    as can_delete
from roles;

-- 8. Exact RPC execute matrix.
with roles(role_name) as (
  values ('anon'), ('authenticated'), ('service_role'), ('postgres')
)
select
  role_name,
  has_function_privilege(
    role_name,
    'public.record_product_score_audit_snapshot(uuid,text,integer,text,text,text,text,text,jsonb)',
    'EXECUTE'
  ) as can_execute_write_rpc,
  has_function_privilege(
    role_name,
    'public.get_current_product_score_audit_snapshot(uuid,text,text,text,text,text)',
    'EXECUTE'
  ) as can_execute_read_rpc
from roles;

-- 9. Static, non-destructive verification of the trusted write gate and
-- immutable-row exception. Both booleans must be true.
select
  position(
    'auth.role()' in pg_get_functiondef(
      'public.record_product_score_audit_snapshot(uuid,text,integer,text,text,text,text,text,jsonb)'::regprocedure
    )
  ) > 0 as checks_service_role,
  position(
    'is_freshscan_admin()' in pg_get_functiondef(
      'public.record_product_score_audit_snapshot(uuid,text,integer,text,text,text,text,text,jsonb)'::regprocedure
    )
  ) > 0 as checks_admin_gate,
  position(
    'score_audit_snapshot_immutable' in pg_get_functiondef(
      'public.prevent_score_audit_snapshot_mutation()'::regprocedure
    )
  ) > 0 as rejects_mutation;
```

Expected permission results are all `false` in query 7. In query 8, write is
`false/true/true/true` and read is `true/true/true/true` for
`anon/authenticated/service_role/postgres`. Authenticated write-RPC visibility
is intentional; non-admin calls are rejected inside the definer function.
These checks prove the static privilege/gate configuration without attempting
a destructive insert, update, or delete in production.

## Backfill Dry Run

The executable tool is `tool/score_audit_backfill.dart`. It uses the same
matcher, canonical risk service, readiness evaluators, transforms, calculator,
snapshot builder, validator, fingerprint, and public audit gate as the app. It
never calculates an alternate score.

Supply credentials only in the trusted operator process. Prefer an interactive
hidden prompt so the key does not enter shell history:

```bash
export SUPABASE_URL='https://dzsmkmwatwvuxigynimq.supabase.co'
read -rsp 'Service role key: ' SUPABASE_SERVICE_ROLE_KEY
export SUPABASE_SERVICE_ROLE_KEY
dart run tool/score_audit_backfill.dart \
  --project-ref dzsmkmwatwvuxigynimq \
  --dry-run \
  --batch-size 100 \
  --max-products 100
unset SUPABASE_SERVICE_ROLE_KEY
```

Dry-run performs no insert call. It reports total examined, nutrition/additive/
final readiness, matching/missing/stale/invalid audits, would-insert,
not-scorable, existing-key records requiring manual review, top blocker reasons,
errors, last cursor, and safe resume cursor. An invalid/stale row already using
the exact unique key is never presented as insertable because the append-only
constraint would resolve it to the same row; it is reported as an error for
manual review instead.

After separate approval, the operator can replace `--dry-run` with both
`--apply --confirm-write-audit-snapshots`. Apply mode writes only through
`record_product_score_audit_snapshot` with trigger source
`controlled_backfill`; it never updates a product or scoring evidence. Do not
run apply mode as part of this preparation phase.

Each product is isolated. A failed item is reported by product ID while later
items in the batch continue. `safe_resume_cursor` remains before the first
failure, so retrying from it revisits failed and later rows. Matching rows are
skipped, and the database unique constraint resolves concurrent/repeated writes
as duplicates. A page/catalogue load failure halts without advancing the safe
cursor.

## Read-Only Sample Validation

After a future approved backfill, inspect a small, non-sensitive product-ID
sample:

```bash
dart run tool/score_audit_backfill.dart \
  --project-ref dzsmkmwatwvuxigynimq \
  --sample-product-ids UUID_1,UUID_2,UUID_3
```

The command reports only product ID/barcode, current calculated score, snapshot
score, fingerprint match, version tuple, validator status, and public gate
status. It never prints ingredients, raw snapshot JSON, user data, or secrets.

## Public Score Rollout Behavior

Before backfill, a product with no matching trusted snapshot shows the neutral
score-unavailable state. Missing, stale, malformed, unsupported-version, or
otherwise invalid snapshots remain unavailable. Only a valid matching current
snapshot makes the numeric score visible. Backfill does not weaken this gate;
it makes qualifying products visible only by appending matching evidence.

## Rollback Limitations

An error inside the explicit deployment transaction can be rolled back without
leaving partial objects. After commit, there is no routine destructive rollback.
The table is legal/audit evidence, rows are append-only, and the product foreign
key restricts deletion. Dropping the table/functions after any capture would
destroy evidence and requires separate legal, retention, backup, and incident
review. Do not disable the trigger or delete rows to undo rollout.

## Migration History After Verified Success

Only after manual application and every post-check succeeds, run exactly:

```bash
supabase migration repair 20260808020000 --status applied --linked
```

Do not run this command during preparation. Do not include any older version in
the repair command. Finally rerun `supabase migration list --linked` and verify
only `20260808020000` changed to local/remote present.
