import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/product/models/ingredient.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/scoring/application/legacy_scoring_evidence_recovery.dart';
import 'package:food_analyzer_app/features/scoring/application/legacy_scoring_recovery_lifecycle_runner.dart';
import 'package:food_analyzer_app/features/scoring/application/product_etiketly_score_orchestrator.dart';
import 'package:food_analyzer_app/features/scoring/application/product_score_audit_evaluator.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/composition_percentage_evidence.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_score_audit_snapshot.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_score_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/presence_evidence.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/score_audit_write.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_evidence_snapshot.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';
import 'package:food_analyzer_app/features/scoring/presentation/etiketly_score_presentation.dart';

import 'scoring_test_fixtures.dart';
import 'support/score_audit_test_support.dart';

void main() {
  group('dry run', () {
    test('1. recoverable legacy Migros fixture reports recoverable', () async {
      final dataSource = _FakeRecoveryDataSource(
        products: {_product().id: _product()},
        staging: {_product().sourceUrl!: [_staging()]},
      );
      final runner = LegacyScoringRecoveryLifecycleRunner(
        dataSource: dataSource,
      );

      final summary = await runner.runForProductIds(
        dryRun: true,
        productIds: [_product().id],
      );

      expect(summary.results.single.outcome, LegacyScoringRecoveryOutcome.recoverable);
      expect(summary.results.single.wouldApply, isTrue);
      expect(summary.results.single.blockerReasons, isEmpty);
      expect(dataSource.writeScoringEvidenceCalls, 0);
      expect(dataSource.insertSnapshotCalls, 0);
    });

    test(
      '2. evidence-recoverable but scoring-readiness-blocked reports blocked, not recoverable',
      () async {
        // Basis/nutrition/category all check out (recoverEvidence() would
        // produce non-null evidence), but the unresolved E999-like token
        // against an empty catalogue blocks the full readiness evaluation.
        final product = _product(
          ingredientsText: 'mısır unu, bitkisel yağ, tuz, E999',
        );
        final evidenceOnly = await const LegacyScoringEvidenceRecoveryService()
            .recoverEvidence(
              product: product,
              stagingMatches: [_staging(product: product)],
              ingredientCatalogue: const [],
            );
        expect(
          evidenceOnly.evidence,
          isNotNull,
          reason: 'fixture must genuinely be evidence-recoverable',
        );

        final dataSource = _FakeRecoveryDataSource(
          products: {product.id: product},
          staging: {product.sourceUrl!: [_staging(product: product)]},
        );
        final runner = LegacyScoringRecoveryLifecycleRunner(
          dataSource: dataSource,
        );

        final summary = await runner.runForProductIds(
          dryRun: true,
          productIds: [product.id],
        );

        expect(
          summary.results.single.outcome,
          LegacyScoringRecoveryOutcome.blocked,
        );
        expect(dataSource.writeScoringEvidenceCalls, 0);
        expect(dataSource.insertSnapshotCalls, 0);
      },
    );

    test('3. missing staging match is blocked', () async {
      final product = _product();
      final dataSource = _FakeRecoveryDataSource(
        products: {product.id: product},
        staging: const {},
      );
      final runner = LegacyScoringRecoveryLifecycleRunner(
        dataSource: dataSource,
      );

      final summary = await runner.runForProductIds(
        dryRun: true,
        productIds: [product.id],
      );

      expect(summary.results.single.outcome, LegacyScoringRecoveryOutcome.blocked);
      expect(
        summary.results.single.blockerReasons,
        contains('missing_staging_match'),
      );
    });

    test('4. assumed/unknown nutrition basis is rejected', () async {
      final product = _product();
      final dataSource = _FakeRecoveryDataSource(
        products: {product.id: product},
        staging: {
          product.sourceUrl!: [
            _staging(warnings: const ['nutrition_basis_unknown_assumed_per_100']),
          ],
        },
      );
      final runner = LegacyScoringRecoveryLifecycleRunner(
        dataSource: dataSource,
      );

      final summary = await runner.runForProductIds(
        dryRun: true,
        productIds: [product.id],
      );

      expect(summary.results.single.outcome, LegacyScoringRecoveryOutcome.blocked);
      expect(
        summary.results.single.blockerReasons,
        contains('basis_unknown_assumed_per100'),
      );
    });

    test('5. per-serving-only basis is rejected', () async {
      final product = _product();
      final dataSource = _FakeRecoveryDataSource(
        products: {product.id: product},
        staging: {
          product.sourceUrl!: [_staging(basis: 'per_serving')],
        },
      );
      final runner = LegacyScoringRecoveryLifecycleRunner(
        dataSource: dataSource,
      );

      final summary = await runner.runForProductIds(
        dryRun: true,
        productIds: [product.id],
      );

      expect(summary.results.single.outcome, LegacyScoringRecoveryOutcome.blocked);
      expect(
        summary.results.single.blockerReasons,
        contains('basis_per_serving'),
      );
    });

    test('6. nutrition mismatch against staging is rejected', () async {
      final product = _product();
      final dataSource = _FakeRecoveryDataSource(
        products: {product.id: product},
        staging: {
          product.sourceUrl!: [
            _staging(
              nutritionJson: {..._nutrition(), 'sugars': 999},
            ),
          ],
        },
      );
      final runner = LegacyScoringRecoveryLifecycleRunner(
        dataSource: dataSource,
      );

      final summary = await runner.runForProductIds(
        dryRun: true,
        productIds: [product.id],
      );

      expect(summary.results.single.outcome, LegacyScoringRecoveryOutcome.blocked);
      expect(
        summary.results.single.blockerReasons,
        contains('nutrition_source_unverified'),
      );
    });

    test('incomplete trusted nutrition evidence is rejected', () async {
      final product = _product(
        nutrition: {..._nutrition()}..remove('fiber'),
      );
      final dataSource = _FakeRecoveryDataSource(
        products: {product.id: product},
        staging: {
          product.sourceUrl!: [_staging(product: product, nutritionJson: product.nutrition?.toMap())],
        },
      );
      final runner = LegacyScoringRecoveryLifecycleRunner(
        dataSource: dataSource,
      );

      final summary = await runner.runForProductIds(
        dryRun: true,
        productIds: [product.id],
      );

      expect(summary.results.single.outcome, LegacyScoringRecoveryOutcome.blocked);
      expect(summary.results.single.blockerReasons, contains('missing_fiber'));
    });

    test('7 & 8. dry run makes zero evidence and zero audit writes', () async {
      final recoverable = _product(id: '0100');
      final blocked = _product(id: '0200');
      final dataSource = _FakeRecoveryDataSource(
        products: {recoverable.id: recoverable, blocked.id: blocked},
        staging: {
          recoverable.sourceUrl!: [_staging(product: recoverable)],
        },
      );
      final runner = LegacyScoringRecoveryLifecycleRunner(
        dataSource: dataSource,
      );

      await runner.runForProductIds(
        dryRun: true,
        productIds: [recoverable.id, blocked.id],
      );

      expect(dataSource.writeScoringEvidenceCalls, 0);
      expect(dataSource.insertSnapshotCalls, 0);
    });
  });

  group('apply', () {
    test('9 & 10 & 11. apply routes through the lifecycle and verifies evidence + a matching current audit', () async {
      final product = _product();
      final dataSource = _FakeRecoveryDataSource(
        products: {product.id: product},
        staging: {product.sourceUrl!: [_staging()]},
      );
      final runner = LegacyScoringRecoveryLifecycleRunner(
        dataSource: dataSource,
      );

      final summary = await runner.runForProductIds(
        dryRun: false,
        productIds: [product.id],
      );

      expect(
        summary.results.single.outcome,
        LegacyScoringRecoveryOutcome.recoveredAndCurrent,
      );
      expect(dataSource.writeScoringEvidenceCalls, 1);
      expect(dataSource.insertSnapshotCalls, 1);
      expect(dataSource.products[product.id]!.scoringEvidence, isNotNull);
      expect(dataSource.audits, hasLength(1));
      // The runner never fabricates ScoringEvidenceSnapshot itself — the
      // written evidence must be exactly what
      // LegacyScoringEvidenceRecoveryService.recoverEvidence produced.
      final expected = await const LegacyScoringEvidenceRecoveryService()
          .recoverEvidence(
            product: product,
            stagingMatches: [_staging()],
            ingredientCatalogue: const [],
          );
      expect(
        jsonEncode(dataSource.products[product.id]!.scoringEvidence!.toJson()),
        jsonEncode(expected.evidence!.toJson()),
      );
    });

    test(
      '9. apply eligibility matches dry-run eligibility exactly (readiness-blocked product never applies)',
      () async {
        final recoverableProduct = _product(id: '0700');
        final blockedProduct = _product(
          id: '0800',
          ingredientsText: 'mısır unu, bitkisel yağ, tuz, E999',
        );
        final products = {
          recoverableProduct.id: recoverableProduct,
          blockedProduct.id: blockedProduct,
        };
        final staging = {
          recoverableProduct.sourceUrl!: [_staging(product: recoverableProduct)],
          blockedProduct.sourceUrl!: [_staging(product: blockedProduct)],
        };

        final dryRunSource = _FakeRecoveryDataSource(
          products: products,
          staging: staging,
        );
        final dryRunSummary = await LegacyScoringRecoveryLifecycleRunner(
          dataSource: dryRunSource,
        ).runForProductIds(
          dryRun: true,
          productIds: [recoverableProduct.id, blockedProduct.id],
        );

        final applySource = _FakeRecoveryDataSource(
          products: products,
          staging: staging,
        );
        final applySummary = await LegacyScoringRecoveryLifecycleRunner(
          dataSource: applySource,
        ).runForProductIds(
          dryRun: false,
          productIds: [recoverableProduct.id, blockedProduct.id],
        );

        bool wouldSucceed(LegacyScoringRecoveryOutcome outcome) =>
            outcome == LegacyScoringRecoveryOutcome.recoverable ||
            outcome == LegacyScoringRecoveryOutcome.recoveredAndCurrent;

        for (var i = 0; i < dryRunSummary.results.length; i++) {
          expect(
            wouldSucceed(applySummary.results[i].outcome),
            wouldSucceed(dryRunSummary.results[i].outcome),
            reason: dryRunSummary.results[i].productId,
          );
        }
        // The blocked product specifically must never reach processCurrent.
        expect(applySource.writeScoringEvidenceCalls, 1);
        expect(applySource.insertSnapshotCalls, 1);
      },
    );

    test('blocked product makes zero writes and reports exact blockers', () async {
      final product = _product();
      final dataSource = _FakeRecoveryDataSource(
        products: {product.id: product},
        staging: const {},
      );
      final runner = LegacyScoringRecoveryLifecycleRunner(
        dataSource: dataSource,
      );

      final summary = await runner.runForProductIds(
        dryRun: false,
        productIds: [product.id],
      );

      expect(summary.results.single.outcome, LegacyScoringRecoveryOutcome.blocked);
      expect(
        summary.results.single.blockerReasons,
        contains('missing_staging_match'),
      );
      expect(dataSource.writeScoringEvidenceCalls, 0);
      expect(dataSource.insertSnapshotCalls, 0);
    });

    test(
      '12. evidence written but current audit not independently verifiable is never reported as success',
      () async {
        final product = _product();
        final dataSource = _FakeRecoveryDataSource(
          products: {product.id: product},
          staging: {product.sourceUrl!: [_staging()]},
          // The 1st fetchMatchingSnapshot call is processCurrent's own
          // pre-insert check (legitimately empty). Starting at the 2nd
          // call — the runner's independent postcondition re-check — force
          // a miss even though the row now exists, simulating that the
          // evidence write and the audit insert are not one transaction.
          failVerificationFromCall: 2,
        );
        final runner = LegacyScoringRecoveryLifecycleRunner(
          dataSource: dataSource,
        );

        final summary = await runner.runForProductIds(
          dryRun: false,
          productIds: [product.id],
        );

        expect(
          summary.results.single.outcome,
          LegacyScoringRecoveryOutcome.auditNotCurrentAfterApply,
        );
        expect(
          summary.results.single.blockerReasons,
          contains('audit_not_current_after_apply'),
        );
        // The row genuinely exists (write happened) — this must never be
        // conflated with "recovered", exactly the failure mode this guards.
        expect(dataSource.audits, hasLength(1));
        expect(dataSource.products[product.id]!.scoringEvidence, isNotNull);
      },
    );

    test(
      '13 & 17 & 18. retry after an incomplete apply is idempotent, an already-current rerun is a no-op, and no duplicate audit is created',
      () async {
        final product = _product();
        final laggingDataSource = _FakeRecoveryDataSource(
          products: {product.id: product},
          staging: {product.sourceUrl!: [_staging()]},
          failVerificationFromCall: 2,
        );
        final runner = LegacyScoringRecoveryLifecycleRunner(
          dataSource: laggingDataSource,
        );
        final firstAttempt = await runner.runForProductIds(
          dryRun: false,
          productIds: [product.id],
        );
        expect(
          firstAttempt.results.single.outcome,
          LegacyScoringRecoveryOutcome.auditNotCurrentAfterApply,
        );
        expect(laggingDataSource.audits, hasLength(1));

        // "The replica has caught up": retry with verification restored.
        final recoveredDataSource = _FakeRecoveryDataSource(
          products: laggingDataSource.products,
          staging: {product.sourceUrl!: [_staging()]},
          audits: laggingDataSource.audits,
        );
        final retryRunner = LegacyScoringRecoveryLifecycleRunner(
          dataSource: recoveredDataSource,
        );
        final retry = await retryRunner.runForProductIds(
          dryRun: false,
          productIds: [product.id],
        );

        expect(retry.results.single.outcome, LegacyScoringRecoveryOutcome.alreadyCurrent);
        expect(recoveredDataSource.writeScoringEvidenceCalls, 0);
        expect(recoveredDataSource.insertSnapshotCalls, 0);
        expect(recoveredDataSource.audits, hasLength(1));
      },
    );
  });

  group('existing evidence protection (--product-id)', () {
    test(
      '14 & 15. existing scoring_evidence and adminVerification provenance are never touched when no current audit exists',
      () async {
        final existingEvidence = ScoringEvidenceSnapshot(
          nutritionBasis: NutritionBasis.per100g,
          nutritionProductState: NutritionProductState.asSold,
          nutrition: completeNutrition(),
          fvlEvidence: const CompositionPercentageEvidence.provenAbsent(
            provenance: EvidenceProvenance.declaredLabel,
            verification: EvidenceVerification.verified,
          ),
          nnsEvidence: const PresenceEvidence.absent(
            provenance: EvidenceProvenance.declaredLabel,
            verification: EvidenceVerification.verified,
          ),
          ingredientEvidenceCompleteness: IngredientEvidenceCompleteness.complete,
          categoryEvidence: explicitCategory(ScoringCategory.generalFood),
          adminVerification: ScoringEvidenceAdminMetadata(
            verifiedBy: 'admin-1',
            verifiedAt: DateTime.utc(2026, 1, 1),
            note: 'manually verified by admin',
          ),
        );
        final product = auditProductFromInput(
          existingEvidence.toScoringInput(),
          id: 'evidenced-0001',
          ingredientsText: 'Su',
        );
        final productWithEvidence = _copyProduct(
          product,
          scoringEvidence: existingEvidence,
        );
        // No staging row at all — proves the recovery service path is
        // structurally unreachable here, not merely unused by coincidence.
        final dataSource = _FakeRecoveryDataSource(
          products: {productWithEvidence.id: productWithEvidence},
          staging: const {},
          catalogue: [auditOrdinaryIngredient()],
        );
        final runner = LegacyScoringRecoveryLifecycleRunner(
          dataSource: dataSource,
        );

        final summary = await runner.runForProductIds(
          dryRun: false,
          productIds: [productWithEvidence.id],
        );

        expect(dataSource.writeScoringEvidenceCalls, 0);
        expect(
          summary.results.single.outcome,
          isNot(LegacyScoringRecoveryOutcome.unexpectedError),
        );
        final storedEvidence = dataSource.products[productWithEvidence.id]!
            .scoringEvidence!;
        expect(
          jsonEncode(storedEvidence.toJson()),
          jsonEncode(existingEvidence.toJson()),
          reason: 'existing evidence must be byte/semantically unchanged',
        );
        expect(storedEvidence.adminVerification?.verifiedBy, 'admin-1');
        expect(
          storedEvidence.adminVerification?.note,
          'manually verified by admin',
        );
        expect(
          storedEvidence.adminVerification?.verifiedAt,
          DateTime.utc(2026, 1, 1),
        );
      },
    );

    test(
      'existing evidence with a current matching audit reports already_current without any write',
      () async {
        final input = completeInput();
        final product = auditProductFromInput(
          input,
          id: 'evidenced-already-current',
          ingredientsText: 'Su',
        );
        final matchingAudit = buildAuditSnapshot(
          product: product,
          assessment: auditOrdinaryAssessment(),
        );
        final dataSource = _FakeRecoveryDataSource(
          products: {product.id: product},
          staging: const {},
          catalogue: [auditOrdinaryIngredient()],
          audits: [matchingAudit],
        );
        final runner = LegacyScoringRecoveryLifecycleRunner(
          dataSource: dataSource,
        );

        final summary = await runner.runForProductIds(
          dryRun: false,
          productIds: [product.id],
        );

        expect(
          summary.results.single.outcome,
          LegacyScoringRecoveryOutcome.alreadyCurrent,
        );
        expect(dataSource.writeScoringEvidenceCalls, 0);
        expect(dataSource.insertSnapshotCalls, 0);
        expect(dataSource.audits, hasLength(1));
      },
    );
  });

  group('JSON round-trip', () {
    test(
      '16. recovered evidence readiness and fingerprint-relevant values survive toJson/tryFromJson',
      () async {
        final product = _product();
        final recovered = await const LegacyScoringEvidenceRecoveryService()
            .recoverEvidence(
              product: product,
              stagingMatches: [_staging()],
              ingredientCatalogue: const [],
            );
        final original = recovered.evidence!;
        final roundTripped = ScoringEvidenceSnapshot.tryFromJson(
          original.toJson(),
        );

        expect(roundTripped, isNotNull);
        expect(roundTripped!.nutritionBasis, original.nutritionBasis);
        expect(
          roundTripped.nutritionProductState,
          original.nutritionProductState,
        );
        expect(
          roundTripped.nutrition.energyKj.value,
          original.nutrition.energyKj.value,
        );
        expect(
          roundTripped.nutrition.energyKj.provenance,
          original.nutrition.energyKj.provenance,
        );
        expect(
          roundTripped.nutrition.energyKj.verification,
          original.nutrition.energyKj.verification,
        );
        expect(
          roundTripped.categoryEvidence.resolvedCategory,
          original.categoryEvidence.resolvedCategory,
        );
        expect(roundTripped.fvlEvidence.state, original.fvlEvidence.state);
        // Full fidelity: the round trip must not silently drop or alter
        // anything readiness/fingerprint depends on.
        expect(
          jsonEncode(roundTripped.toJson()),
          jsonEncode(original.toJson()),
        );
      },
    );

    test(
      'apply postcondition reads the re-read persisted representation, not the pre-write object',
      () async {
        final product = _product();
        final dataSource = _FakeRecoveryDataSource(
          products: {product.id: product},
          staging: {product.sourceUrl!: [_staging()]},
        );
        final runner = LegacyScoringRecoveryLifecycleRunner(
          dataSource: dataSource,
        );

        await runner.runForProductIds(dryRun: false, productIds: [product.id]);

        final persistedEvidence =
            dataSource.products[product.id]!.scoringEvidence!;
        final expected = await const LegacyScoringEvidenceRecoveryService()
            .recoverEvidence(
              product: product,
              stagingMatches: [_staging()],
              ingredientCatalogue: const [],
            );
        // Never the exact same object reference the resolver produced —
        // the fake always round-trips through JSON on write.
        expect(identical(persistedEvidence, expected.evidence), isFalse);
        // ...but semantically equal after the round trip.
        expect(
          jsonEncode(persistedEvidence.toJson()),
          jsonEncode(expected.evidence!.toJson()),
        );
      },
    );

    test(
      'malformed/lossy persisted evidence cannot be reported as success',
      () async {
        final product = _product();
        final dataSource = _FakeRecoveryDataSource(
          products: {product.id: product},
          staging: {product.sourceUrl!: [_staging()]},
          corruptPersistedEvidenceJson: true,
        );
        final runner = LegacyScoringRecoveryLifecycleRunner(
          dataSource: dataSource,
        );

        final summary = await runner.runForProductIds(
          dryRun: false,
          productIds: [product.id],
        );

        expect(
          summary.results.single.outcome,
          isNot(LegacyScoringRecoveryOutcome.recoveredAndCurrent),
        );
        // The corruption (dropped nutrition_basis) degrades readiness on
        // re-evaluation, so no audit should ever have been inserted.
        expect(dataSource.audits, isEmpty);
      },
    );
  });

  group('batching and targeting', () {
    test(
      '20. --source style batches filter by an EXACT source match, never a prefix/wildcard',
      () async {
        final exact = _product(id: '0900', source: 'web_scraper:migros');
        final widerVariant = _product(
          id: '0901',
          source: 'web_scraper:migros_v2',
        );
        final percentInjection = _product(
          id: '0902',
          source: 'web_scraper:migros%',
        );
        final dataSource = _FakeRecoveryDataSource(
          products: {
            exact.id: exact,
            widerVariant.id: widerVariant,
            percentInjection.id: percentInjection,
          },
          staging: {exact.sourceUrl!: [_staging(product: exact)]},
        );
        final runner = LegacyScoringRecoveryLifecycleRunner(
          dataSource: dataSource,
        );

        final summary = await runner.runForSource(
          dryRun: true,
          source: 'web_scraper:migros',
          limit: 10,
        );

        expect(summary.totalExamined, 1);
        expect(summary.results.single.productId, exact.id);
      },
    );

    test('--source style batches are bounded by limit', () async {
      final products = List.generate(5, (i) => _product(id: '0${i + 1}00'));
      final dataSource = _FakeRecoveryDataSource(
        products: {for (final p in products) p.id: p},
        staging: {for (final p in products) p.sourceUrl!: [_staging(product: p)]},
      );
      final runner = LegacyScoringRecoveryLifecycleRunner(
        dataSource: dataSource,
      );

      final summary = await runner.runForSource(
        dryRun: true,
        source: 'web_scraper:migros',
        limit: 2,
        batchSize: 10,
      );

      expect(summary.totalExamined, 2);
      expect(summary.reachedLimit, isTrue);
      expect(dataSource.fetchRecoveryCandidatesCalls.every((c) => c.limit <= 2), isTrue);
    });

    test('--source resumes strictly after the supplied start-after cursor', () async {
      final products = List.generate(5, (i) => _product(id: '0${i + 1}00'));
      final dataSource = _FakeRecoveryDataSource(
        products: {for (final p in products) p.id: p},
        staging: {for (final p in products) p.sourceUrl!: [_staging(product: p)]},
      );
      final runner = LegacyScoringRecoveryLifecycleRunner(
        dataSource: dataSource,
      );

      final summary = await runner.runForSource(
        dryRun: true,
        source: 'web_scraper:migros',
        limit: 10,
        startAfterProductId: '0200',
      );

      expect(summary.totalExamined, 3);
      expect(
        summary.results.map((r) => r.productId),
        ['0300', '0400', '0500'],
      );
    });

    test('17. --product-id targeted mode never scans the catalogue', () async {
      final product = _product();
      final dataSource = _FakeRecoveryDataSource(
        products: {product.id: product},
        staging: {product.sourceUrl!: [_staging()]},
      );
      final runner = LegacyScoringRecoveryLifecycleRunner(
        dataSource: dataSource,
      );

      await runner.runForProductIds(dryRun: true, productIds: [product.id]);

      expect(dataSource.fetchRecoveryCandidatesCalls, isEmpty);
    });

    test('one blocked product does not stop the next product', () async {
      final blocked = _product(id: '0300');
      final recoverable = _product(id: '0400');
      final dataSource = _FakeRecoveryDataSource(
        products: {blocked.id: blocked, recoverable.id: recoverable},
        staging: {
          recoverable.sourceUrl!: [_staging(product: recoverable)],
        },
      );
      final runner = LegacyScoringRecoveryLifecycleRunner(
        dataSource: dataSource,
      );

      final summary = await runner.runForProductIds(
        dryRun: true,
        productIds: [blocked.id, recoverable.id],
      );

      expect(summary.results, hasLength(2));
      expect(summary.results[0].outcome, LegacyScoringRecoveryOutcome.blocked);
      expect(
        summary.results[1].outcome,
        LegacyScoringRecoveryOutcome.recoverable,
      );
    });

    test('19. an unexpected per-product failure is isolated', () async {
      final failing = _product(id: '0500');
      final recoverable = _product(id: '0600');
      final dataSource = _FakeRecoveryDataSource(
        products: {failing.id: failing, recoverable.id: recoverable},
        staging: {
          recoverable.sourceUrl!: [_staging(product: recoverable)],
        },
        throwOnStagingLookupFor: failing.sourceUrl,
      );
      final runner = LegacyScoringRecoveryLifecycleRunner(
        dataSource: dataSource,
      );

      final summary = await runner.runForProductIds(
        dryRun: true,
        productIds: [failing.id, recoverable.id],
      );

      expect(summary.results[0].outcome, LegacyScoringRecoveryOutcome.unexpectedError);
      expect(
        summary.results[1].outcome,
        LegacyScoringRecoveryOutcome.recoverable,
      );
    });
  });

  group('26. Product Detail blocker presentation states', () {
    const mapper = EtiketlyScorePresentationMapper();

    // A genuine not-calculated EtiketlyScoreResult (missing fiber), built
    // through the real orchestrator rather than hand-constructed — the
    // presentation mapper must not care why it's not calculated, only
    // whether trusted evidence exists.
    EtiketlyScoreResult notCalculableResult() {
      final input = completeInput(
        nutrition: completeNutrition(includeFiber: false),
      );
      final product = auditProductFromInput(input, ingredientsText: 'Su');
      final evaluation = const ProductEtiketlyScoreOrchestrator().calculate(
        product: product,
        canonicalAssessment: auditOrdinaryAssessment(),
      );
      return evaluation!.result;
    }

    test('A. no trusted evidence yet', () {
      final state = mapper.fromResult(
        notCalculableResult(),
        usesLegacyFallback: true,
      );

      expect(
        state.unavailableStage,
        ProductEtiketlyScoreUnavailableStage.noTrustedEvidence,
      );
      expect(state.message, isNot(contains('güvenli')));
      expect(state.message, isNot(contains('tehlikeli')));
      expect(state.message, isNot(contains('sağlıksız')));
    });

    test('B. evidence exists but readiness is incomplete', () {
      final state = mapper.fromResult(
        notCalculableResult(),
        usesLegacyFallback: false,
      );

      expect(
        state.unavailableStage,
        ProductEtiketlyScoreUnavailableStage.evidenceIncompleteReadiness,
      );
    });

    test('C. evidence is scoring-ready but current matching audit unavailable', () {
      final state = mapper.auditSnapshotRequired();

      expect(
        state.unavailableStage,
        ProductEtiketlyScoreUnavailableStage.auditNotCurrent,
      );
      expect(state.message, 'Puan kaydı güncelleniyor.');
      expect(state.displayScore, isNull);
    });

    test(
      'D. current matching trusted audit produces a real calculated numeric score with no unavailable stage or message',
      () async {
        final input = completeInput();
        final product = auditProductFromInput(input, ingredientsText: 'Su');
        final evaluation = const ProductEtiketlyScoreOrchestrator().calculate(
          product: product,
          canonicalAssessment: auditOrdinaryAssessment(),
        );

        expect(evaluation, isNotNull);
        expect(
          evaluation!.isCalculated,
          isTrue,
          reason: 'fixture must genuinely reach a calculated score',
        );

        // Mirrors the controller's own gate: a numeric score is only ever
        // built via fromResult() after mayDisplayNumericScore is true —
        // exercised end-to-end in product_etiketly_score_integration_test.dart.
        final auditSnapshot = buildAuditSnapshot(
          product: product,
          assessment: auditOrdinaryAssessment(),
        );
        const evaluator = ProductScoreAuditEvaluator();
        final auditEvaluation = await evaluator.evaluate(
          product,
          [auditOrdinaryIngredient()],
        );
        expect(auditEvaluation.finalScoreReady, isTrue);
        expect(
          auditEvaluation.snapshot!.inputFingerprint,
          auditSnapshot.inputFingerprint,
          reason:
              'the independently rebuilt snapshot must match the trusted '
              'one by fingerprint before a number may ever be shown',
        );

        final state = mapper.fromResult(evaluation.result);

        expect(state.status, ProductEtiketlyScoreStatus.calculated);
        expect(state.displayScore, isNotNull);
        expect(state.unavailableStage, isNull);
        expect(state.message, isNull);
        expect(state.reasons, isEmpty);
      },
    );
  });
}

