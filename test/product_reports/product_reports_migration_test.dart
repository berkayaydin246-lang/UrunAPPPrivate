import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('product_reports migration', () {
    late String sql;

    setUpAll(() async {
      sql = await File(
        'supabase/migrations/20260626000000_add_product_reports.sql',
      ).readAsString();
    });

    test('creates the expected table shape and constraints', () {
      expect(
        sql,
        contains('CREATE TABLE IF NOT EXISTS public.product_reports'),
      );
      expect(sql, contains('product_name_snapshot TEXT NOT NULL'));
      expect(sql, contains('product_brand_snapshot TEXT'));
      expect(sql, contains('product_image_snapshot TEXT'));
      expect(sql, contains('client_install_id UUID NOT NULL'));
      expect(sql, contains('client_submission_id UUID NOT NULL UNIQUE'));
      expect(sql, contains("CONSTRAINT product_reports_details_length_check"));
      expect(sql, contains("CONSTRAINT product_reports_evidence_count_check"));
      expect(sql, contains("cardinality(evidence_image_urls) <= 3"));
    });

    test('adds the expected indexes and secures the table with RLS', () {
      expect(
        sql,
        contains(
          'CREATE INDEX IF NOT EXISTS product_reports_status_created_idx',
        ),
      );
      expect(
        sql,
        contains('CREATE INDEX IF NOT EXISTS product_reports_product_idx'),
      );
      expect(
        sql,
        contains(
          'CREATE INDEX IF NOT EXISTS product_reports_install_created_idx',
        ),
      );
      expect(sql, contains('ALTER TABLE public.product_reports'));
      expect(sql, contains('ENABLE ROW LEVEL SECURITY;'));
    });

    test('uses a security definer RPC with idempotency and rate limiting', () {
      expect(
        sql,
        contains('CREATE OR REPLACE FUNCTION public.submit_product_report('),
      );
      expect(sql, contains('SECURITY DEFINER'));
      expect(sql, contains('SET search_path = public'));
      expect(
        sql,
        contains('WHERE client_submission_id = p_client_submission_id;'),
      );
      expect(sql, contains('duplicate_recent_report'));
      expect(sql, contains('report_rate_limited'));
      expect(sql, contains("INTERVAL '24 hours'"));
      expect(sql, contains('v_product.name'));
      expect(sql, contains('v_product.brand'));
      expect(sql, contains('v_product.image_url'));
    });

    test(
      'keeps direct table policies service-role-only and exposes only RPC execution',
      () {
        final policyStatements = RegExp(
          r'CREATE POLICY[\s\S]*?;',
          caseSensitive: false,
        ).allMatches(sql).map((match) => match.group(0)!).toList();

        expect(policyStatements, hasLength(1));
        expect(policyStatements.single, contains('ON public.product_reports'));
        expect(policyStatements.single, contains('TO service_role'));
        expect(policyStatements.single, isNot(contains('TO anon')));
        expect(policyStatements.single, isNot(contains('TO authenticated')));

        expect(
          sql,
          contains(
            'REVOKE ALL ON FUNCTION public.submit_product_report(UUID, TEXT, TEXT, UUID, UUID, TEXT[]) FROM PUBLIC;',
          ),
        );
        expect(
          sql,
          contains(
            'GRANT EXECUTE ON FUNCTION public.submit_product_report(UUID, TEXT, TEXT, UUID, UUID, TEXT[]) TO anon;',
          ),
        );
        expect(
          sql,
          contains(
            'GRANT EXECUTE ON FUNCTION public.submit_product_report(UUID, TEXT, TEXT, UUID, UUID, TEXT[]) TO authenticated;',
          ),
        );
        expect(
          sql,
          contains(
            'GRANT EXECUTE ON FUNCTION public.submit_product_report(UUID, TEXT, TEXT, UUID, UUID, TEXT[]) TO service_role;',
          ),
        );
      },
    );
  });
}
