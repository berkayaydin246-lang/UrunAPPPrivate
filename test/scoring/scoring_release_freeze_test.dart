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
    expect(migration, contains('WITH CHECK (public.is_freshscan_admin())'));
    expect(
      migration,
      isNot(contains('GRANT INSERT, UPDATE ON TABLE public.products TO anon')),
    );
    expect(migration, contains('BEGIN;'));
    expect(migration, contains('COMMIT;'));
  });
}
