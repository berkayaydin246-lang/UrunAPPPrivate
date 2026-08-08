import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/product/models/nutrition_data.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/scoring/adapters/product_scoring_input_adapter.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/composition_percentage_evidence.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/evidence_value.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/presence_evidence.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/scoring_readiness_evaluator.dart';

void main() {
  const adapter = ProductScoringInputAdapter();
  const evaluator = ScoringReadinessEvaluator();

  Product product({
    String name = 'Test Product',
    String? nutritionText,
    List<String>? categoryTags,
  }) {
    final timestamp = DateTime.utc(2026, 8, 8);
    return Product(
      id: 'product-id',
      name: name,
      nutritionText: nutritionText,
      categoryTags: categoryTags,
      verificationStatus: 'verified',
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }

  group('evidence state distinctions', () {
    test('FVL unknown is not zero', () {
      const evidence = CompositionPercentageEvidence.unknown();

      expect(evidence.state, CompositionPercentageState.unknown);
      expect(evidence.percentage, isNull);
      expect(evidence.hasDeterministicValue, isFalse);
    });

    test('FVL proven absent is deterministic zero', () {
      const evidence = CompositionPercentageEvidence.provenAbsent(
        provenance: EvidenceProvenance.declaredLabel,
      );

      expect(evidence.state, CompositionPercentageState.provenAbsent);
      expect(evidence.percentage, 0);
      expect(evidence.hasDeterministicValue, isTrue);
    });

    test('known FVL percentage retains exact value', () {
      const evidence = CompositionPercentageEvidence.known(
        20,
        provenance: EvidenceProvenance.adminVerified,
      );

      expect(evidence.state, CompositionPercentageState.known);
      expect(evidence.percentage, 20);
    });

    test('NNS absent is distinct from unknown', () {
      const absent = PresenceEvidence.absent(
        provenance: EvidenceProvenance.declaredLabel,
      );
      const unknown = PresenceEvidence.unknown();

      expect(absent.state, PresenceEvidenceState.absent);
      expect(absent.isKnown, isTrue);
      expect(unknown.state, PresenceEvidenceState.unknown);
      expect(unknown.isKnown, isFalse);
    });

    test('unknown provenance never becomes verified', () {
      const evidence = EvidenceValue<double>(
        value: 12,
        provenance: EvidenceProvenance.unknown,
      );

      expect(evidence.hasValue, isTrue);
      expect(evidence.isTrusted, isFalse);
      expect(evidence.verification, EvidenceVerification.unknown);
    });
  });

  group('legacy nutrition adaptation', () {
    test('sodium-derived salt retains value and provenance', () {
      final nutrition = adapter.fromLegacyNutrition(
        const NutritionData(sodium: 0.3),
      );

      expect(nutrition.salt.value, closeTo(0.75, 0.000001));
      expect(nutrition.salt.provenance, EvidenceProvenance.derivedFromSodium);
    });

    test('kcal conversion remains explicitly derived', () {
      final nutrition = adapter.fromLegacyNutrition(
        const NutritionData(energyKcal: 100),
      );

      expect(nutrition.energyKj.value, closeTo(418.4, 0.000001));
      expect(nutrition.energyKj.provenance, EvidenceProvenance.derivedFromKcal);
    });

    test('canonical kJ remains imported and is not overwritten by kcal', () {
      final nutrition = adapter.fromLegacyNutrition(
        const NutritionData(energyKj: 410, energyKcal: 100),
      );

      expect(nutrition.energyKj.value, 410);
      expect(nutrition.energyKj.provenance, EvidenceProvenance.databaseImport);
      expect(
        nutrition.energyKj.provenance,
        isNot(EvidenceProvenance.declaredLabel),
      );
    });

    test('null nutrition adapts without throwing', () {
      expect(() => adapter.fromLegacyNutrition(null), returnsNormally);
      expect(adapter.fromLegacyNutrition(null).energyKj.value, isNull);
    });
  });

  group('legacy Product behavior', () {
    test('existing product adapter does not throw', () {
      final legacyProduct = product(
        categoryTags: ['gazli_icecek'],
        nutritionText:
            '{"energy_kcal":42,"saturated_fat":0,"sugars":10,"salt":0.1,"proteins":0,"fiber":0}',
      );

      expect(() => adapter.fromProduct(legacyProduct), returnsNormally);
    });

    test('legacy nutrition without basis is not scorable', () {
      final input = adapter.fromProduct(
        product(
          categoryTags: ['gazli_icecek'],
          nutritionText:
              '{"energy_kcal":42,"saturated_fat":0,"sugars":10,"salt":0.1,"proteins":0,"fiber":0}',
        ),
      );
      final result = evaluator.evaluate(input);

      expect(result.isScorable, isFalse);
      expect(
        result.blockingReasons,
        contains(ScoringReadinessBlocker.unknownNutritionBasis),
      );
    });

    test('null legacy nutrition returns clear blockers', () {
      final result = evaluator.evaluate(
        adapter.fromProduct(product(categoryTags: ['gazli_icecek'])),
      );

      expect(result.isScorable, isFalse);
      expect(
        result.blockingReasons,
        containsAll({
          ScoringReadinessBlocker.unknownNutritionBasis,
          ScoringReadinessBlocker.missingEnergyKj,
          ScoringReadinessBlocker.missingSaturatedFat,
          ScoringReadinessBlocker.missingSugars,
          ScoringReadinessBlocker.missingSalt,
          ScoringReadinessBlocker.missingProtein,
          ScoringReadinessBlocker.missingFiber,
          ScoringReadinessBlocker.unknownFvlPercentage,
          ScoringReadinessBlocker.unknownNnsPresence,
        }),
      );
    });

    test('malformed legacy nutrition does not throw', () {
      final input = adapter.fromProduct(
        product(categoryTags: ['gazli_icecek'], nutritionText: 'not-json'),
      );

      expect(input.nutrition.energyKj.value, isNull);
    });

    test('product name never changes category resolution', () {
      final first = adapter.fromProduct(
        product(name: 'Kola', categoryTags: ['gazli_icecek']),
      );
      final second = adapter.fromProduct(
        product(name: 'Tamamen Farklı Ad', categoryTags: ['gazli_icecek']),
      );

      expect(first.categoryEvidence.resolvedCategory, ScoringCategory.beverage);
      expect(
        second.categoryEvidence.resolvedCategory,
        first.categoryEvidence.resolvedCategory,
      );
    });
  });
}
