import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/scoring/application/legacy_scoring_recovery_lifecycle_runner.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';

/// Section A of the methodology/readiness correction: notScoreEligible
/// (ScoringCategory.outOfScope — food supplement / infant food / medical
/// food / sports nutrition / meal replacement) must be its own outcome,
/// never mixed into `blocked`. These tests exercise only the pure
/// reporting/accounting layer (LegacyScoringRecoveryOutcome,
/// LegacyScoringRecoveryBatchSummary, CategoryClosureStats,
/// computeClosurePostcondition) directly against synthetic results — the
/// live recovery pipeline cannot itself produce this outcome yet, since
/// ScoringClassificationFacts is hardcoded empty in
/// LegacyScoringEvidenceRecoveryService (a separate, documented finding,
/// not something this correction invents a fact-population heuristic for).
void main() {
  LegacyScoringRecoveryProductResult result({
    required String id,
    required LegacyScoringRecoveryOutcome outcome,
    ScoringCategory? category,
    List<String> blockerReasons = const [],
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

  group('LegacyScoringRecoveryBatchSummary', () {
    test('notScoreEligible is counted separately from blocked', () {
      final summary = LegacyScoringRecoveryBatchSummary(
        dryRun: true,
        safeResumeCursor: null,
      );
      summary.record(
        result(id: '1', outcome: LegacyScoringRecoveryOutcome.notScoreEligible),
      );
      summary.record(
        result(id: '2', outcome: LegacyScoringRecoveryOutcome.blocked),
      );

      expect(summary.notScoreEligible, 1);
      expect(summary.blocked, 1);
      expect(summary.outcomeCountsSum, 2);
      summary.totalExamined = 2;
      expect(summary.outcomeCountsAreConsistent, isTrue);
    });
  });

  group('computeClosurePostcondition eligibility accounting', () {
    test(
      'eligible_total excludes notScoreEligible and partitions cleanly into '
      'current/recoverable/blocked',
      () {
        final results = [
          result(
            id: 'supplement-1',
            outcome: LegacyScoringRecoveryOutcome.notScoreEligible,
          ),
          result(
            id: 'supplement-2',
            outcome: LegacyScoringRecoveryOutcome.notScoreEligible,
          ),
          result(
            id: 'current-1',
            outcome: LegacyScoringRecoveryOutcome.alreadyCurrent,
          ),
          result(
            id: 'current-2',
            outcome: LegacyScoringRecoveryOutcome.recoveredAndCurrent,
          ),
          result(
            id: 'current-3',
            outcome: LegacyScoringRecoveryOutcome.auditRepairedCurrent,
          ),
          result(
            id: 'recoverable-1',
            outcome: LegacyScoringRecoveryOutcome.recoverable,
          ),
          result(
            id: 'repairable-1',
            outcome: LegacyScoringRecoveryOutcome.auditRepairable,
          ),
          result(
            id: 'not-current-after-apply-1',
            outcome: LegacyScoringRecoveryOutcome.auditNotCurrentAfterApply,
          ),
          result(id: 'blocked-1', outcome: LegacyScoringRecoveryOutcome.blocked),
          result(
            id: 'unavailable-1',
            outcome:
                LegacyScoringRecoveryOutcome.existingEvidenceAuditUnavailable,
          ),
          result(
            id: 'error-1',
            outcome: LegacyScoringRecoveryOutcome.unexpectedError,
          ),
        ];

        final postcondition = computeClosurePostcondition(results);

        expect(postcondition.catalogueTotal, 11);
        expect(postcondition.notScoreEligible, 2);
        expect(postcondition.eligibleTotal, 9);
        expect(postcondition.eligibleCurrent, 3);
        // recoverable-1 + repairable-1 + not-current-after-apply-1
        expect(postcondition.eligibleRecoverable, 3);
        // remainder: blocked-1 + unavailable-1 + error-1
        expect(postcondition.eligibleBlocked, 3);
        expect(
          postcondition.eligibleCurrent +
              postcondition.eligibleRecoverable +
              postcondition.eligibleBlocked,
          postcondition.eligibleTotal,
          reason:
              'eligible_current + eligible_recoverable + eligible_blocked '
              'must always reconstruct eligible_total exactly',
        );
      },
    );

    test(
      'a catalogue with only notScoreEligible products has eligible_total '
      'zero, not misreported as fully blocked',
      () {
        final results = [
          result(
            id: 'supplement-1',
            outcome: LegacyScoringRecoveryOutcome.notScoreEligible,
          ),
        ];

        final postcondition = computeClosurePostcondition(results);

        expect(postcondition.catalogueTotal, 1);
        expect(postcondition.notScoreEligible, 1);
        expect(postcondition.eligibleTotal, 0);
        expect(postcondition.eligibleCurrent, 0);
        expect(postcondition.eligibleRecoverable, 0);
        expect(postcondition.eligibleBlocked, 0);
      },
    );
  });

  group('CategoryClosureStats / groupResultsByCategory', () {
    test('notScoreEligible is tracked per category and stays consistent', () {
      final results = [
        result(
          id: '1',
          outcome: LegacyScoringRecoveryOutcome.notScoreEligible,
          category: ScoringCategory.outOfScope,
        ),
        result(
          id: '2',
          outcome: LegacyScoringRecoveryOutcome.recoverable,
          category: ScoringCategory.generalFood,
        ),
      ];
      final byCategory = groupResultsByCategory(results);

      final outOfScopeStats = byCategory[ScoringCategory.outOfScope.name]!;
      expect(outOfScopeStats.notScoreEligible, 1);
      expect(outOfScopeStats.totalProducts, 1);
      expect(outOfScopeStats.outcomeCountsAreConsistent, isTrue);

      final generalFoodStats = byCategory[ScoringCategory.generalFood.name]!;
      expect(generalFoodStats.notScoreEligible, 0);
      expect(generalFoodStats.recoverable, 1);
    });
  });

  group('Section K: classifyFinalState', () {
    test('notScoreEligible outcome maps to NOT_SCORE_ELIGIBLE', () {
      expect(
        classifyFinalState(
          result(id: '1', outcome: LegacyScoringRecoveryOutcome.notScoreEligible),
        ),
        ScoringFinalState.notScoreEligible,
      );
    });

    test('the three current-producing outcomes all map to CURRENT', () {
      for (final outcome in [
        LegacyScoringRecoveryOutcome.alreadyCurrent,
        LegacyScoringRecoveryOutcome.recoveredAndCurrent,
        LegacyScoringRecoveryOutcome.auditRepairedCurrent,
      ]) {
        expect(
          classifyFinalState(result(id: outcome.name, outcome: outcome)),
          ScoringFinalState.current,
          reason: outcome.name,
        );
      }
    });

    test(
      'recoverable/auditRepairable/auditNotCurrentAfterApply all map to '
      'SCOREABLE_NOT_CURRENT',
      () {
        for (final outcome in [
          LegacyScoringRecoveryOutcome.recoverable,
          LegacyScoringRecoveryOutcome.auditRepairable,
          LegacyScoringRecoveryOutcome.auditNotCurrentAfterApply,
        ]) {
          expect(
            classifyFinalState(result(id: outcome.name, outcome: outcome)),
            ScoringFinalState.scoreableNotCurrent,
            reason: outcome.name,
          );
        }
      },
    );

    test('unexpectedError always maps to UNEXPECTED_ERROR', () {
      expect(
        classifyFinalState(
          result(id: '1', outcome: LegacyScoringRecoveryOutcome.unexpectedError),
        ),
        ScoringFinalState.unexpectedError,
      );
    });

    test(
      'blocked with only missing/unknown-evidence tokens is '
      'BLOCKED_INSUFFICIENT_EVIDENCE',
      () {
        expect(
          classifyFinalState(
            result(
              id: '1',
              outcome: LegacyScoringRecoveryOutcome.blocked,
              blockerReasons: const [
                'missing_fiber',
                'fvl_unknown',
                'ingredients_incomplete',
              ],
            ),
          ),
          ScoringFinalState.blockedInsufficientEvidence,
        );
      },
    );

    test(
      'blocked with a saturatedFatExceedsTotalFat-style token is '
      'BLOCKED_INVALID_SOURCE_DATA, even alongside insufficient-evidence '
      'tokens',
      () {
        expect(
          classifyFinalState(
            result(
              id: '1',
              outcome: LegacyScoringRecoveryOutcome.blocked,
              blockerReasons: const [
                'missing_fiber',
                'saturated_fat_exceeds_total_fat',
              ],
            ),
          ),
          ScoringFinalState.blockedInvalidSourceData,
          reason:
              'an invalid-source-data signal must dominate when both kinds '
              'of blocker are present on the same product',
        );
      },
    );

    test(
      'existingEvidenceAuditUnavailable with the audit-path nutrition: '
      'prefixed contradiction token is also BLOCKED_INVALID_SOURCE_DATA',
      () {
        expect(
          classifyFinalState(
            result(
              id: '1',
              outcome:
                  LegacyScoringRecoveryOutcome.existingEvidenceAuditUnavailable,
              blockerReasons: const ['nutrition:plainWaterCategoryMismatch'],
            ),
          ),
          ScoringFinalState.blockedInvalidSourceData,
        );
      },
    );

    test(
      'existingEvidenceAuditUnavailable with only additive incompleteness '
      'tokens is BLOCKED_INSUFFICIENT_EVIDENCE',
      () {
        expect(
          classifyFinalState(
            result(
              id: '1',
              outcome:
                  LegacyScoringRecoveryOutcome.existingEvidenceAuditUnavailable,
              blockerReasons: const [
                'nutrition:missingFiber',
                'additive:reviewRequiredAdditiveEvidence',
                'additive:additiveAssessmentIncomplete',
              ],
            ),
          ),
          ScoringFinalState.blockedInsufficientEvidence,
        );
      },
    );

    test(
      'additiveRiskConflict is the one additive: token that counts as '
      'invalid source data, not insufficient evidence',
      () {
        expect(
          classifyFinalState(
            result(
              id: '1',
              outcome: LegacyScoringRecoveryOutcome.blocked,
              blockerReasons: const ['additive:additiveRiskConflict'],
            ),
          ),
          ScoringFinalState.blockedInvalidSourceData,
        );
      },
    );
  });

  group('Section K: summarizeFinalStates', () {
    test('every result contributes to exactly one bucket, summing to total', () {
      final results = [
        result(id: '1', outcome: LegacyScoringRecoveryOutcome.notScoreEligible),
        result(id: '2', outcome: LegacyScoringRecoveryOutcome.alreadyCurrent),
        result(id: '3', outcome: LegacyScoringRecoveryOutcome.recoverable),
        result(
          id: '4',
          outcome: LegacyScoringRecoveryOutcome.blocked,
          blockerReasons: const ['missing_fiber'],
        ),
        result(
          id: '5',
          outcome: LegacyScoringRecoveryOutcome.blocked,
          blockerReasons: const ['saturated_fat_exceeds_total_fat'],
        ),
        result(id: '6', outcome: LegacyScoringRecoveryOutcome.unexpectedError),
      ];

      final counts = summarizeFinalStates(results);
      final sum = counts.values.fold(0, (a, b) => a + b);

      expect(sum, results.length);
      expect(counts[ScoringFinalState.notScoreEligible], 1);
      expect(counts[ScoringFinalState.current], 1);
      expect(counts[ScoringFinalState.scoreableNotCurrent], 1);
      expect(counts[ScoringFinalState.blockedInsufficientEvidence], 1);
      expect(counts[ScoringFinalState.blockedInvalidSourceData], 1);
      expect(counts[ScoringFinalState.unexpectedError], 1);
    });
  });
}
