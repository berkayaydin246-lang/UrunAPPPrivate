import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/additive_quality_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_score_audit_snapshot.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_score_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/nutrition_quality_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/nutrition_raw_score_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_evidence_snapshot.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/etiketly_score_calculator.dart';

void main() {
  test('release freeze pins the complete Etiketly Score v2 contract', () {
    expect(etiketlyScoreVersion, 'etiketly_score_v2');
    expect(nutritionRawMethodologyVersion, 'updated_nutrition_profile_2023_v1');
    expect(nutritionQualityTransformVersion, 'nutrition_quality_transform_v2');
    expect(additiveQualityTransformVersion, 'additive_quality_transform_v1');
    expect(ScoringEvidenceSnapshot.currentSchemaVersion, 1);
    expect(EtiketlyScoreAuditSnapshot.currentSchemaVersion, 1);
    expect(EtiketlyScoreCalculator.nutritionWeight, 0.80);
    expect(EtiketlyScoreCalculator.additiveWeight, 0.20);
  });

  test('production RPC accepts exactly the frozen v2 version tuple', () {
    final migration = File(
      'supabase/migrations/20260814000000_enable_score_v2_audit_snapshots.sql',
    ).readAsStringSync();

    expect(migration, contains("'etiketly_score_v2'"));
    expect(migration, contains("'updated_nutrition_profile_2023_v1'"));
    expect(migration, contains("'nutrition_quality_transform_v2'"));
    expect(migration, contains("'additive_quality_transform_v1'"));
    expect(migration, contains('p_snapshot_schema_version IS DISTINCT FROM 1'));
    expect(migration, contains('0.80 * v_nutrition_quality'));
    expect(migration, contains('0.20 * v_additive_quality'));
  });

  test('every scoring-relevant product write path uses trusted lifecycle', () {
    final sources = <String, String>{
      'staging approval': File(
        'lib/features/admin/repositories/product_staging_approval_repository.dart',
      ).readAsStringSync(),
      'submission approval': File(
        'lib/features/admin/repositories/product_submission_approval_repository.dart',
      ).readAsStringSync(),
      'legacy draft': File(
        'lib/features/admin/repositories/product_draft_repository.dart',
      ).readAsStringSync(),
      'OFF enrichment': File(
        'lib/features/imports/repositories/open_food_facts_repository.dart',
      ).readAsStringSync(),
    };
    for (final entry in sources.entries) {
      expect(
        entry.value,
        contains('_scoringLifecycle.processCurrent'),
        reason: entry.key,
      );
    }

    final pythonPaths = [
      'scripts/product_import/web_scraper/runner.py',
      'scripts/import_openfoodfacts_turkey.py',
      'scripts/import_tools/upload_products.py',
      'scripts/import_tools/safe_importer.py',
      'scripts/backfill_search_keywords.py',
    ];
    for (final path in pythonPaths) {
      final source = File(path).readAsStringSync();
      expect(source, contains('run_product_scoring_lifecycle'), reason: path);
    }

    for (final path in [
      'scripts/import_tools/upload_products.py',
      'scripts/import_tools/safe_importer.py',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, contains('SUPABASE_SERVICE_ROLE_KEY'), reason: path);
      expect(source, isNot(contains("os.getenv('SUPABASE_ANON_KEY')")));
    }

    final offRepository = sources['OFF enrichment']!;
    expect(offRepository, contains("rpc('is_freshscan_admin')"));
    expect(
      RegExp(
        r'if \(!await _canManageCatalogue\(\)\)',
      ).allMatches(offRepository),
      hasLength(2),
    );
  });

  test('release RLS closes anonymous and non-admin catalogue write bypass', () {
    final migration = File(
      'supabase/migrations/20260814010000_restrict_product_catalogue_writes.sql',
    ).readAsStringSync();

    for (final policy in [
      'Allow products insert',
      'Allow products select',
      'Allow products update',
    ]) {
      final drop = 'DROP POLICY IF EXISTS "$policy"';
      expect(migration, contains(drop));
      expect(
        migration.indexOf(drop),
        lessThan(migration.indexOf('DO \$\$')),
        reason: '$policy must be removed before the fail-closed guard',
      );
    }
    expect(
      migration,
      contains(
        'DROP POLICY IF EXISTS "dev: authenticated can insert products"',
      ),
    );
    expect(
      migration,
      contains(
        'DROP POLICY IF EXISTS "dev: authenticated can update products"',
      ),
    );
    expect(
      migration,
      isNot(contains('DROP POLICY IF EXISTS "anyone can select products"')),
      reason: 'the canonical public catalogue read policy must be preserved',
    );
    expect(
      migration,
      contains(
        'REVOKE INSERT, UPDATE, DELETE ON TABLE public.products FROM anon;',
      ),
    );
    expect(
      migration,
      contains(
        'REVOKE INSERT, UPDATE, DELETE ON TABLE public.products FROM PUBLIC;',
      ),
    );
    expect(
      migration,
      contains(
        'GRANT INSERT, UPDATE ON TABLE public.products TO service_role;',
      ),
    );
    expect(
      migration,
      contains("RAISE EXCEPTION 'unexpected_products_write_policy'"),
    );
    expect(migration, contains("cmd IN ('ALL', 'INSERT', 'UPDATE', 'DELETE')"));
    expect(
      migration,
      contains(
        'GRANT INSERT, UPDATE ON TABLE public.products TO authenticated;',
      ),
    );
    expect(migration, contains('WITH CHECK (public.is_freshscan_admin())'));
    expect(migration, contains('USING (public.is_freshscan_admin())'));
    expect(
      RegExp(r'FOR (INSERT|UPDATE)\s+TO authenticated').allMatches(migration),
      hasLength(2),
    );
    expect(
      migration,
      isNot(contains('GRANT INSERT, UPDATE ON TABLE public.products TO anon')),
    );
    expect(migration, contains('BEGIN;'));
    expect(migration, contains('COMMIT;'));
  });

  test('release RLS enforces the guarded audit RPC execute matrix', () {
    final migration = File(
      'supabase/migrations/20260814010000_restrict_product_catalogue_writes.sql',
    ).readAsStringSync();
    const signature =
        'public.record_product_score_audit_snapshot(\n'
        '  UUID, TEXT, INTEGER, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB\n'
        ')';

    expect(
      migration,
      contains('REVOKE EXECUTE ON FUNCTION $signature FROM PUBLIC;'),
    );
    expect(
      migration,
      contains('REVOKE EXECUTE ON FUNCTION $signature FROM anon;'),
    );
    expect(
      migration,
      contains(
        'GRANT EXECUTE ON FUNCTION $signature '
        'TO authenticated, service_role, postgres;',
      ),
    );
    expect(
      migration,
      isNot(contains('CREATE OR REPLACE FUNCTION')),
      reason: 'the access-control migration must not rewrite scoring logic',
    );
    expect(
      migration,
      isNot(contains('get_current_product_score_audit_snapshot')),
      reason: 'the public current-audit read RPC must remain unchanged',
    );
  });

  test('release RLS repairs historical admin RPC execute ACL drift', () {
    final migration = File(
      'supabase/migrations/20260814010000_restrict_product_catalogue_writes.sql',
    ).readAsStringSync();
    const functions = <String>[
      'public.is_freshscan_admin()',
      'public.admin_get_product_report(UUID)',
      'public.admin_list_product_reports(\n'
          '  TEXT, INTEGER, TIMESTAMPTZ, UUID\n'
          ')',
      'public.admin_update_product_report(\n  UUID, TEXT, TEXT\n)',
    ];

    for (final function in functions) {
      final escapedFunction = RegExp.escape(function);
      expect(
        migration,
        matches(RegExp('REVOKE ALL ON FUNCTION $escapedFunction FROM PUBLIC;')),
        reason: function,
      );
      expect(
        migration,
        matches(
          RegExp('REVOKE EXECUTE ON FUNCTION $escapedFunction FROM anon;'),
        ),
        reason: function,
      );
      expect(
        migration,
        matches(
          RegExp(
            'GRANT EXECUTE ON FUNCTION $escapedFunction\\s+'
            'TO authenticated, service_role, postgres;',
          ),
        ),
        reason: function,
      );
    }

    expect(
      migration,
      isNot(contains('CREATE OR REPLACE FUNCTION')),
      reason: 'ACL repair must not replace historical or scoring RPC bodies',
    );
    expect(
      migration,
      isNot(contains('get_current_product_score_audit_snapshot')),
      reason: 'audit read RPC must remain unchanged',
    );
  });

  test('RLS rollout preflight documents runtime and ACL invariants', () {
    final rollout = File(
      'docs/scoring/PRODUCT_CATALOGUE_RLS_ROLLOUT.md',
    ).readAsStringSync();

    for (final marker in [
      'auth.role()',
      'service_role',
      'is_freshscan_admin()',
      'not_authorized',
      '42501',
      'snapshot_product_version_stale',
      'snapshot_score_reconciliation_failed',
      'etiketly_score_v2',
      'nutrition_quality_transform_v2',
      'additive_quality_transform_v1',
    ]) {
      expect(rollout, contains(marker), reason: marker);
    }
    expect(rollout, contains('anon=false'));
    expect(rollout, contains('authenticated=true'));
    expect(rollout, contains('service_role=true'));
    expect(rollout, contains('PUBLIC=false'));
    expect(rollout, contains('anon=true'));
    expect(rollout, contains('Post-migration ACL state required'));
    expect(rollout, contains('SECURITY INVOKER'));
    expect(rollout, contains('SECURITY DEFINER'));
    expect(rollout, contains('20260626010000'));
    expect(rollout, contains('supabase migration repair'));
    expect(rollout, contains('manual insert'));
  });
}
