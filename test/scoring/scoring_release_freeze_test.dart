import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/additive_quality_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_score_audit_snapshot.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_score_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/nutrition_quality_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/nutrition_raw_score_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_evidence_snapshot.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/etiketly_score_calculator.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/nutrition_quality_transformer.dart';
import 'package:food_analyzer_app/features/scoring/presentation/etiketly_score_presentation.dart';

void main() {
  test(
    'release freeze pins the complete Etiketly Score CURRENT (v3) contract',
    () {
      // CURRENT as of the V3 cutover.
      expect(etiketlyScoreVersion, 'etiketly_score_v2');
      expect(
        nutritionRawMethodologyVersion,
        'updated_nutrition_profile_2023_v1',
      );
      expect(
        nutritionQualityTransformVersion,
        'nutrition_quality_transform_v3',
        reason: 'production default was cut over from v2 to v3 after full '
            'shadow backfill coverage (4330/4330) was verified',
      );
      expect(additiveQualityTransformVersion, 'additive_quality_transform_v1');
      expect(ScoringEvidenceSnapshot.currentSchemaVersion, 1);
      expect(EtiketlyScoreAuditSnapshot.currentSchemaVersion, 1);
      // Unchanged by the cutover: weighting.
      expect(EtiketlyScoreCalculator.nutritionWeight, 0.80);
      expect(EtiketlyScoreCalculator.additiveWeight, 0.20);
      // Unchanged by the cutover: score bands (thresholds and labels).
      const presentation = EtiketlyScorePresentationMapper();
      expect(presentation.bandForDisplayScore(85), EtiketlyScoreBand.veryGood);
      expect(presentation.bandForDisplayScore(84), EtiketlyScoreBand.good);
      expect(presentation.bandForDisplayScore(70), EtiketlyScoreBand.good);
      expect(presentation.bandForDisplayScore(69), EtiketlyScoreBand.medium);
      expect(presentation.bandForDisplayScore(50), EtiketlyScoreBand.medium);
      expect(presentation.bandForDisplayScore(49), EtiketlyScoreBand.weak);
      expect(presentation.bandForDisplayScore(30), EtiketlyScoreBand.weak);
      expect(presentation.bandForDisplayScore(29), EtiketlyScoreBand.veryWeak);
      expect(presentation.labelForBand(EtiketlyScoreBand.veryGood), 'Çok iyi');
      expect(presentation.labelForBand(EtiketlyScoreBand.good), 'İyi');
      expect(presentation.labelForBand(EtiketlyScoreBand.medium), 'Orta');
      expect(presentation.labelForBand(EtiketlyScoreBand.weak), 'Zayıf');
      expect(presentation.labelForBand(EtiketlyScoreBand.veryWeak), 'Çok zayıf');
    },
  );

  test(
    'historical V2 remains frozen and fully reconstructable via '
    'NutritionQualityTransformer.v2() — never deleted, never mutated',
    () {
      expect(nutritionQualityTransformV2Version, 'nutrition_quality_transform_v2');
      const v2 = NutritionQualityTransformer.v2();
      expect(v2.transformVersion, 'nutrition_quality_transform_v2');
      // Original V2 generalFood/beverage anchors, spot-checked exactly.
      expect(v2.qualityForRawScore(0.5, ScoringCategory.generalFood), 94);
      expect(v2.qualityForRawScore(2.5, ScoringCategory.generalFood), 86);
      expect(v2.qualityForRawScore(10.5, ScoringCategory.generalFood), 72);
      expect(v2.qualityForRawScore(2.5, ScoringCategory.beverage), 88);
      expect(v2.qualityForRawScore(6.5, ScoringCategory.beverage), 75);

      // The production-current default is NOW v3, not v2 — confirms the
      // cutover actually happened, not merely that v2 still exists.
      const current = NutritionQualityTransformer();
      expect(current.transformVersion, 'nutrition_quality_transform_v3');
      expect(
        current.qualityForRawScore(2.5, ScoringCategory.generalFood),
        isNot(v2.qualityForRawScore(2.5, ScoringCategory.generalFood)),
      );
    },
  );

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

  group('V3 (approved Candidate A) release freeze — additive to V2, never a mutation', () {
    const v2 = NutritionQualityTransformer.v2();
    const v3 = NutritionQualityTransformer.v3();

    test(
      'V3 is now the production-current default — cut over from V2 after '
      'full shadow backfill coverage (4330/4330) was verified',
      () {
        expect(
          nutritionQualityTransformV3Version,
          'nutrition_quality_transform_v3',
        );
        expect(
          nutritionQualityTransformVersion,
          nutritionQualityTransformV3Version,
          reason: 'production default was cut over from v2 to v3',
        );
        // The bare (unnamed) constructor IS the production-current one —
        // it now behaves identically to the explicit .v3() constructor.
        const bareDefault = NutritionQualityTransformer();
        expect(bareDefault.transformVersion, v3.transformVersion);
        expect(
          bareDefault.qualityForRawScore(5, ScoringCategory.generalFood),
          v3.qualityForRawScore(5, ScoringCategory.generalFood),
        );
      },
    );

    test('unchanged: raw nutrition methodology, additive transform, 80/20 weights', () {
      // Re-asserted here (not just in the V2 test above) so this group
      // stands alone as documentation of exactly what V3 did NOT change.
      expect(nutritionRawMethodologyVersion, 'updated_nutrition_profile_2023_v1');
      expect(additiveQualityTransformVersion, 'additive_quality_transform_v1');
      expect(EtiketlyScoreCalculator.nutritionWeight, 0.80);
      expect(EtiketlyScoreCalculator.additiveWeight, 0.20);
    });

    test('V3 approved Candidate A generalFood anchors, exact', () {
      const anchors = <(double, double)>[
        (-5.5, 100),
        (0.5, 92),
        (2.5, 78),
        (6.5, 74),
        (10.5, 72),
        (18.5, 66),
        (26.5, 42),
        (34.5, 18),
        (42.5, 0),
      ];
      for (final (raw, quality) in anchors) {
        expect(
          v3.qualityForRawScore(raw, ScoringCategory.generalFood),
          quality,
          reason: 'generalFood v3 anchor raw=$raw',
        );
      }
    });

    test('V3 approved Candidate A beverage anchors, exact', () {
      const anchors = <(double, double)>[
        (-3.5, 95),
        (2.5, 84),
        (4.5, 76),
        (6.5, 70),
        (9.5, 60),
        (13.5, 40),
        (17.5, 20),
        (21.5, 0),
      ];
      for (final (raw, quality) in anchors) {
        expect(
          v3.qualityForRawScore(raw, ScoringCategory.beverage),
          quality,
          reason: 'beverage v3 anchor raw=$raw',
        );
      }
    });

    test(
      'V3 leaves cheese/redMeat/fatsOilsNutsSeeds byte-identical to V2 — '
      'the approved recalibration touched generalFood/beverage only',
      () {
        const rawSamples = <double>[-11.5, -5.5, 0, 2.5, 8, 10.5, 18.5, 26.5, 34.5, 42.5];
        for (final category in [
          ScoringCategory.cheese,
          ScoringCategory.redMeat,
          ScoringCategory.fatsOilsNutsSeeds,
        ]) {
          for (final raw in rawSamples) {
            expect(
              v3.qualityForRawScore(raw, category),
              v2.qualityForRawScore(raw, category),
              reason: '${category.name} raw=$raw must be untouched by V3',
            );
          }
        }
      },
    );

    test('V2 curve is completely unchanged by the existence of V3', () {
      // Guards against V3's implementation ever accidentally sharing
      // mutable state or a mutated constant with V2.
      const v2GeneralAnchors = <(double, double)>[
        (-5.5, 100),
        (0.5, 94),
        (2.5, 86),
        (10.5, 72),
        (18.5, 66),
        (26.5, 42),
        (34.5, 18),
        (42.5, 0),
      ];
      const v2BeverageAnchors = <(double, double)>[
        (-3.5, 95),
        (2.5, 88),
        (6.5, 75),
        (9.5, 60),
        (13.5, 40),
        (17.5, 20),
        (21.5, 0),
      ];
      for (final (raw, quality) in v2GeneralAnchors) {
        expect(v2.qualityForRawScore(raw, ScoringCategory.generalFood), quality);
      }
      for (final (raw, quality) in v2BeverageAnchors) {
        expect(v2.qualityForRawScore(raw, ScoringCategory.beverage), quality);
      }
    });

    test(
      'the v3-enabling migration ADDS v3 alongside v2 — never narrows, '
      'never rewrites the frozen v2-enabling migration',
      () {
        final v2Migration = File(
          'supabase/migrations/20260814000000_enable_score_v2_audit_snapshots.sql',
        ).readAsStringSync();
        // The original v2 migration must remain byte-for-byte the same
        // historical artifact — still v2-only, exactly as release-frozen
        // above.
        expect(v2Migration, contains("'nutrition_quality_transform_v2'"));
        expect(
          v2Migration,
          isNot(contains('nutrition_quality_transform_v3')),
          reason: 'the historical v2 migration must never be rewritten to '
              'know about v3',
        );

        final v3Migration = File(
          'supabase/migrations/20260819000000_enable_score_v3_audit_snapshots.sql',
        ).readAsStringSync();
        // Widened tuple: v3 added, v2 still accepted (Phase 1 shadow
        // rollout needs the RPC to keep accepting ordinary v2 writes from
        // the still-live production orchestrator while the backfill tool
        // writes v3 in parallel).
        expect(v3Migration, contains("'nutrition_quality_transform_v2'"));
        expect(v3Migration, contains("'nutrition_quality_transform_v3'"));
        expect(
          v3Migration,
          contains(
            "p_nutrition_transform_version NOT IN (\n"
            "       'nutrition_quality_transform_v2',\n"
            "       'nutrition_quality_transform_v3'\n"
            "     )",
          ),
        );
        // Every OTHER axis of the version tuple, and the score
        // reconciliation math, must be untouched.
        expect(v3Migration, contains("'etiketly_score_v2'"));
        expect(v3Migration, contains("'updated_nutrition_profile_2023_v1'"));
        expect(v3Migration, contains("'additive_quality_transform_v1'"));
        expect(v3Migration, contains('p_snapshot_schema_version IS DISTINCT FROM 1'));
        expect(v3Migration, contains('0.80 * v_nutrition_quality'));
        expect(v3Migration, contains('0.20 * v_additive_quality'));
      },
    );
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

  test(
    'historical recovery tooling never fabricates evidence or scores directly',
    () {
      final runner = File(
        'lib/features/scoring/application/legacy_scoring_recovery_lifecycle_runner.dart',
      ).readAsStringSync();
      final tool = File(
        'tool/legacy_scoring_recovery_lifecycle.dart',
      ).readAsStringSync();

      // Apply must route through the trusted lifecycle with the recovery
      // service as the evidence resolver, using the reserved backfill
      // trigger — never a raw evidence/audit write of its own.
      expect(runner, contains('ProductScoringLifecycleService'));
      expect(runner, contains('recovery.recoverEvidence'));
      expect(runner, contains('ScoreAuditTriggerSource.controlledBackfill'));
      expect(runner, isNot(contains('dataSource.writeScoringEvidence(')));
      expect(runner, isNot(contains('dataSource.insertSnapshot(')));

      // Dry-run must only ever call the read-only recovery evaluation.
      expect(runner, contains('recovery.recover('));

      expect(tool, contains('LegacyScoringRecoveryLifecycleRunner'));
      expect(tool, isNot(contains('ScoringEvidenceSnapshot(')));
    },
  );

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

  group('product_staging access restriction', () {
    const migrationPath =
        'supabase/migrations/20260815000000_restrict_product_staging_access.sql';

    test('explicitly enables RLS early, before final policies/grants, without FORCE', () {
      final migration = File(migrationPath).readAsStringSync();
      const enableStatement =
          'ALTER TABLE public.product_staging ENABLE ROW LEVEL SECURITY;';

      expect(migration, contains(enableStatement));
      expect(
        migration,
        isNot(
          contains('ALTER TABLE public.product_staging FORCE ROW LEVEL SECURITY'),
        ),
        reason:
            'FORCE would also restrict the table owner and change '
            'postgres/service-role semantics beyond this migration\'s intent',
      );

      final beginIndex = migration.indexOf('BEGIN;');
      final enableIndex = migration.indexOf(enableStatement);
      final firstCreatePolicyIndex = migration.indexOf('CREATE POLICY');
      final firstGrantIndex = migration.indexOf('GRANT ');
      expect(beginIndex, greaterThanOrEqualTo(0));
      expect(enableIndex, greaterThan(beginIndex));
      expect(
        enableIndex,
        lessThan(firstCreatePolicyIndex),
        reason: 'RLS must be enabled before the final policies are created',
      );
      expect(
        enableIndex,
        lessThan(firstGrantIndex),
        reason: 'RLS must be enabled before the final grants are established',
      );
    });

    test('drops every confirmed-live broad/dev policy before the fail-closed guard', () {
      final migration = File(migrationPath).readAsStringSync();
      final guardIndex = migration.indexOf('DO \$\$');
      expect(guardIndex, greaterThan(0));

      for (final policy in [
        'authenticated can insert product_staging',
        'authenticated can select product_staging',
        'authenticated can update product_staging',
        'dev anon can read product_staging',
        'dev anon can update product_staging',
        'dev authenticated can read product_staging',
        // Migration-history names, dropped defensively in case an
        // environment's history diverges from the confirmed live names.
        'dev: select product_staging',
        'dev: insert product_staging',
        'dev: update product_staging',
      ]) {
        final drop = 'DROP POLICY IF EXISTS "$policy" ON public.product_staging;';
        expect(migration, contains(drop), reason: policy);
        expect(
          migration.indexOf(drop),
          lessThan(guardIndex),
          reason: '$policy must be dropped before the fail-closed guard',
        );
      }
    });

    test('fails closed on any residual policy, not just write policies', () {
      final migration = File(migrationPath).readAsStringSync();

      expect(
        migration,
        contains("RAISE EXCEPTION 'unexpected_product_staging_policy'"),
      );
      // Unlike the products migration (which intentionally keeps a public
      // SELECT policy and only guards write commands), product_staging has
      // no legitimate policy that should survive the drops above — the
      // guard must not be scoped to a cmd allowlist.
      expect(migration, isNot(contains("cmd IN (")));
      expect(
        migration,
        contains(
          "WHERE schemaname = 'public'\n"
          "      AND tablename = 'product_staging'",
        ),
      );
    });

    test('anon loses all product_staging access', () {
      final migration = File(migrationPath).readAsStringSync();

      expect(
        migration,
        contains('REVOKE ALL ON TABLE public.product_staging FROM PUBLIC;'),
      );
      expect(
        migration,
        contains('REVOKE ALL ON TABLE public.product_staging FROM anon;'),
      );
      expect(migration, isNot(contains('TO anon')));
    });

    test('authenticated gets exactly SELECT + UPDATE, never INSERT or DELETE', () {
      final migration = File(migrationPath).readAsStringSync();

      expect(
        migration,
        contains('REVOKE ALL ON TABLE public.product_staging FROM authenticated;'),
      );
      expect(
        migration,
        contains(
          'GRANT SELECT, UPDATE ON TABLE public.product_staging TO authenticated;',
        ),
      );
      expect(
        migration,
        isNot(contains('INSERT ON TABLE public.product_staging TO authenticated')),
      );
      expect(
        migration,
        isNot(contains('DELETE ON TABLE public.product_staging TO authenticated')),
      );
    });

    test(
      'service_role is stripped to exactly SELECT/INSERT/UPDATE — live '
      'DELETE/REFERENCES/TRIGGER/TRUNCATE are not re-granted',
      () {
        final migration = File(migrationPath).readAsStringSync();

        expect(
          migration,
          contains(
            'REVOKE ALL ON TABLE public.product_staging FROM service_role;',
          ),
        );
        expect(
          migration,
          contains(
            'GRANT SELECT, INSERT, UPDATE ON TABLE public.product_staging '
            'TO service_role;',
          ),
        );
        final revokeIndex = migration.indexOf(
          'REVOKE ALL ON TABLE public.product_staging FROM service_role;',
        );
        final grantIndex = migration.indexOf(
          'GRANT SELECT, INSERT, UPDATE ON TABLE public.product_staging '
          'TO service_role;',
        );
        expect(
          revokeIndex,
          lessThan(grantIndex),
          reason: 'must revoke the live broad grant before re-granting least '
              'privilege',
        );
        expect(
          migration,
          isNot(contains('DELETE ON TABLE public.product_staging TO service_role')),
        );
        expect(
          migration,
          isNot(
            contains('REFERENCES ON TABLE public.product_staging TO service_role'),
          ),
        );
        expect(
          migration,
          isNot(contains('TRIGGER ON TABLE public.product_staging TO service_role')),
        );
        expect(
          migration,
          isNot(
            contains('TRUNCATE ON TABLE public.product_staging TO service_role'),
          ),
        );
      },
    );

    test('exactly two admin policies exist, both gated by is_freshscan_admin, neither INSERT nor DELETE', () {
      final migration = File(migrationPath).readAsStringSync();

      expect(
        RegExp(r'CREATE POLICY "admins can \w+ product_staging"').allMatches(migration),
        hasLength(2),
      );
      expect(
        migration,
        contains(
          'CREATE POLICY "admins can select product_staging"\n'
          '  ON public.product_staging\n'
          '  FOR SELECT\n'
          '  TO authenticated\n'
          '  USING (public.is_freshscan_admin());',
        ),
      );
      expect(
        migration,
        contains(
          'CREATE POLICY "admins can update product_staging"\n'
          '  ON public.product_staging\n'
          '  FOR UPDATE\n'
          '  TO authenticated\n'
          '  USING (public.is_freshscan_admin())\n'
          '  WITH CHECK (public.is_freshscan_admin());',
        ),
      );
      expect(migration, isNot(contains('FOR INSERT')));
      expect(migration, isNot(contains('FOR DELETE')));
      expect(migration, isNot(contains('FOR ALL')));
    });

    test('migration is transactional and touches no scoring logic or data', () {
      final migration = File(migrationPath).readAsStringSync();

      expect(migration, contains('BEGIN;'));
      expect(migration, contains('COMMIT;'));
      expect(migration, isNot(contains('CREATE OR REPLACE FUNCTION')));
      expect(migration, isNot(contains('UPDATE public.product_staging SET')));
      expect(migration, isNot(contains('DELETE FROM public.product_staging')));
      expect(migration, isNot(contains('INSERT INTO public.product_staging')));
      // Must not touch the two migrations explicitly out of scope.
      expect(
        Directory('supabase/migrations')
            .listSync()
            .whereType<File>()
            .map((f) => f.path.split('/').last)
            .where(
              (name) =>
                  name.startsWith('20260626010000') ||
                  name.startsWith('20260814010000'),
            ),
        hasLength(2),
        reason:
            'both referenced migrations must still exist untouched alongside '
            'the new one',
      );
    });

    test('the read-only preflight script never writes and is never auto-executed', () {
      final script = File(
        'tmp/product_staging_rls_preflight.sh',
      ).readAsStringSync();

      expect(script, contains('BEGIN TRANSACTION READ ONLY;'));
      expect(script, contains('ROLLBACK;'));
      expect(script, contains('DO NOT execute this script as part of an agent task'));
      expect(
        script,
        isNot(
          contains(RegExp(r'\b(INSERT INTO|UPDATE public|DELETE FROM|DROP |ALTER )')),
        ),
      );
    });
  });
}
