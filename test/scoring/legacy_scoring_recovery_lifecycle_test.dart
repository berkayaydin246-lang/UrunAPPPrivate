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
import 'package:food_analyzer_app/features/scoring/domain/models/evidence_value.dart';
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
        staging: {
          _product().sourceUrl!: [_staging()],
        },
      );
      final runner = LegacyScoringRecoveryLifecycleRunner(
        dataSource: dataSource,
      );

      final summary = await runner.runForProductIds(
        dryRun: true,
        productIds: [_product().id],
      );

      expect(
        summary.results.single.outcome,
        LegacyScoringRecoveryOutcome.recoverable,
      );
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
          staging: {
            product.sourceUrl!: [_staging(product: product)],
          },
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

      expect(
        summary.results.single.outcome,
        LegacyScoringRecoveryOutcome.blocked,
      );
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
            _staging(
              warnings: const ['nutrition_basis_unknown_assumed_per_100'],
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

      expect(
        summary.results.single.outcome,
        LegacyScoringRecoveryOutcome.blocked,
      );
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

      expect(
        summary.results.single.outcome,
        LegacyScoringRecoveryOutcome.blocked,
      );
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
            _staging(nutritionJson: {..._nutrition(), 'sugars': 999}),
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

      expect(
        summary.results.single.outcome,
        LegacyScoringRecoveryOutcome.blocked,
      );
      expect(
        summary.results.single.blockerReasons,
        contains('nutrition_source_unverified'),
      );
    });

    test('incomplete trusted nutrition evidence is rejected', () async {
      final product = _product(nutrition: {..._nutrition()}..remove('fiber'));
      final dataSource = _FakeRecoveryDataSource(
        products: {product.id: product},
        staging: {
          product.sourceUrl!: [
            _staging(
              product: product,
              nutritionJson: product.nutrition?.toMap(),
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

      expect(
        summary.results.single.outcome,
        LegacyScoringRecoveryOutcome.blocked,
      );
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
    test(
      '9 & 10 & 11. apply routes through the lifecycle and verifies evidence + a matching current audit',
      () async {
        final product = _product();
        final dataSource = _FakeRecoveryDataSource(
          products: {product.id: product},
          staging: {
            product.sourceUrl!: [_staging()],
          },
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
          jsonEncode(
            dataSource.products[product.id]!.scoringEvidence!.toJson(),
          ),
          jsonEncode(expected.evidence!.toJson()),
        );
      },
    );

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
          recoverableProduct.sourceUrl!: [
            _staging(product: recoverableProduct),
          ],
          blockedProduct.sourceUrl!: [_staging(product: blockedProduct)],
        };

        final dryRunSource = _FakeRecoveryDataSource(
          products: products,
          staging: staging,
        );
        final dryRunSummary =
            await LegacyScoringRecoveryLifecycleRunner(
              dataSource: dryRunSource,
            ).runForProductIds(
              dryRun: true,
              productIds: [recoverableProduct.id, blockedProduct.id],
            );

        final applySource = _FakeRecoveryDataSource(
          products: products,
          staging: staging,
        );
        final applySummary =
            await LegacyScoringRecoveryLifecycleRunner(
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

    test(
      'blocked product makes zero writes and reports exact blockers',
      () async {
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

        expect(
          summary.results.single.outcome,
          LegacyScoringRecoveryOutcome.blocked,
        );
        expect(
          summary.results.single.blockerReasons,
          contains('missing_staging_match'),
        );
        expect(dataSource.writeScoringEvidenceCalls, 0);
        expect(dataSource.insertSnapshotCalls, 0);
      },
    );

    test(
      '12. evidence written but current audit not independently verifiable is never reported as success',
      () async {
        final product = _product();
        final dataSource = _FakeRecoveryDataSource(
          products: {product.id: product},
          staging: {
            product.sourceUrl!: [_staging()],
          },
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
          staging: {
            product.sourceUrl!: [_staging()],
          },
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
          staging: {
            product.sourceUrl!: [_staging()],
          },
          audits: laggingDataSource.audits,
        );
        final retryRunner = LegacyScoringRecoveryLifecycleRunner(
          dataSource: recoveredDataSource,
        );
        final retry = await retryRunner.runForProductIds(
          dryRun: false,
          productIds: [product.id],
        );

        expect(
          retry.results.single.outcome,
          LegacyScoringRecoveryOutcome.alreadyCurrent,
        );
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
          ingredientEvidenceCompleteness:
              IngredientEvidenceCompleteness.complete,
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
        final storedEvidence =
            dataSource.products[productWithEvidence.id]!.scoringEvidence!;
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

    test(
      'dry-run for a product with existing evidence and a current matching audit reports alreadyCurrent, not recoverable — and performs zero writes',
      () async {
        final input = completeInput();
        final product = auditProductFromInput(
          input,
          id: 'evidenced-already-current-dry-run',
          ingredientsText: 'Su',
        );
        final matchingAudit = buildAuditSnapshot(
          product: product,
          assessment: auditOrdinaryAssessment(),
        );
        // No staging row at all. If dry-run mistakenly routed this product
        // through LegacyScoringEvidenceRecoveryService.recover() (the bug
        // under test), the product's own minimal nutritionText
        // ({'energy_kcal': 100}) has no staging fallback for classification/
        // FVL/etc. and would report `blocked`, never `alreadyCurrent` —
        // so asserting `alreadyCurrent` here proves recover() was never
        // consulted.
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
          dryRun: true,
          productIds: [product.id],
        );

        expect(summary.results.single.dryRun, isTrue);
        expect(
          summary.results.single.outcome,
          LegacyScoringRecoveryOutcome.alreadyCurrent,
        );
        expect(
          summary.results.single.outcome,
          isNot(LegacyScoringRecoveryOutcome.recoverable),
        );
        expect(dataSource.writeScoringEvidenceCalls, 0);
        expect(dataSource.insertSnapshotCalls, 0);
        expect(dataSource.audits, hasLength(1));
      },
    );

    test(
      'dry-run for a product with score-ready existing evidence but NO current matching audit reports auditRepairable, not recoverable',
      () async {
        final input = completeInput();
        final product = auditProductFromInput(
          input,
          id: 'evidenced-no-current-audit-dry-run',
          ingredientsText: 'Su',
        );
        final dataSource = _FakeRecoveryDataSource(
          products: {product.id: product},
          staging: const {},
          catalogue: [auditOrdinaryIngredient()],
          // No audits recorded — there is nothing current to match.
        );
        final runner = LegacyScoringRecoveryLifecycleRunner(
          dataSource: dataSource,
        );

        final summary = await runner.runForProductIds(
          dryRun: true,
          productIds: [product.id],
        );

        expect(summary.results.single.dryRun, isTrue);
        expect(
          summary.results.single.outcome,
          LegacyScoringRecoveryOutcome.auditRepairable,
          reason:
              'the evidence itself IS score-ready — this is a repairable '
              'audit gap, not a genuine evidence-readiness blocker',
        );
        expect(
          summary.results.single.outcome,
          isNot(LegacyScoringRecoveryOutcome.recoverable),
        );
        expect(dataSource.writeScoringEvidenceCalls, 0);
        expect(dataSource.insertSnapshotCalls, 0);
      },
    );

    group(
      'pre-APPLY trust correction: audit repairability requires '
      'independently trusted basis provenance on the CURRENT evidence',
      () {
        // A product whose CURRENT scoring_evidence basis provenance is
        // exactly [provenance] (including null, for missing provenance) —
        // otherwise completely score-ready (declaredLabel-grade nutrition/
        // FVL/NNS/category evidence from completeInput()). Deliberately
        // NEVER calls buildAuditSnapshot on this directly: for untrusted
        // [provenance] that would now correctly throw (see
        // ScoringEvidenceSnapshot.toScoringInput's basis-provenance-trust
        // downgrade to NutritionBasis.unknown) — the whole point of these
        // tests is that such a product can no longer be mathematically
        // scored at all, not merely "has no current audit yet".
        Product basisProvenanceProduct({
          required EvidenceProvenance? provenance,
          required String id,
          ScoringCategory category = ScoringCategory.generalFood,
        }) {
          final input = completeInput(category: category);
          final baseProduct = auditProductFromInput(
            input,
            id: id,
            ingredientsText: 'Su',
          );
          final base = baseProduct.scoringEvidence!;
          final evidence = provenance == null
              ? ScoringEvidenceSnapshot(
                  nutritionBasis: base.nutritionBasis,
                  nutritionBasisEvidence: null,
                  nutritionProductState: base.nutritionProductState,
                  nutritionProductStateEvidence:
                      base.nutritionProductStateEvidence,
                  nutrition: base.nutrition,
                  fvlEvidence: base.fvlEvidence,
                  nnsEvidence: base.nnsEvidence,
                  ingredientEvidenceCompleteness:
                      base.ingredientEvidenceCompleteness,
                  categoryEvidence: base.categoryEvidence,
                  classificationFacts: base.classificationFacts,
                )
              : base.copyWith(
                  nutritionBasisEvidence: EvidenceValue<NutritionBasis>(
                    value: input.nutritionBasis,
                    provenance: provenance,
                    verification: EvidenceVerification.verified,
                  ),
                );
          return _copyProduct(baseProduct, scoringEvidence: evidence);
        }

        test(
          'A: missing basis provenance, otherwise completely score-ready -> '
          'blocked insufficient evidence, never auditRepairable, never '
          'scoreableNotCurrent, would_apply=false',
          () async {
            final product = basisProvenanceProduct(
              provenance: null,
              id: 'trust-a-missing-provenance',
            );
            final dataSource = _FakeRecoveryDataSource(
              products: {product.id: product},
              staging: const {},
              catalogue: [auditOrdinaryIngredient()],
            );
            final runner = LegacyScoringRecoveryLifecycleRunner(
              dataSource: dataSource,
            );

            final summary = await runner.runForProductIds(
              dryRun: true,
              productIds: [product.id],
            );

            final result = summary.results.single;
            expect(
              result.outcome,
              LegacyScoringRecoveryOutcome.existingEvidenceAuditUnavailable,
            );
            expect(
              result.outcome,
              isNot(LegacyScoringRecoveryOutcome.auditRepairable),
            );
            expect(result.wouldApply, isFalse);
            expect(
              result.blockerReasons,
              contains('nutrition:unknownNutritionBasis'),
              reason: 'an untrusted-provenance basis must fail readiness '
                  'even though the stored enum says per100g',
            );
            expect(
              classifyFinalState(result),
              ScoringFinalState.blockedInsufficientEvidence,
            );
            expect(dataSource.writeScoringEvidenceCalls, 0);
            expect(dataSource.insertSnapshotCalls, 0);
          },
        );

        test(
          'B: databaseImport basis provenance -> the same fail-closed '
          'result as missing provenance',
          () async {
            final product = basisProvenanceProduct(
              provenance: EvidenceProvenance.databaseImport,
              id: 'trust-b-databaseimport',
            );
            final dataSource = _FakeRecoveryDataSource(
              products: {product.id: product},
              staging: const {},
              catalogue: [auditOrdinaryIngredient()],
            );
            final runner = LegacyScoringRecoveryLifecycleRunner(
              dataSource: dataSource,
            );

            final summary = await runner.runForProductIds(
              dryRun: true,
              productIds: [product.id],
            );

            final result = summary.results.single;
            expect(
              result.outcome,
              LegacyScoringRecoveryOutcome.existingEvidenceAuditUnavailable,
            );
            expect(result.wouldApply, isFalse);
            expect(
              result.blockerReasons,
              contains('nutrition:unknownNutritionBasis'),
              reason: 'databaseImport is exactly the historical '
                  '_basisForCategory-invented signature — never trusted, '
                  'even though it is a "known" provenance value',
            );
            expect(
              classifyFinalState(result),
              ScoringFinalState.blockedInsufficientEvidence,
            );
          },
        );

        test(
          'C: declaredLabel basis provenance, otherwise fully ready, audit '
          'missing -> auditRepairable',
          () async {
            final product = basisProvenanceProduct(
              provenance: EvidenceProvenance.declaredLabel,
              id: 'trust-c-declaredlabel',
            );
            final dataSource = _FakeRecoveryDataSource(
              products: {product.id: product},
              staging: const {},
              catalogue: [auditOrdinaryIngredient()],
            );
            final runner = LegacyScoringRecoveryLifecycleRunner(
              dataSource: dataSource,
            );

            final summary = await runner.runForProductIds(
              dryRun: true,
              productIds: [product.id],
            );

            final result = summary.results.single;
            expect(result.outcome, LegacyScoringRecoveryOutcome.auditRepairable);
            expect(result.wouldApply, isTrue);
          },
        );

        test(
          'D: per100ml basis, adminVerified provenance (beverage category), '
          'otherwise fully ready, audit missing -> auditRepairable',
          () async {
            final product = basisProvenanceProduct(
              provenance: EvidenceProvenance.adminVerified,
              id: 'trust-d-adminverified',
              category: ScoringCategory.beverage,
            );
            expect(
              product.scoringEvidence!.nutritionBasis,
              NutritionBasis.per100ml,
              reason: 'beverage category resolves per100ml by fixture '
                  'default — see completeInput()',
            );
            final dataSource = _FakeRecoveryDataSource(
              products: {product.id: product},
              staging: const {},
              catalogue: [auditOrdinaryIngredient()],
            );
            final runner = LegacyScoringRecoveryLifecycleRunner(
              dataSource: dataSource,
            );

            final summary = await runner.runForProductIds(
              dryRun: true,
              productIds: [product.id],
            );

            final result = summary.results.single;
            expect(result.outcome, LegacyScoringRecoveryOutcome.auditRepairable);
            expect(result.wouldApply, isTrue);
          },
        );

        test(
          'E: a HISTORICAL audit predating this correction (missing basis '
          'provenance, immutable, never deleted) sitting in the data '
          'source does not block repair once CURRENT evidence has trusted '
          'declaredLabel basis — never unnecessarily blocked just because '
          'the historical audit itself is old',
          () async {
            const id = 'trust-e-current-trusted';
            final product = basisProvenanceProduct(
              provenance: EvidenceProvenance.declaredLabel,
              id: id,
            );
            final historicalAudit =
                buildHistoricalAuditSnapshotWithBasisProvenance(null, id: id);
            final dataSource = _FakeRecoveryDataSource(
              products: {product.id: product},
              staging: const {},
              catalogue: [auditOrdinaryIngredient()],
              audits: [historicalAudit],
            );
            final runner = LegacyScoringRecoveryLifecycleRunner(
              dataSource: dataSource,
            );

            final summary = await runner.runForProductIds(
              dryRun: true,
              productIds: [product.id],
            );

            final result = summary.results.single;
            expect(result.outcome, LegacyScoringRecoveryOutcome.auditRepairable);
            expect(result.wouldApply, isTrue);
          },
        );

        test(
          'F: a historical audit AND the underlying CURRENT evidence are '
          'both untrusted -> blocked insufficient evidence, never audit '
          'repair, regardless of what historical audit rows exist',
          () async {
            const id = 'trust-f-both-untrusted';
            final product = basisProvenanceProduct(provenance: null, id: id);
            final historicalAudit =
                buildHistoricalAuditSnapshotWithBasisProvenance(null, id: id);
            final dataSource = _FakeRecoveryDataSource(
              products: {product.id: product},
              staging: const {},
              catalogue: [auditOrdinaryIngredient()],
              audits: [historicalAudit],
            );
            final runner = LegacyScoringRecoveryLifecycleRunner(
              dataSource: dataSource,
            );

            final summary = await runner.runForProductIds(
              dryRun: true,
              productIds: [product.id],
            );

            final result = summary.results.single;
            expect(
              result.outcome,
              LegacyScoringRecoveryOutcome.existingEvidenceAuditUnavailable,
            );
            expect(
              result.outcome,
              isNot(LegacyScoringRecoveryOutcome.auditRepairable),
            );
            expect(result.wouldApply, isFalse);
          },
        );

        // G) a generic current Migros `100 g / ml` fresh source remaining
        // insufficient to upgrade legacy exact-unit provenance is basis
        // REVALIDATION behavior (HistoricalBasisRevalidationService), not
        // this lifecycle boundary — already covered, unmodified and still
        // passing, by historical_basis_revalidation_service_test.dart's
        // "generic current source header -> still ambiguous" group
        // ('per_100_generic never becomes a success',
        // 'the historical bare per_100 string is also still ambiguous').
      },
    );

    test(
      'dry-run for a product with genuinely NOT-ready existing evidence reports existingEvidenceAuditUnavailable',
      () async {
        // Evidence exists but is missing required fields (fiber) — the
        // ProductScoreAuditEvaluator cannot build a snapshot from it at
        // all, which is a real readiness gap, not a repairable audit gap.
        final incompleteEvidence = ScoringEvidenceSnapshot(
          nutritionBasis: NutritionBasis.per100g,
          nutritionProductState: NutritionProductState.asSold,
          nutrition: completeNutrition(includeFiber: false),
          fvlEvidence: const CompositionPercentageEvidence.provenAbsent(
            provenance: EvidenceProvenance.declaredLabel,
            verification: EvidenceVerification.verified,
          ),
          nnsEvidence: const PresenceEvidence.absent(
            provenance: EvidenceProvenance.declaredLabel,
            verification: EvidenceVerification.verified,
          ),
          ingredientEvidenceCompleteness:
              IngredientEvidenceCompleteness.complete,
          categoryEvidence: explicitCategory(ScoringCategory.generalFood),
        );
        final product = auditProductFromInput(
          incompleteEvidence.toScoringInput(),
          id: 'evidenced-not-ready-dry-run',
          ingredientsText: 'Su',
        );
        final productWithEvidence = _copyProduct(
          product,
          scoringEvidence: incompleteEvidence,
        );
        final dataSource = _FakeRecoveryDataSource(
          products: {productWithEvidence.id: productWithEvidence},
          staging: const {},
          catalogue: [auditOrdinaryIngredient()],
        );
        final runner = LegacyScoringRecoveryLifecycleRunner(
          dataSource: dataSource,
        );

        final summary = await runner.runForProductIds(
          dryRun: true,
          productIds: [productWithEvidence.id],
        );

        expect(summary.results.single.dryRun, isTrue);
        expect(
          summary.results.single.outcome,
          LegacyScoringRecoveryOutcome.existingEvidenceAuditUnavailable,
        );
        expect(dataSource.writeScoringEvidenceCalls, 0);
        expect(dataSource.insertSnapshotCalls, 0);
      },
    );
  });

  group(
    'Section 8: existing evidence upgrade from current trusted source data',
    () {
      // Same shape as the "genuinely NOT-ready" test above (missing fiber),
      // but this time a full, matching staging row IS available — proving
      // the product is not permanently stuck just because it already has
      // some (incomplete) evidence on file.
      ScoringEvidenceSnapshot buildIncompleteEvidence() =>
          ScoringEvidenceSnapshot(
            nutritionBasis: NutritionBasis.per100g,
            nutritionProductState: NutritionProductState.asSold,
            nutrition: completeNutrition(includeFiber: false),
            fvlEvidence: const CompositionPercentageEvidence.provenAbsent(
              provenance: EvidenceProvenance.declaredLabel,
              verification: EvidenceVerification.verified,
            ),
            nnsEvidence: const PresenceEvidence.absent(
              provenance: EvidenceProvenance.declaredLabel,
              verification: EvidenceVerification.verified,
            ),
            ingredientEvidenceCompleteness:
                IngredientEvidenceCompleteness.complete,
            categoryEvidence: explicitCategory(ScoringCategory.generalFood),
          );

      test(
        'dry-run reports existingEvidenceUpgradable when fresh recovery from '
        'current staging data would now succeed',
        () async {
          final product = _copyProduct(
            _product(),
            scoringEvidence: buildIncompleteEvidence(),
          );
          final dataSource = _FakeRecoveryDataSource(
            products: {product.id: product},
            staging: {
              product.sourceUrl!: [_staging(product: product)],
            },
            catalogue: const [],
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
            LegacyScoringRecoveryOutcome.existingEvidenceUpgradable,
          );
          expect(dataSource.writeScoringEvidenceCalls, 0);
          expect(dataSource.insertSnapshotCalls, 0);
        },
      );

      test(
        'apply performs the upgrade, writes new evidence, inserts a new '
        'current audit snapshot, and reports existingEvidenceUpgraded',
        () async {
          final incompleteEvidence = buildIncompleteEvidence();
          final product = _copyProduct(
            _product(),
            scoringEvidence: incompleteEvidence,
          );
          final dataSource = _FakeRecoveryDataSource(
            products: {product.id: product},
            staging: {
              product.sourceUrl!: [_staging(product: product)],
            },
            catalogue: const [],
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
            LegacyScoringRecoveryOutcome.existingEvidenceUpgraded,
          );
          expect(dataSource.writeScoringEvidenceCalls, 1);
          expect(dataSource.insertSnapshotCalls, 1);
          final storedEvidence = dataSource.products[product.id]!.scoringEvidence!;
          expect(
            storedEvidence.nutrition.fiber.value,
            isNotNull,
            reason: 'the new evidence must actually be more complete than '
                'the old evidence it replaced',
          );
          expect(
            jsonEncode(storedEvidence.toJson()),
            isNot(jsonEncode(incompleteEvidence.toJson())),
          );
        },
      );

      test(
        'a second apply run afterward is idempotent — reports alreadyCurrent, '
        'never upgrades a second time, and performs zero further writes',
        () async {
          final product = _copyProduct(
            _product(),
            scoringEvidence: buildIncompleteEvidence(),
          );
          final dataSource = _FakeRecoveryDataSource(
            products: {product.id: product},
            staging: {
              product.sourceUrl!: [_staging(product: product)],
            },
            catalogue: const [],
          );
          final runner = LegacyScoringRecoveryLifecycleRunner(
            dataSource: dataSource,
          );

          final first = await runner.runForProductIds(
            dryRun: false,
            productIds: [product.id],
          );
          expect(
            first.results.single.outcome,
            LegacyScoringRecoveryOutcome.existingEvidenceUpgraded,
          );

          final second = await runner.runForProductIds(
            dryRun: false,
            productIds: [product.id],
          );

          expect(
            second.results.single.outcome,
            LegacyScoringRecoveryOutcome.alreadyCurrent,
          );
          expect(dataSource.writeScoringEvidenceCalls, 1, reason: 'unchanged from the first run');
          expect(dataSource.insertSnapshotCalls, 1, reason: 'unchanged from the first run');
        },
      );

      test(
        'admin-verified existing evidence is NEVER upgraded, even when '
        'staging data would otherwise support it',
        () async {
          final adminEvidence = ScoringEvidenceSnapshot(
            nutritionBasis: NutritionBasis.per100g,
            nutritionProductState: NutritionProductState.asSold,
            nutrition: completeNutrition(includeFiber: false),
            fvlEvidence: const CompositionPercentageEvidence.provenAbsent(
              provenance: EvidenceProvenance.declaredLabel,
              verification: EvidenceVerification.verified,
            ),
            nnsEvidence: const PresenceEvidence.absent(
              provenance: EvidenceProvenance.declaredLabel,
              verification: EvidenceVerification.verified,
            ),
            ingredientEvidenceCompleteness:
                IngredientEvidenceCompleteness.complete,
            categoryEvidence: explicitCategory(ScoringCategory.generalFood),
            adminVerification: ScoringEvidenceAdminMetadata(
              verifiedBy: 'admin-1',
              verifiedAt: DateTime.utc(2026, 1, 1),
              note: 'manually verified, incomplete by design',
            ),
          );
          final product = _copyProduct(
            _product(),
            scoringEvidence: adminEvidence,
          );
          final dataSource = _FakeRecoveryDataSource(
            products: {product.id: product},
            staging: {
              product.sourceUrl!: [_staging(product: product)],
            },
            catalogue: const [],
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
            LegacyScoringRecoveryOutcome.existingEvidenceAuditUnavailable,
          );
          expect(dataSource.writeScoringEvidenceCalls, 0);
          expect(dataSource.insertSnapshotCalls, 0);
          final storedEvidence = dataSource.products[product.id]!.scoringEvidence!;
          expect(storedEvidence.adminVerification?.verifiedBy, 'admin-1');
          expect(
            jsonEncode(storedEvidence.toJson()),
            jsonEncode(adminEvidence.toJson()),
            reason: 'admin-verified evidence must be byte-for-byte unchanged',
          );
        },
      );
    },
  );

  group(
    'audit repair (apply, existing score-ready evidence, no current audit)',
    () {
      Product buildRepairableProduct(String id) {
        final input = completeInput();
        return auditProductFromInput(input, id: id, ingredientsText: 'Su');
      }

      test(
        'apply inserts the missing current snapshot without touching evidence, reporting auditRepairedCurrent',
        () async {
          final product = buildRepairableProduct('repair-me-0001');
          final dataSource = _FakeRecoveryDataSource(
            products: {product.id: product},
            staging: const {},
            catalogue: [auditOrdinaryIngredient()],
            // No audits recorded — the missing/stale audit to be repaired.
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
            LegacyScoringRecoveryOutcome.auditRepairedCurrent,
          );
          expect(
            dataSource.writeScoringEvidenceCalls,
            0,
            reason: 'the identity evidence resolver must never write evidence',
          );
          expect(dataSource.insertSnapshotCalls, 1);
          expect(dataSource.audits, hasLength(1));
          expect(
            jsonEncode(
              dataSource.products[product.id]!.scoringEvidence!.toJson(),
            ),
            jsonEncode(product.scoringEvidence!.toJson()),
            reason: 'evidence must remain byte-for-byte unchanged after repair',
          );
        },
      );

      test(
        'repeating apply is idempotent: second run reports alreadyCurrent, zero further writes',
        () async {
          final product = buildRepairableProduct('repair-me-idempotent');
          final dataSource = _FakeRecoveryDataSource(
            products: {product.id: product},
            staging: const {},
            catalogue: [auditOrdinaryIngredient()],
          );
          final runner = LegacyScoringRecoveryLifecycleRunner(
            dataSource: dataSource,
          );

          final first = await runner.runForProductIds(
            dryRun: false,
            productIds: [product.id],
          );
          expect(
            first.results.single.outcome,
            LegacyScoringRecoveryOutcome.auditRepairedCurrent,
          );

          final second = await runner.runForProductIds(
            dryRun: false,
            productIds: [product.id],
          );
          expect(
            second.results.single.outcome,
            LegacyScoringRecoveryOutcome.alreadyCurrent,
          );
          expect(dataSource.writeScoringEvidenceCalls, 0);
          expect(
            dataSource.insertSnapshotCalls,
            1,
            reason: 'no duplicate current audit snapshot on the second run',
          );
          expect(dataSource.audits, hasLength(1));
        },
      );

      test(
        'admin-verified evidence metadata survives an audit repair untouched',
        () async {
          final input = completeInput();
          final baseProduct = auditProductFromInput(
            input,
            id: 'repair-admin-verified',
            ingredientsText: 'Su',
          );
          final adminEvidence = ScoringEvidenceSnapshot(
            nutritionBasis: baseProduct.scoringEvidence!.nutritionBasis,
            // Basis remediation Section E: an admin-verified evidence
            // object's basis provenance must itself say adminVerified —
            // the public gate now checks this field specifically, not
            // merely whether whole-snapshot adminVerification is present.
            nutritionBasisEvidence: EvidenceValue<NutritionBasis>(
              value: baseProduct.scoringEvidence!.nutritionBasis,
              provenance: EvidenceProvenance.adminVerified,
              verification: EvidenceVerification.verified,
            ),
            nutritionProductState:
                baseProduct.scoringEvidence!.nutritionProductState,
            nutrition: baseProduct.scoringEvidence!.nutrition,
            fvlEvidence: baseProduct.scoringEvidence!.fvlEvidence,
            nnsEvidence: baseProduct.scoringEvidence!.nnsEvidence,
            ingredientEvidenceCompleteness:
                baseProduct.scoringEvidence!.ingredientEvidenceCompleteness,
            categoryEvidence: baseProduct.scoringEvidence!.categoryEvidence,
            adminVerification: ScoringEvidenceAdminMetadata(
              verifiedBy: 'admin-1',
              verifiedAt: DateTime.utc(2026, 1, 1),
              note: 'manually verified by admin',
            ),
          );
          final product = _copyProduct(
            baseProduct,
            scoringEvidence: adminEvidence,
          );
          final dataSource = _FakeRecoveryDataSource(
            products: {product.id: product},
            staging: const {},
            catalogue: [auditOrdinaryIngredient()],
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
            LegacyScoringRecoveryOutcome.auditRepairedCurrent,
          );
          expect(dataSource.writeScoringEvidenceCalls, 0);
          final stored = dataSource.products[product.id]!.scoringEvidence!;
          expect(stored.adminVerification?.verifiedBy, 'admin-1');
          expect(stored.adminVerification?.note, 'manually verified by admin');
        },
      );
    },
  );

  group('whole-catalogue closure (runFullCatalogueClosure)', () {
    test(
      'covers products regardless of scoring_evidence nullness in one pass',
      () async {
        final neverRecoveredNoEvidence = _product(
          id: 'closure-never-recovered',
        );
        final alreadyEvidenced = auditProductFromInput(
          completeInput(),
          id: 'closure-needs-repair',
          ingredientsText: 'Su',
        );
        final dataSource = _FakeRecoveryDataSource(
          products: {
            neverRecoveredNoEvidence.id: neverRecoveredNoEvidence,
            alreadyEvidenced.id: alreadyEvidenced,
          },
          staging: {
            neverRecoveredNoEvidence.sourceUrl!: [
              _staging(product: neverRecoveredNoEvidence),
            ],
          },
          catalogue: [auditOrdinaryIngredient()],
        );
        final runner = LegacyScoringRecoveryLifecycleRunner(
          dataSource: dataSource,
        );

        final summary = await runner.runFullCatalogueClosure(
          dryRun: false,
          limit: 10,
        );

        expect(summary.totalExamined, 2);
        expect(dataSource.fetchCataloguePageCalls, isNotEmpty);
        expect(
          dataSource.fetchRecoveryCandidatesCalls,
          isEmpty,
          reason:
              'the whole-catalogue pass must never use the '
              'scoring_evidence-IS-NULL-only candidate query',
        );
        final outcomes = {
          for (final result in summary.results)
            result.productId: result.outcome,
        };
        expect(
          outcomes[neverRecoveredNoEvidence.id],
          LegacyScoringRecoveryOutcome.recoveredAndCurrent,
        );
        expect(
          outcomes[alreadyEvidenced.id],
          LegacyScoringRecoveryOutcome.auditRepairedCurrent,
        );
      },
    );
  });

  group('category grouping and closure postcondition (pure functions)', () {
    LegacyScoringRecoveryProductResult result({
      required String id,
      required LegacyScoringRecoveryOutcome outcome,
      ScoringCategory? category,
    }) => LegacyScoringRecoveryProductResult(
      productId: id,
      productName: id,
      dryRun: false,
      outcome: outcome,
      blockerReasons: const [],
      resolvedCategory: category,
    );

    test(
      'groupResultsByCategory buckets by resolved category, including unknown',
      () {
        final results = [
          result(
            id: '1',
            outcome: LegacyScoringRecoveryOutcome.alreadyCurrent,
            category: ScoringCategory.generalFood,
          ),
          result(
            id: '2',
            outcome: LegacyScoringRecoveryOutcome.blocked,
            category: ScoringCategory.generalFood,
          ),
          result(
            id: '3',
            outcome: LegacyScoringRecoveryOutcome.recoveredAndCurrent,
            category: ScoringCategory.beverage,
          ),
          result(
            id: '4',
            outcome: LegacyScoringRecoveryOutcome.unexpectedError,
          ),
        ];

        final grouped = groupResultsByCategory(results);

        expect(grouped['generalFood']!.totalProducts, 2);
        expect(grouped['generalFood']!.alreadyCurrent, 1);
        expect(grouped['generalFood']!.blocked, 1);
        expect(grouped['beverage']!.totalProducts, 1);
        expect(grouped['beverage']!.recoveredAndCurrent, 1);
        expect(grouped['unknown']!.totalProducts, 1);
        expect(grouped['unknown']!.unexpectedErrors, 1);
      },
    );

    test(
      'computeClosurePostcondition is clean when nothing is stuck or erroring',
      () {
        final results = [
          result(id: '1', outcome: LegacyScoringRecoveryOutcome.alreadyCurrent),
          result(
            id: '2',
            outcome: LegacyScoringRecoveryOutcome.recoveredAndCurrent,
          ),
          result(
            id: '3',
            outcome: LegacyScoringRecoveryOutcome.auditRepairedCurrent,
          ),
          result(id: '4', outcome: LegacyScoringRecoveryOutcome.blocked),
        ];

        final postcondition = computeClosurePostcondition(results);

        expect(postcondition.isClean, isTrue);
        expect(postcondition.scoreableButNotCurrent, 0);
        expect(postcondition.unexpectedErrors, 0);
        expect(postcondition.currentPublicScores, 3);
        expect(postcondition.catalogueTotal, 4);
      },
    );

    test(
      'computeClosurePostcondition surfaces exact product ids when dirty',
      () {
        final results = [
          result(
            id: 'good',
            outcome: LegacyScoringRecoveryOutcome.alreadyCurrent,
          ),
          result(
            id: 'stuck',
            outcome: LegacyScoringRecoveryOutcome.auditNotCurrentAfterApply,
          ),
          result(
            id: 'broken',
            outcome: LegacyScoringRecoveryOutcome.unexpectedError,
          ),
        ];

        final postcondition = computeClosurePostcondition(results);

        expect(postcondition.isClean, isFalse);
        expect(postcondition.scoreableButNotCurrent, 1);
        expect(postcondition.scoreableButNotCurrentProductIds, ['stuck']);
        expect(postcondition.unexpectedErrors, 1);
        expect(postcondition.unexpectedErrorProductIds, ['broken']);
      },
    );

    test('auditRepairable counts as scoreable-but-not-current in dry-run: by '
        'definition the evidence is already score-ready, it just has no '
        'current audit yet', () {
      final results = [
        result(
          id: 'ready',
          outcome: LegacyScoringRecoveryOutcome.auditRepairable,
        ),
      ];

      final postcondition = computeClosurePostcondition(results);

      expect(postcondition.scoreableButNotCurrent, 1);
      expect(postcondition.scoreableButNotCurrentProductIds, ['ready']);
      expect(postcondition.isClean, isFalse);
    });

    test('reproduces the exact reported production accounting gap: '
        'already_current + audit_repairable + blocked + '
        'existing_evidence_audit_unavailable == catalogue_total, and '
        'closure_clean is false because of the audit_repairable backlog', () {
      final results = [
        for (var i = 0; i < 728; i++)
          result(
            id: 'already-$i',
            outcome: LegacyScoringRecoveryOutcome.alreadyCurrent,
          ),
        for (var i = 0; i < 93; i++)
          result(
            id: 'repairable-$i',
            outcome: LegacyScoringRecoveryOutcome.auditRepairable,
          ),
        for (var i = 0; i < 4958; i++)
          result(
            id: 'blocked-$i',
            outcome: LegacyScoringRecoveryOutcome.blocked,
          ),
        // The missing 80: existing, non-null scoring_evidence that is
        // itself not (or no longer) score-ready — a real, distinct,
        // previously-unprinted outcome in the dry-run [summary].
        for (var i = 0; i < 80; i++)
          result(
            id: 'evidence-not-ready-$i',
            outcome:
                LegacyScoringRecoveryOutcome.existingEvidenceAuditUnavailable,
          ),
      ];
      expect(results, hasLength(5859));

      final postcondition = computeClosurePostcondition(results);

      expect(postcondition.catalogueTotal, 5859);
      expect(postcondition.currentPublicScores, 728);
      expect(
        postcondition.scoreableButNotCurrent,
        93,
        reason: 'exactly the audit_repairable count in dry-run',
      );
      expect(postcondition.isClean, isFalse);
      expect(postcondition.unexpectedErrors, 0);
    });

    test('LegacyScoringRecoveryBatchSummary.outcomeCountsSum equals '
        'totalExamined for a realistic mixed-outcome dry-run batch', () {
      final summary = LegacyScoringRecoveryBatchSummary(
        dryRun: true,
        safeResumeCursor: null,
      );
      final mixedResults = [
        result(id: 'a', outcome: LegacyScoringRecoveryOutcome.alreadyCurrent),
        result(id: 'b', outcome: LegacyScoringRecoveryOutcome.auditRepairable),
        result(id: 'c', outcome: LegacyScoringRecoveryOutcome.blocked),
        result(
          id: 'd',
          outcome:
              LegacyScoringRecoveryOutcome.existingEvidenceAuditUnavailable,
        ),
        result(id: 'e', outcome: LegacyScoringRecoveryOutcome.recoverable),
        result(id: 'f', outcome: LegacyScoringRecoveryOutcome.unexpectedError),
      ];
      for (final r in mixedResults) {
        summary.totalExamined++;
        summary.record(r);
      }

      expect(summary.outcomeCountsSum, summary.totalExamined);
      expect(summary.outcomeCountsAreConsistent, isTrue);
    });

    test('category breakdown uses the same mutually-exclusive outcome '
        'semantics as the global summary: category-level blocked never '
        'silently absorbs audit_repairable or '
        'existing_evidence_audit_unavailable', () {
      final results = [
        result(
          id: '1',
          outcome: LegacyScoringRecoveryOutcome.blocked,
          category: ScoringCategory.generalFood,
        ),
        result(
          id: '2',
          outcome: LegacyScoringRecoveryOutcome.auditRepairable,
          category: ScoringCategory.generalFood,
        ),
        result(
          id: '3',
          outcome:
              LegacyScoringRecoveryOutcome.existingEvidenceAuditUnavailable,
          category: ScoringCategory.generalFood,
        ),
      ];

      final grouped = groupResultsByCategory(results);
      final stats = grouped['generalFood']!;

      expect(
        stats.blocked,
        1,
        reason: 'must count only outcome==blocked, not the other two',
      );
      expect(stats.auditRepairable, 1);
      expect(stats.existingEvidenceAuditUnavailable, 1);
      expect(stats.outcomeCountsSum, stats.totalProducts);
      expect(stats.outcomeCountsAreConsistent, isTrue);

      // Summing this category's per-outcome fields must reproduce what a
      // global summary would report for the same results — the exact
      // property that was broken (category blocked=5131 vs global
      // blocked=4958 in the reported production run).
      final globalSummary = LegacyScoringRecoveryBatchSummary(
        dryRun: true,
        safeResumeCursor: null,
      );
      for (final r in results) {
        globalSummary.totalExamined++;
        globalSummary.record(r);
      }
      expect(stats.blocked, globalSummary.blocked);
      expect(stats.auditRepairable, globalSummary.auditRepairable);
      expect(
        stats.existingEvidenceAuditUnavailable,
        globalSummary.existingEvidenceAuditUnavailable,
      );
    });
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
          staging: {
            product.sourceUrl!: [_staging()],
          },
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
          staging: {
            product.sourceUrl!: [_staging()],
          },
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
          staging: {
            exact.sourceUrl!: [_staging(product: exact)],
          },
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
        staging: {
          for (final p in products) p.sourceUrl!: [_staging(product: p)],
        },
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
      expect(
        dataSource.fetchRecoveryCandidatesCalls.every((c) => c.limit <= 2),
        isTrue,
      );
    });

    test(
      '--source resumes strictly after the supplied start-after cursor',
      () async {
        final products = List.generate(5, (i) => _product(id: '0${i + 1}00'));
        final dataSource = _FakeRecoveryDataSource(
          products: {for (final p in products) p.id: p},
          staging: {
            for (final p in products) p.sourceUrl!: [_staging(product: p)],
          },
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
        expect(summary.results.map((r) => r.productId), [
          '0300',
          '0400',
          '0500',
        ]);
      },
    );

    test('17. --product-id targeted mode never scans the catalogue', () async {
      final product = _product();
      final dataSource = _FakeRecoveryDataSource(
        products: {product.id: product},
        staging: {
          product.sourceUrl!: [_staging()],
        },
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

      expect(
        summary.results[0].outcome,
        LegacyScoringRecoveryOutcome.unexpectedError,
      );
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

    test(
      'C. evidence is scoring-ready but current matching audit unavailable',
      () {
        final state = mapper.auditSnapshotRequired();

        expect(
          state.unavailableStage,
          ProductEtiketlyScoreUnavailableStage.auditNotCurrent,
        );
        expect(state.message, 'Puan kaydı güncelleniyor.');
        expect(state.displayScore, isNull);
      },
    );

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
        final auditEvaluation = await evaluator.evaluate(product, [
          auditOrdinaryIngredient(),
        ]);
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

  group(
    'Section 12: source-neutral lifecycle (synthetic future-adapter fixtures)',
    () {
      // Deliberately NOT scraping a101/bim — these are synthetic fixtures
      // proving the scoring lifecycle is source-neutral by construction
      // (the only place a "source" string is ever inspected anywhere in
      // this pipeline is _isWebScraperSource()'s prefix check), not that
      // any real integration with these retailers exists.
      Product syntheticSourceProduct(String source, String id) {
        final now = DateTime.utc(2026, 8, 8);
        return Product(
          id: id,
          barcode: '869000000$id',
          name: 'Synthetic $source product',
          ingredientsText: 'mısır unu, bitkisel yağ, tuz',
          nutritionText: jsonEncode(_nutrition()),
          source: source,
          sourceUrl: 'https://example-$source.test/product-$id',
          verificationStatus: 'imported',
          categoryTags: const ['cips_kraker'],
          createdAt: now,
          updatedAt: now,
        );
      }

      LegacyStagingScoringEvidence syntheticStaging(Product product) {
        return LegacyStagingScoringEvidence(
          id: '${product.id}-staging',
          sourceUrl: product.sourceUrl!,
          // A future adapter proving the distinct unit — see the basis
          // independence fix — is exactly the "forward-compatible" case
          // this string models, unlike the real (unit-ambiguous) Migros
          // contract's generic 'per_100'.
          nutritionBasis: 'per_100g',
          source: product.source,
          ingredientsSource: product.source,
          ingredientsRaw: 'İçindekiler: ${product.ingredientsText}',
          ingredientsText: product.ingredientsText,
          ingredientsQuality: 'ingredients_ok',
          nutritionSource: product.source,
          nutritionStrategy: 'dom',
          nutritionJson: _nutrition(),
        );
      }

      test(
        'a generic A101-like trusted source (web_scraper:a101) reaches the '
        'central lifecycle and produces a current audit snapshot, with no '
        'retailer-specific code path involved',
        () async {
          final product = syntheticSourceProduct('web_scraper:a101', 'a101-1');
          final dataSource = _FakeRecoveryDataSource(
            products: {product.id: product},
            staging: {
              product.sourceUrl!: [syntheticStaging(product)],
            },
            catalogue: const [],
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
          expect(dataSource.insertSnapshotCalls, 1);
        },
      );

      test(
        'a generic BIM-like trusted source (web_scraper:bim) reaches the '
        'central lifecycle and produces a current audit snapshot',
        () async {
          final product = syntheticSourceProduct('web_scraper:bim', 'bim-1');
          final dataSource = _FakeRecoveryDataSource(
            products: {product.id: product},
            staging: {
              product.sourceUrl!: [syntheticStaging(product)],
            },
            catalogue: const [],
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
          expect(dataSource.insertSnapshotCalls, 1);
        },
      );

      test(
        'identical trusted input produces the identical calculated score '
        'regardless of which retailer source it came from — no '
        'retailer-specific scoring formula exists',
        () async {
          final a101 = syntheticSourceProduct('web_scraper:a101', 'a101-2');
          final bim = syntheticSourceProduct('web_scraper:bim', 'bim-2');
          final migros = _product(id: 'migros-2');
          final dataSource = _FakeRecoveryDataSource(
            products: {
              a101.id: a101,
              bim.id: bim,
              migros.id: migros,
            },
            staging: {
              a101.sourceUrl!: [syntheticStaging(a101)],
              bim.sourceUrl!: [syntheticStaging(bim)],
              migros.sourceUrl!: [_staging(product: migros)],
            },
            catalogue: const [],
          );
          final runner = LegacyScoringRecoveryLifecycleRunner(
            dataSource: dataSource,
          );

          final summary = await runner.runForProductIds(
            dryRun: false,
            productIds: [a101.id, bim.id, migros.id],
          );

          final scores = {
            for (final result in summary.results)
              result.productId: result.calculatedScore,
          };
          expect(scores[a101.id], isNotNull);
          expect(scores[bim.id], scores[a101.id]);
          expect(scores[migros.id], scores[a101.id]);
        },
      );
    },
  );
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

class _FetchCataloguePageCall {
  const _FetchCataloguePageCall({
    required this.afterProductId,
    required this.limit,
  });

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

  final List<_FetchCataloguePageCall> fetchCataloguePageCalls = [];

  @override
  Future<List<Product>> fetchCataloguePage({
    required String? afterProductId,
    required int limit,
  }) async {
    fetchCataloguePageCalls.add(
      _FetchCataloguePageCall(afterProductId: afterProductId, limit: limit),
    );
    final ordered = products.values.toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    final afterIndex = afterProductId == null
        ? -1
        : ordered.indexWhere((p) => p.id == afterProductId);
    return ordered.skip(afterIndex + 1).take(limit).toList(growable: false);
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
      final nutrition = Map<String, dynamic>.from(mutable['nutrition'] as Map);
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

// Basis independence correction: 'per_100' (the ONLY value the real
// historical Migros scraper contract ever produces) never distinguishes g
// from ml and now correctly resolves to NutritionBasis.unknown, not a
// category-invented value (see _recoveredBasisFromEvidence in
// legacy_scoring_evidence_recovery.dart). Most tests in this file are
// about the LIFECYCLE (dedup, cursor, idempotency, error isolation, audit
// repair) rather than basis itself, so they need a fixture with genuinely
// PROVEN basis evidence to exercise what they actually test — 'per_100g'
// is the forward-compatible, explicitly supported distinct-unit string.
LegacyStagingScoringEvidence _staging({
  String id = 'staging-1',
  String? basis = 'per_100g',
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