class _FetchRecoveryCandidatesCall {
  const _FetchRecoveryCandidatesCall({
    required this.source,
    required this.afterProductId,
    required this.limit,
  });

  final String source;
  final String? afterProductId;
  final int limit;
}

class _FakeRecoveryDataSource
    implements LegacyScoringRecoveryLifecycleDataSource {
  _FakeRecoveryDataSource({
    required Map<String, Product> products,
    required Map<String, List<LegacyStagingScoringEvidence>> staging,
    List<Ingredient> catalogue = const [],
    List<EtiketlyScoreAuditSnapshot>? audits,
    this.failVerificationFromCall,
    this.throwOnStagingLookupFor,
    this.corruptPersistedEvidenceJson = false,
  }) : products = {
         for (final entry in products.entries)
           entry.key: _roundTripEvidence(entry.value),
       },
       staging = {...staging},
       catalogue = [...catalogue],
       audits = [...?audits];

  final Map<String, Product> products;
  final Map<String, List<LegacyStagingScoringEvidence>> staging;
  final List<Ingredient> catalogue;
  final List<EtiketlyScoreAuditSnapshot> audits;
  final int? failVerificationFromCall;
  final String? throwOnStagingLookupFor;
  final bool corruptPersistedEvidenceJson;

  int writeScoringEvidenceCalls = 0;
  int insertSnapshotCalls = 0;
  int _fetchMatchingSnapshotCallCount = 0;
  final List<_FetchRecoveryCandidatesCall> fetchRecoveryCandidatesCalls = [];

  @override
  Future<Product?> fetchProduct(String productId) async => products[productId];

  @override
  Future<List<Ingredient>> fetchIngredientCatalogue() async => catalogue;

  @override
  Future<List<Product>> fetchRecoveryCandidates({
    required String source,
    required String? afterProductId,
    required int limit,
  }) async {
    fetchRecoveryCandidatesCalls.add(
      _FetchRecoveryCandidatesCall(
        source: source,
        afterProductId: afterProductId,
        limit: limit,
      ),
    );
    final ordered = products.values.toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    final afterIndex = afterProductId == null
        ? -1
        : ordered.indexWhere((p) => p.id == afterProductId);
    return ordered
        .skip(afterIndex + 1)
        // Exact match only — mirrors the production `eq.` filter, never
        // ILIKE/prefix matching.
        .where((p) => p.source == source)
        .take(limit)
        .toList(growable: false);
  }

  @override
  Future<List<LegacyStagingScoringEvidence>> fetchStagingMatches(
    String? sourceUrl,
  ) async {
    if (sourceUrl != null && sourceUrl == throwOnStagingLookupFor) {
      throw StateError('staging lookup failed');
    }
    return staging[sourceUrl] ?? const [];
  }

  @override
  Future<bool> writeScoringEvidence(
    String productId,
    ScoringEvidenceSnapshot evidence, {
    required ScoringEvidenceSnapshot? expectedCurrent,
  }) async {
    writeScoringEvidenceCalls++;
    final product = products[productId];
    if (product == null) return false;
    final current = product.scoringEvidence;
    if ((current == null) != (expectedCurrent == null) ||
        (current != null &&
            jsonEncode(current.toJson()) !=
                jsonEncode(expectedCurrent!.toJson()))) {
      return false;
    }
    // Simulate production persistence: never keep the exact object
    // reference the caller passed in — go through toJson/tryFromJson, as
    // the real REST data source effectively does via PATCH + re-fetch.
    var json = evidence.toJson();
    if (corruptPersistedEvidenceJson) {
      // toScoringInput() prefers the evidence-wrapped value over the plain
      // legacy field whenever the wrapper is present and verified, so
      // corrupting only the legacy field would have no effect on
      // readiness. Corrupt the wrapped nutrition value itself.
      final mutable = Map<String, dynamic>.from(json);
      final nutrition = Map<String, dynamic>.from(
        mutable['nutrition'] as Map,
      );
      nutrition['energy_kj'] = null;
      mutable['nutrition'] = nutrition;
      json = mutable;
    }
    final persisted = ScoringEvidenceSnapshot.tryFromJson(json);
    products[productId] = _copyProduct(product, scoringEvidence: persisted);
    return true;
  }

  @override
  Future<EtiketlyScoreAuditSnapshot?> fetchMatchingSnapshot(
    EtiketlyScoreAuditSnapshot current,
  ) async {
    _fetchMatchingSnapshotCallCount++;
    if (failVerificationFromCall != null &&
        _fetchMatchingSnapshotCallCount >= failVerificationFromCall!) {
      return null;
    }
    return audits
        .where(
          (snapshot) =>
              snapshot.productId == current.productId &&
              snapshot.inputFingerprint == current.inputFingerprint &&
              snapshot.scoreVersion == current.scoreVersion &&
              snapshot.nutritionMethodologyVersion ==
                  current.nutritionMethodologyVersion &&
              snapshot.nutritionTransformVersion ==
                  current.nutritionTransformVersion &&
              snapshot.additiveTransformVersion ==
                  current.additiveTransformVersion,
        )
        .lastOrNull;
  }

  @override
  Future<ScoreAuditSnapshotWriteResult> insertSnapshot(
    EtiketlyScoreAuditSnapshot snapshot, {
    required ScoreAuditTriggerSource triggerSource,
  }) async {
    insertSnapshotCalls++;
    expect(triggerSource, ScoreAuditTriggerSource.controlledBackfill);
    audits.add(snapshot);
    return ScoreAuditSnapshotWriteResult(
      snapshotId: 'snapshot-${audits.length}',
      inserted: true,
    );
  }

  static Product _roundTripEvidence(Product product) {
    final evidence = product.scoringEvidence;
    if (evidence == null) return product;
    final roundTripped = ScoringEvidenceSnapshot.tryFromJson(evidence.toJson());
    return _copyProduct(product, scoringEvidence: roundTripped);
  }
}

