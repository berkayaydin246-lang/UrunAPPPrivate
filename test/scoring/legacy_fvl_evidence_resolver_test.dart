import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/legacy_fvl_evidence_resolver.dart';

/// Direct unit coverage for [LegacyFvlEvidenceResolver], focused on the
/// deterministic FVL evidence semantics required by the methodology
/// readiness correction:
///   1. proven absence (source-complete, no qualifying ingredient) => 0
///   2. explicit declarations uniquely determining the bucket => exact sum
///   3. safe bounds: a proven lower bound that already exceeds the single
///      open-ended top bucket threshold (80%) => ready, even with other
///      qualifying ingredients left unquantified
///   4. genuine ambiguity (bound does not clear a threshold, or a
///      dried/concentrated factor is involved) => remains unknown/blocked
void main() {
  const resolver = LegacyFvlEvidenceResolver();

  group('proven absence', () {
    test('source-complete list with no qualifying ingredient is zero, not unknown', () {
      final result = resolver.resolve(
        ingredientsText: 'un, tuz, şeker, maya',
        sourceComplete: true,
        category: ScoringCategory.generalFood,
      );

      expect(result.hasQualifyingIngredient, isFalse);
      expect(result.isReady, isTrue);
      expect(
        result.evidence.state,
        CompositionPercentageState.provenAbsent,
      );
      expect(result.evidence.percentage, 0);
    });

    test('a not-source-complete list is unknown, never assumed absent', () {
      final result = resolver.resolve(
        ingredientsText: 'un, tuz, şeker, maya',
        sourceComplete: false,
        category: ScoringCategory.generalFood,
      );

      expect(result.isReady, isFalse);
      expect(result.evidence.state, CompositionPercentageState.unknown);
    });
  });

  group('explicit declarations', () {
    test('every qualifying ingredient with a clean single percentage sums exactly', () {
      final result = resolver.resolve(
        ingredientsText: 'domates %45, biber %10, tuz',
        sourceComplete: true,
        category: ScoringCategory.generalFood,
      );

      expect(result.isReady, isTrue);
      expect(result.evidence.state, CompositionPercentageState.known);
      expect(result.evidence.percentage, 55);
    });

    test('a single qualifying ingredient without any percentage remains unknown', () {
      final result = resolver.resolve(
        ingredientsText: 'domates, tuz, şeker',
        sourceComplete: true,
        category: ScoringCategory.generalFood,
      );

      expect(result.isReady, isFalse);
      expect(result.hasQualifyingIngredient, isTrue);
      expect(result.evidence.state, CompositionPercentageState.unknown);
    });
  });

  group('safe bounds', () {
    test(
      'a known lower-bound sum already above 80% is ready, even with an unquantified qualifying ingredient present',
      () {
        final result = resolver.resolve(
          ingredientsText: 'domates %85, biber, tuz',
          sourceComplete: true,
          category: ScoringCategory.generalFood,
        );

        expect(
          result.isReady,
          isTrue,
          reason:
              'the true total can only be >= 85% once the undeclared '
              'biber percentage is added, so it is provably in the same '
              'open-ended >80 bucket regardless of that value',
        );
        expect(result.evidence.state, CompositionPercentageState.known);
        expect(result.evidence.percentage, greaterThan(80));
      },
    );

    test(
      'a known lower-bound sum that does NOT clear 80% remains blocked — the undeclared remainder could still cross a threshold',
      () {
        final result = resolver.resolve(
          ingredientsText: 'domates %45, biber, tuz',
          sourceComplete: true,
          category: ScoringCategory.generalFood,
        );

        expect(
          result.isReady,
          isFalse,
          reason:
              'the undeclared biber percentage could push the true total '
              'past 60 or 80, changing which bucket applies — this must '
              'not be guessed',
        );
        expect(result.evidence.state, CompositionPercentageState.unknown);
      },
    );

    test(
      'multiple unquantified qualifying ingredients still only need the known sum to clear 80%',
      () {
        final result = resolver.resolve(
          ingredientsText: 'domates %90, biber, soğan, tuz',
          sourceComplete: true,
          category: ScoringCategory.generalFood,
        );

        expect(result.isReady, isTrue);
        expect(result.evidence.percentage, greaterThan(80));
      },
    );

    test(
      'the exact single-explicit-percentage boundary case (=80) is NOT treated as a safe lower bound — it is not the ambiguous case at all, it must stay exact',
      () {
        // Exactly 80% is fully declared with no unquantified ingredient —
        // this is case 2 (explicit declarations), not case 3 (safe
        // bounds), and must resolve to the literal, exact value.
        final result = resolver.resolve(
          ingredientsText: 'domates %80, tuz',
          sourceComplete: true,
          category: ScoringCategory.generalFood,
        );

        expect(result.isReady, isTrue);
        expect(result.evidence.percentage, 80);
      },
    );
  });

  group('genuine ambiguity remains blocked regardless of safe-bounds logic', () {
    test('a dried/concentrated qualifying ingredient blocks the whole product even if others are known and high', () {
      final result = resolver.resolve(
        ingredientsText: 'domates %90, kuru üzüm, tuz',
        sourceComplete: true,
        category: ScoringCategory.generalFood,
      );

      expect(
        result.isReady,
        isFalse,
        reason:
            'dried/concentrated FVL requires the official factor-of-2 '
            'rule, which this resolver does not compute — never guessed, '
            'even when other declared ingredients already clear 80%',
      );
    });

    test('a percentage sum exceeding 100% is a data anomaly, never a safe bound', () {
      final result = resolver.resolve(
        ingredientsText: 'domates %90, biber %90',
        sourceComplete: true,
        category: ScoringCategory.generalFood,
      );

      expect(result.isReady, isFalse);
    });

    test(
      'a single segment declaring two nested percentages (an outer '
      'compound ingredient with its own sub-ingredient percentage) is '
      'never resolved by picking either number — it stays unquantified',
      () {
        // "domates sosu %30 (domates %90, su, tuz)" is ONE segment (the
        // comma inside the parentheses does not split it — see
        // LegacyFvlEvidenceResolver._segments' depth tracking), so it
        // contains two percentage matches: the outer ingredient's own
        // %30, and the nested sub-ingredient's %90. Neither is the
        // correct standalone contribution of this one ingredient to the
        // product's total FVL percentage, so this resolver must never
        // guess which one applies.
        final result = resolver.resolve(
          ingredientsText: 'domates sosu %30 (domates %90, su, tuz), tuz',
          sourceComplete: true,
          category: ScoringCategory.generalFood,
        );

        expect(
          result.isReady,
          isFalse,
          reason:
              'a segment with two percentage matches must fall through to '
              'unquantified, never silently pick the outer or inner value',
        );
        expect(result.hasQualifyingIngredient, isTrue);
      },
    );

    test(
      'a nested compound ingredient does not corrupt an otherwise-known '
      'sum from sibling ingredients',
      () {
        final result = resolver.resolve(
          ingredientsText:
              'domates %85, biber sosu %10 (biber %70, su), tuz',
          sourceComplete: true,
          category: ScoringCategory.generalFood,
        );

        expect(
          result.isReady,
          isTrue,
          reason:
              'domates alone already proves the safe >80 lower bound; the '
              'nested biber sosu segment correctly contributes nothing to '
              'knownPercentageSum rather than corrupting it with either of '
              'its two percentages',
        );
        expect(result.evidence.percentage, 85);
      },
    );
  });
}
