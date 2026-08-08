import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String sql;

  setUpAll(() {
    sql = File(
      'supabase/migrations/20260808020000_add_product_score_audit_snapshots.sql',
    ).readAsStringSync().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  });

  test('audit table is append-only and historical rows are retained', () {
    expect(sql, contains('create table public.product_score_audit_snapshots'));
    expect(sql, contains('on delete restrict'));
    expect(sql, contains('before update or delete'));
    expect(sql, contains('score_audit_snapshot_immutable'));
    expect(sql, isNot(contains('on delete cascade')));
  });

  test('mobile roles have no direct table access or write policy', () {
    expect(
      sql,
      contains(
        'revoke all on table public.product_score_audit_snapshots from authenticated',
      ),
    );
    expect(sql, isNot(contains('create policy')));
    expect(
      sql,
      isNot(
        contains(
          'grant insert on table public.product_score_audit_snapshots to authenticated',
        ),
      ),
    );
    expect(
      sql,
      contains(
        'revoke all on table public.product_score_audit_snapshots from service_role',
      ),
    );
  });

  test('trusted RPC checks admin or service role before inserting', () {
    expect(sql, contains('record_product_score_audit_snapshot'));
    expect(sql, contains("coalesce(auth.role(), '') <> 'service_role'"));
    expect(sql, contains('not public.is_freshscan_admin()'));
    expect(sql, contains('snapshot_score_reconciliation_failed'));
    expect(sql, contains('on conflict on constraint'));
  });

  test('public RPC exposes only the current product snapshot', () {
    expect(sql, contains('get_current_product_score_audit_snapshot'));
    expect(sql, contains('order by created_at desc, id desc limit 1'));
    expect(
      sql,
      contains(
        'grant execute on function public.get_current_product_score_audit_snapshot(uuid) to anon, authenticated',
      ),
    );
  });
}