Product _copyProduct(
  Product product, {
  required ScoringEvidenceSnapshot? scoringEvidence,
}) {
  return Product(
    id: product.id,
    barcode: product.barcode,
    name: product.name,
    normalizedName: product.normalizedName,
    brand: product.brand,
    categoryId: product.categoryId,
    imageUrl: product.imageUrl,
    ingredientsText: product.ingredientsText,
    nutritionText: product.nutritionText,
    source: product.source,
    sourceUrl: product.sourceUrl,
    verificationStatus: product.verificationStatus,
    searchKeywords: product.searchKeywords,
    categoryTags: product.categoryTags,
    canonicalCategory: product.canonicalCategory,
    canonicalSubcategory: product.canonicalSubcategory,
    scoringEvidence: scoringEvidence,
    createdAt: product.createdAt,
    updatedAt: product.updatedAt,
  );
}

Product _product({
  String id = '0001',
  String name = 'Legacy Migros product',
  Map<String, dynamic>? nutrition,
  List<String>? categoryTags = const ['cips_kraker'],
  String ingredientsText = 'mısır unu, bitkisel yağ, tuz',
  String source = 'web_scraper:migros',
}) {
  final now = DateTime.utc(2026, 8, 8);
  return Product(
    id: id,
    barcode: '8690000000000',
    name: name,
    ingredientsText: ingredientsText,
    nutritionText: jsonEncode(nutrition ?? _nutrition()),
    source: source,
    sourceUrl: 'https://www.migros.com.tr/product-$id',
    verificationStatus: 'imported',
    categoryTags: categoryTags,
    createdAt: now,
    updatedAt: now,
  );
}

LegacyStagingScoringEvidence _staging({
  String id = 'staging-1',
  String? basis = 'per_100',
  List<String> warnings = const [],
  Product? product,
  Map<String, dynamic>? nutritionJson,
}) {
  final target = product ?? _product();
  return LegacyStagingScoringEvidence(
    id: id,
    sourceUrl: target.sourceUrl!,
    nutritionBasis: basis,
    nutritionWarnings: warnings,
    source: 'web_scraper:migros',
    ingredientsSource: 'web_scraper:migros',
    ingredientsRaw: 'İçindekiler: ${target.ingredientsText}',
    ingredientsText: target.ingredientsText,
    ingredientsQuality: 'ingredients_ok',
    nutritionSource: 'web_scraper:migros',
    nutritionStrategy: 'dom',
    nutritionJson: nutritionJson ?? target.nutrition?.toMap(),
  );
}

Map<String, dynamic> _nutrition() => const {
  'energy_kj': 840,
  'energy_kcal': 200,
  'fat': 3,
  'saturated_fat': 1,
  'carbohydrates': 15,
  'sugars': 5,
  'fiber': 2,
  'proteins': 4,
  'salt': 0.5,
};
