import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('admin_product_reports_rpcs migration', () {
    late String sql;

    setUpAll(() async {
      sql = await File(
        'supabase/migrations/20260626010000_admin_product_reports_rpcs.sql',
      ).readAsString();
    });

    // ── 1. Admin authorization uses trusted app_metadata ──────────────────

    test('is_freshscan_admin uses trusted app_metadata claim', () {
      expect(sql, contains("auth.jwt() -> 'app_metadata' ->> 'role'"));
      expect(sql, contains("= 'admin'"));
    });

    test('is_freshscan_admin does NOT use user_metadata', () {
      expect(sql, isNot(contains('user_metadata')));
    });

    test('is_freshscan_admin checks auth.uid() is not null', () {
      expect(sql, contains('auth.uid() IS NOT NULL'));
    });

    // ── 2. All admin RPCs check authorization ─────────────────────────────

    test('admin_list_product_reports calls is_freshscan_admin', () {
      final listFn = _extractFunction(sql, 'admin_list_product_reports');
      expect(listFn, contains('is_freshscan_admin()'));
      expect(listFn, contains('not_authorized'));
    });

    test('admin_get_product_report calls is_freshscan_admin', () {
      final getFn = _extractFunction(sql, 'admin_get_product_report');
      expect(getFn, contains('is_freshscan_admin()'));
      expect(getFn, contains('not_authorized'));
    });

    test('admin_update_product_report calls is_freshscan_admin', () {
      final updateFn = _extractFunction(sql, 'admin_update_product_report');
      expect(updateFn, contains('is_freshscan_admin()'));
      expect(updateFn, contains('not_authorized'));
    });

    // ── 3. Admin RPCs not granted to anon ─────────────────────────────────

    test('admin RPCs are not granted to anon', () {
      // Find all GRANT EXECUTE statements for admin RPCs
      final grantLines = sql
          .split('\n')
          .where(
            (l) =>
                l.contains('GRANT EXECUTE') &&
                (l.contains('admin_list_product_reports') ||
                    l.contains('admin_get_product_report') ||
                    l.contains('admin_update_product_report')),
          )
          .join('\n');

      expect(
        grantLines,
        isNotEmpty,
        reason: 'Expected GRANT statements for admin RPCs',
      );
      expect(grantLines, isNot(contains('anon')));
    });

    // ── 4. Admin RPCs not granted to PUBLIC ───────────────────────────────

    test('all admin functions have REVOKE ALL FROM PUBLIC', () {
      expect(
        sql,
        contains(
          'REVOKE ALL ON FUNCTION public.is_freshscan_admin() FROM PUBLIC;',
        ),
      );
      expect(
        sql,
        contains(
          'REVOKE ALL ON FUNCTION public.admin_list_product_reports'
          '(TEXT, INTEGER, TIMESTAMPTZ, UUID)',
        ),
      );
      expect(
        sql,
        contains(
          'REVOKE ALL ON FUNCTION public.admin_get_product_report(UUID)'
          ' FROM PUBLIC;',
        ),
      );
      expect(
        sql,
        contains(
          'REVOKE ALL ON FUNCTION public.admin_update_product_report(UUID, TEXT, TEXT)'
          ' FROM PUBLIC;',
        ),
      );
    });

    // ── 5. Direct authenticated table access remains absent ───────────────

    test('migration adds no direct authenticated RLS policies', () {
      final policies = RegExp(
        r'CREATE POLICY[\s\S]*?;',
        caseSensitive: false,
      ).allMatches(sql).map((m) => m.group(0)!).toList();

      // This migration should add zero CREATE POLICY statements
      // (policies are in the prior migration)
      expect(
        policies,
        isEmpty,
        reason: 'Admin RPC migration must not add table policies',
      );
    });

    // ── 6. Admin RPCs use SECURITY DEFINER ────────────────────────────────

    test('admin_list_product_reports uses SECURITY DEFINER', () {
      final fn = _extractFunction(sql, 'admin_list_product_reports');
      expect(fn.toUpperCase(), contains('SECURITY DEFINER'));
    });

    test('admin_get_product_report uses SECURITY DEFINER', () {
      final fn = _extractFunction(sql, 'admin_get_product_report');
      expect(fn.toUpperCase(), contains('SECURITY DEFINER'));
    });

    test('admin_update_product_report uses SECURITY DEFINER', () {
      final fn = _extractFunction(sql, 'admin_update_product_report');
      expect(fn.toUpperCase(), contains('SECURITY DEFINER'));
    });

    // ── 7. Admin RPCs use a fixed safe search_path ────────────────────────

    test('is_freshscan_admin uses safe search_path', () {
      final fn = _extractFunction(sql, 'is_freshscan_admin');
      expect(fn, contains('SET search_path = public, pg_temp'));
    });

    test('admin_list_product_reports uses safe search_path', () {
      final fn = _extractFunction(sql, 'admin_list_product_reports');
      expect(fn, contains('SET search_path = public, pg_temp'));
    });

    test('admin_get_product_report uses safe search_path', () {
      final fn = _extractFunction(sql, 'admin_get_product_report');
      expect(fn, contains('SET search_path = public, pg_temp'));
    });

    test('admin_update_product_report uses safe search_path', () {
      final fn = _extractFunction(sql, 'admin_update_product_report');
      expect(fn, contains('SET search_path = public, pg_temp'));
    });

    // ── 8. List limit is capped at 100 ────────────────────────────────────

    test('admin_list_product_reports clamps limit to maximum 100', () {
      final fn = _extractFunction(sql, 'admin_list_product_reports');
      expect(fn, contains('LEAST(100,'));
    });

    test('admin_list_product_reports clamps limit to minimum 1', () {
      final fn = _extractFunction(sql, 'admin_list_product_reports');
      expect(fn, contains('GREATEST(1,'));
    });

    // ── 9. Pagination orders by created_at and id ─────────────────────────

    test(
      'admin_list_product_reports orders by created_at DESC then id DESC',
      () {
        final fn = _extractFunction(sql, 'admin_list_product_reports');
        expect(fn, contains('created_at DESC'));
        expect(fn, contains('id DESC'));
        // Cursor condition uses both fields
        expect(fn, contains('p_before_created_at'));
        expect(fn, contains('p_before_id'));
      },
    );

    // ── 10. Status values are validated ───────────────────────────────────

    test('admin_list_product_reports validates status input', () {
      final fn = _extractFunction(sql, 'admin_list_product_reports');
      expect(fn, contains('invalid_status'));
      expect(fn, contains("'pending'"));
      expect(fn, contains("'reviewing'"));
      expect(fn, contains("'resolved'"));
      expect(fn, contains("'rejected'"));
    });

    test('admin_update_product_report validates status input', () {
      final fn = _extractFunction(sql, 'admin_update_product_report');
      expect(fn, contains('invalid_status'));
    });

    // ── 11. Reviewer recorded with auth.uid() ─────────────────────────────

    test('admin_update_product_report records reviewer with auth.uid()', () {
      final fn = _extractFunction(sql, 'admin_update_product_report');
      expect(fn, contains('auth.uid()'));
      expect(fn, contains('reviewed_by'));
      expect(fn, contains('reviewed_at'));
    });

    // ── 12. Non-admin calls fail closed ───────────────────────────────────

    test('admin_list_product_reports raises not_authorized for non-admins', () {
      final fn = _extractFunction(sql, 'admin_list_product_reports');
      expect(fn, contains("'not_authorized'"));
    });

    test('admin_get_product_report raises not_authorized for non-admins', () {
      final fn = _extractFunction(sql, 'admin_get_product_report');
      expect(fn, contains("'not_authorized'"));
    });

    test(
      'admin_update_product_report raises not_authorized for non-admins',
      () {
        final fn = _extractFunction(sql, 'admin_update_product_report');
        expect(fn, contains("'not_authorized'"));
      },
    );

    // ── 13. Invalid status transitions rejected ────────────────────────────

    test(
      'admin_update_product_report validates transition and raises error',
      () {
        final fn = _extractFunction(sql, 'admin_update_product_report');
        expect(fn, contains('invalid_status_transition'));
      },
    );

    // ── 14. Consumer submit_product_report permissions intact ──────────────
    // (verified by inspecting prior migration — this migration adds no REVOKE
    // against submit_product_report)

    test('this migration does not revoke submit_product_report grants', () {
      expect(sql, isNot(contains('submit_product_report')));
    });

    // ── 15. Admin RPCs report_not_found safety ────────────────────────────

    test('admin_get_product_report raises report_not_found for unknown id', () {
      final fn = _extractFunction(sql, 'admin_get_product_report');
      expect(fn, contains('report_not_found'));
    });

    test(
      'admin_update_product_report raises report_not_found for unknown id',
      () {
        final fn = _extractFunction(sql, 'admin_update_product_report');
        expect(fn, contains('report_not_found'));
      },
    );
  });
}

/// Extracts the SQL body of the first function whose CREATE OR REPLACE
/// FUNCTION declaration matches [functionName].
String _extractFunction(String sql, String functionName) {
  final pattern = RegExp(
    'CREATE OR REPLACE FUNCTION public\\.$functionName'
    r'[\s\S]*?\$\$;',
    caseSensitive: false,
  );
  final match = pattern.firstMatch(sql);
  expect(
    match,
    isNotNull,
    reason: 'Could not find function $functionName in SQL',
  );
  return match!.group(0)!;
}
