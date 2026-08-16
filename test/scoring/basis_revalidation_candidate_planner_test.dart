import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/scoring/application/basis_revalidation_candidate_planner.dart';
import 'package:food_analyzer_app/features/scoring/application/legacy_scoring_recovery_lifecycle_runner.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/composition_percentage_evidence.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/evidence_value.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/presence_evidence.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_category_evidence.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_evidence_snapshot.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';

void main() {
  final now = DateTime.utc(2026, 8, 16);

  LegacyScoringRecoveryProductResult result({
    required String id,
    required LegacyScoringRecoveryOutcome outcome,
    List<String> blockerReasons = const [],
    ScoringCategory? category,
  }) {
    return LegacyScoringRecoveryProductResult(
      productId: id,
      productName: id,
      dryRun: true,
      outcome: outcome,
      blockerReasons: blockerReasons,
      resolvedCategory: category,
    );
  }

  Product currentProduct({required String id, EvidenceProvenance? basisProvenance}) {
    return Product(
      id: id,
      name: id,
      verificationStatus: 'imported',
      scoringEvidence: ScoringEvidenceSnapshot(
        nutritionBasis: NutritionBasis.per100g,
        nutritionBasisEvidence: basisProvenance == null
            ? null
            : EvidenceValue<NutritionBasis>(
                value: NutritionBasis.per100g,
                provenance: basisProvenance,
                verification: EvidenceVerification.verified,
              ),
        nutritionProductState: NutritionProductState.asSold,
        fvlEvidence: const CompositionPercentageEvidence.provenAbsent(
          provenance: EvidenceProvenance.declaredLabel,
          verification: EvidenceVerification.verified,
        ),
        nnsEvidence: const PresenceEvidence.absent(
          provenance: EvidenceProvenance.declaredLabel,
          verification: EvidenceVerification.verified,
        ),
        ingredientEvidenceCompleteness: IngredientEvidenceCompleteness.complete,
        categoryEvidence: ScoringCategoryEvidence(
          resolvedCategory: ScoringCategory.generalFood,
          source: CategoryEvidenceSource.explicitScoringMetadata,
        ),
      ),
      createdAt: now,
      updatedAt: now,
    );
  }

  group('priority 1: current public score with unverified basis provenance', () {
    test('databaseImport provenance (legacy-invented signature) is a candidate', () {
      final results = [
        result(id: 'p1', outcome: LegacyScoringRecoveryOutcome.alreadyCurrent),
      ];
      final products = {
        'p1': currentProduct(id: 'p1', basisProvenance: EvidenceProvenance.databaseImport),
      };

      final candidates = planBasisRevalidationCandidates(
        closureResults: results,
        productsById: products,
      );

      expect(candidates, hasLength(1));
      expect(
        candidates.single.reason,
        BasisRevalidationCandidateReason.currentPublicBasisUnverified,
      );
    });

    test('missing provenance entirely (pre-remediation snapshot) is a candidate', () {
      final results = [
        result(id: 'p1', outcome: LegacyScoringRecoveryOutcome.recoveredAndCurrent),
      ];
      final products = {'p1': currentProduct(id: 'p1', basisProvenance: null)};

      final candidates = planBasisRevalidationCandidates(
        closureResults: results,
        productsById: products,
      );

      expect(candidates, hasLength(1));
    });

    test('declaredLabel provenance (genuinely proven) is NOT a candidate', () {
      final results = [
        result(id: 'p1', outcome: LegacyScoringRecoveryOutcome.auditRepairedCurrent),
      ];
      final products = {
        'p1': currentProduct(id: 'p1', basisProvenance: EvidenceProvenance.declaredLabel),
      };

      final candidates = planBasisRevalidationCandidates(
        closureResults: results,
        productsById: products,
      );

      expect(candidates, isEmpty);
    });

    test('adminVerified provenance is NOT a candidate', () {
      final results = [
        result(id: 'p1', outcome: LegacyScoringRecoveryOutcome.alreadyCurrent),
      ];
      final products = {
        'p1': currentProduct(id: 'p1', basisProvenance: EvidenceProvenance.adminVerified),
      };

      final candidates = planBasisRevalidationCandidates(
        closureResults: results,
        productsById: products,
      );

      expect(candidates, isEmpty);
    });
  });

  group(
    'priority 1 (circular-dependency fix): current_public_basis_unverified '
    'blocker token, as emitted by the lifecycle runner\'s dry-run path',
    () {
      test(
        'auditRepairable with the current_public_basis_unverified blocker '
        'is Priority 1, never Priority 2/3',
        () {
          final results = [
            result(
              id: 'p1',
              outcome: LegacyScoringRecoveryOutcome.auditRepairable,
              blockerReasons: const ['current_public_basis_unverified'],
            ),
          ];

          final candidates = planBasisRevalidationCandidates(
            closureResults: results,
            productsById: const {},
          );

          expect(candidates, hasLength(1));
          expect(
            candidates.single.reason,
            BasisRevalidationCandidateReason.currentPublicBasisUnverified,
          );
        },
      );

      test(
        'auditRepairable with the plain audit_missing_or_stale blocker is '
        'NOT a candidate at all (genuinely stale/missing, not basis-only)',
        () {
          final results = [
            result(
              id: 'p1',
              outcome: LegacyScoringRecoveryOutcome.auditRepairable,
              blockerReasons: const ['audit_missing_or_stale'],
            ),
          ];

          final candidates = planBasisRevalidationCandidates(
            closureResults: results,
            productsById: const {},
          );

          expect(
            candidates,
            isEmpty,
            reason: 'a genuinely stale/missing audit is not "otherwise '
                'current except basis" — no fetch should be spent on it',
          );
        },
      );
    },
  );

  group('priority 2/3: otherwise ready except basis', () {
    test(
      'pre-APPLY trust correction: existingEvidenceAuditUnavailable '
      'blocked ONLY on nutrition:unknownNutritionBasis (an existing-'
      'evidence product whose basis provenance is untrusted) is still a '
      'candidate — the ONLY remaining issue is unproven basis, so this '
      'must not be silently dropped from candidate selection',
      () {
        final results = [
          result(
            id: 'p1',
            outcome: LegacyScoringRecoveryOutcome.existingEvidenceAuditUnavailable,
            blockerReasons: const ['nutrition:unknownNutritionBasis'],
          ),
        ];

        final candidates = planBasisRevalidationCandidates(
          closureResults: results,
          productsById: const {},
        );

        expect(candidates, hasLength(1));
        expect(
          candidates.single.reason,
          BasisRevalidationCandidateReason.otherwiseReadyExceptBasis,
        );
      },
    );

    test(
      'nutrition:unknownNutritionBasis alongside an unrelated genuine '
      'blocker is never a candidate — proving basis alone would not make '
      'it scoreable',
      () {
        final results = [
          result(
            id: 'p1',
            outcome: LegacyScoringRecoveryOutcome.existingEvidenceAuditUnavailable,
            blockerReasons: const [
              'nutrition:unknownNutritionBasis',
              'nutrition:missingFiber',
            ],
          ),
        ];

        final candidates = planBasisRevalidationCandidates(
          closureResults: results,
          productsById: const {},
        );

        expect(candidates, isEmpty);
      },
    );

    test('blocked ONLY on basis_unit_ambiguous is a candidate', () {
      final results = [
        result(
          id: 'p1',
          outcome: LegacyScoringRecoveryOutcome.blocked,
          blockerReasons: const ['basis_unit_ambiguous'],
        ),
      ];

      final candidates = planBasisRevalidationCandidates(
        closureResults: results,
        productsById: const {},
      );

      expect(candidates, hasLength(1));
      expect(
        candidates.single.reason,
        BasisRevalidationCandidateReason.otherwiseReadyExceptBasis,
      );
    });

    test(
      'blocked on basis_unit_ambiguous AND basis_generic_ambiguous_exact_unit_unproven '
      'together (the normal co-occurring pair) is still a candidate',
      () {
        final results = [
          result(
            id: 'p1',
            outcome: LegacyScoringRecoveryOutcome.blocked,
            blockerReasons: const [
              'basis_unit_ambiguous',
              'basis_generic_ambiguous_exact_unit_unproven',
            ],
          ),
        ];

        final candidates = planBasisRevalidationCandidates(
          closureResults: results,
          productsById: const {},
        );

        expect(candidates, hasLength(1));
      },
    );

    test(
      'never spends a fetch on a product blocked by unrelated genuine '
      'missing evidence, even alongside a basis blocker',
      () {
        final results = [
          result(
            id: 'p1',
            outcome: LegacyScoringRecoveryOutcome.blocked,
            blockerReasons: const ['basis_unit_ambiguous', 'missing_fiber'],
          ),
          result(
            id: 'p2',
            outcome: LegacyScoringRecoveryOutcome.blocked,
            blockerReasons: const [
              'missing_fiber',
              'canonical_additive_unresolved',
              'missing_classification',
            ],
          ),
        ];

        final candidates = planBasisRevalidationCandidates(
          closureResults: results,
          productsById: const {},
        );

        expect(
          candidates,
          isEmpty,
          reason: 'proving basis for either product would not make it '
              'scoreable — a fetch would be wasted',
        );
      },
    );

    test('recoverable/notScoreEligible/unexpectedError outcomes are never candidates', () {
      final results = [
        result(id: 'p1', outcome: LegacyScoringRecoveryOutcome.recoverable),
        result(id: 'p2', outcome: LegacyScoringRecoveryOutcome.notScoreEligible),
        result(id: 'p3', outcome: LegacyScoringRecoveryOutcome.unexpectedError),
      ];

      final candidates = planBasisRevalidationCandidates(
        closureResults: results,
        productsById: const {},
      );

      expect(candidates, isEmpty);
    });
  });

  test('planner is deterministic — same input always produces the same output', () {
    final results = [
      result(
        id: 'p1',
        outcome: LegacyScoringRecoveryOutcome.blocked,
        blockerReasons: const ['basis_unit_ambiguous'],
      ),
      result(id: 'p2', outcome: LegacyScoringRecoveryOutcome.alreadyCurrent),
    ];
    final products = {
      'p2': currentProduct(id: 'p2', basisProvenance: EvidenceProvenance.databaseImport),
    };

    final first = planBasisRevalidationCandidates(
      closureResults: results,
      productsById: products,
    );
    final second = planBasisRevalidationCandidates(
      closureResults: results,
      productsById: products,
    );

    expect(first.map((c) => c.productId), second.map((c) => c.productId));
    expect(first.map((c) => c.reason), second.map((c) => c.reason));
  });
}
