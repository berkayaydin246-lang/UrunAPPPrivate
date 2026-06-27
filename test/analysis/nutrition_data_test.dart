import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/analysis/models/product_analysis_result.dart';
import 'package:food_analyzer_app/features/analysis/widgets/analysis_result_widget.dart';
import 'package:food_analyzer_app/features/imports/services/open_food_facts_service.dart';
import 'package:food_analyzer_app/features/product/models/nutrition_data.dart';

void main() {
  // ── parseOffNutriments ────────────────────────────────────────────────────

  group('parseOffNutriments — dash key extraction', () {
    test('parses exact OFF tuna sample (barcode 8699118005551)', () {
      final raw = {
        'energy-kj_100g': 794,
        'energy-kcal_100g': 190,
        'fat_100g': 9.3,
        'saturated-fat_100g': 1.4,
        'carbohydrates_100g': 0.8,
        'sugars_100g': 0,
        'fiber_100g': 0,
        'proteins_100g': 24.8,
        'salt_100g': 1.6725,
        'sodium_100g': 0.669,
      };

      final data = parseOffNutriments(raw)!;
      expect(data.hasAnyData, isTrue);
      expect(data.energyKcal, 190.0);
      expect(data.fat, 9.3);
      expect(data.saturatedFat, 1.4);
      expect(data.sugars, 0.0);
      expect(data.proteins, 24.8);
      expect(data.salt, 1.6725);
    });

    test(
      'dash-variant energy-kcal_100g takes priority over underscore variant',
      () {
        final raw = {'energy-kcal_100g': 200, 'energy_kcal_100g': 999};
        final data = parseOffNutriments(raw)!;
        expect(data.energyKcal, 200.0);
      },
    );

    test('falls back to 100ml key when 100g is absent (beverage)', () {
      final raw = {
        'energy-kcal_100ml': 42,
        'sugars_100ml': 9.8,
        'proteins_100ml': 0.0,
      };
      final data = parseOffNutriments(raw)!;
      expect(data.energyKcal, 42.0);
      expect(data.sugars, 9.8);
    });

    test('returns null when map has no recognised fields', () {
      final raw = <String, dynamic>{'unknown_key': 5};
      expect(parseOffNutriments(raw), isNull);
    });

    test('integer 0 values are extracted (not treated as missing)', () {
      final raw = {'sugars_100g': 0, 'proteins_100g': 0};
      final data = parseOffNutriments(raw)!;
      expect(data.sugars, 0.0);
      expect(data.proteins, 0.0);
    });
  });

  // ── nutrition-only consumption notes ─────────────────────────────────────

  group('buildConsumptionNotes — nutrition-only (null result fallback)', () {
    test('high salt triggers salt note even with no ingredient result', () {
      // Simulate case (b): no ingredients, but nutrition exists.
      // _ConsumptionNoteCard passes a default empty result.
      final result = ProductAnalysisResult(
        scoreLabel: AnalysisScoreLabel.orta,
        summary: '',
      );
      final nutrition = const NutritionData(
        energyKcal: 190.0,
        proteins: 24.8,
        salt: 1.6725,
      );
      final notes = buildConsumptionNotes(result, nutrition);

      expect(notes.any((n) => n.contains('Tuz')), isTrue);
      expect(notes.any((n) => n.contains('Protein')), isTrue);
      // No additive warning — no additive signals present
      expect(notes.any((n) => n.contains('tatlandırıcı')), isFalse);
      expect(notes.any((n) => n.contains('işlenmişlik sinyalleri')), isFalse);
    });

    test('no negative signals with low salt → reassurance note', () {
      final result = ProductAnalysisResult(
        scoreLabel: AnalysisScoreLabel.iyiSecim,
        summary: '',
      );
      final nutrition = const NutritionData(salt: 0.2, proteins: 3.0);
      final notes = buildConsumptionNotes(result, nutrition);

      expect(notes.any((n) => n.contains('porsiyon')), isTrue);
    });
  });

  group('NutritionData.fromMap', () {
    test('parses all double fields', () {
      final data = NutritionData.fromMap({
        'energy_kcal': 250.0,
        'fat': 10.5,
        'saturated_fat': 3.2,
        'carbohydrates': 30.0,
        'sugars': 12.0,
        'fiber': 4.5,
        'proteins': 8.0,
        'salt': 0.8,
        'sodium': 0.3,
      });

      expect(data.energyKcal, 250.0);
      expect(data.fat, 10.5);
      expect(data.saturatedFat, 3.2);
      expect(data.carbohydrates, 30.0);
      expect(data.sugars, 12.0);
      expect(data.fiber, 4.5);
      expect(data.proteins, 8.0);
      expect(data.salt, 0.8);
      expect(data.sodium, 0.3);
    });

    test('coerces int values to double', () {
      final data = NutritionData.fromMap({'energy_kcal': 300, 'proteins': 10});
      expect(data.energyKcal, 300.0);
      expect(data.proteins, 10.0);
    });

    test('coerces string values to double', () {
      final data = NutritionData.fromMap({'sugars': '15.5', 'salt': '1.2'});
      expect(data.sugars, 15.5);
      expect(data.salt, 1.2);
    });

    test('returns null for missing keys', () {
      final data = NutritionData.fromMap({});
      expect(data.energyKcal, isNull);
      expect(data.fat, isNull);
    });

    test('returns null for unparseable string', () {
      final data = NutritionData.fromMap({'sugars': 'n/a'});
      expect(data.sugars, isNull);
    });
  });

  group('NutritionData.toMap round-trip', () {
    test('toMap contains only non-null fields', () {
      const data = NutritionData(sugars: 12.0, salt: 0.5);
      final map = data.toMap();
      expect(map.containsKey('sugars'), isTrue);
      expect(map.containsKey('salt'), isTrue);
      expect(map.containsKey('fat'), isFalse);
    });

    test('fromMap(toMap()) preserves values', () {
      const original = NutritionData(
        energyKcal: 200.0,
        fat: 8.0,
        sugars: 22.0,
        proteins: 6.0,
        fiber: 3.5,
        salt: 1.2,
      );
      final roundTripped = NutritionData.fromMap(original.toMap());
      expect(roundTripped.energyKcal, original.energyKcal);
      expect(roundTripped.fat, original.fat);
      expect(roundTripped.sugars, original.sugars);
      expect(roundTripped.proteins, original.proteins);
      expect(roundTripped.fiber, original.fiber);
      expect(roundTripped.salt, original.salt);
    });
  });

  group('NutritionData.hasAnyData', () {
    test('false when all fields are null', () {
      const data = NutritionData();
      expect(data.hasAnyData, isFalse);
    });

    test('true when at least one field is set', () {
      const data = NutritionData(salt: 0.5);
      expect(data.hasAnyData, isTrue);
    });
  });

  // ── buildConsumptionNotes ───────────────────────────────────────────────────

  ProductAnalysisResult emptyResult({
    Map<String, int> riskSignals = const {},
    List<dynamic> detectedRiskIngredients = const [],
    List<dynamic> recognizedIngredients = const [],
  }) {
    return ProductAnalysisResult(
      scoreLabel: AnalysisScoreLabel.orta,
      summary: '',
      riskSignals: riskSignals,
      detectedRiskIngredients: List.unmodifiable(detectedRiskIngredients),
      recognizedIngredients: List.unmodifiable(recognizedIngredients),
    );
  }

  group('buildConsumptionNotes — ingredient signals', () {
    test('benign high_salt_signal does NOT trigger additive note', () {
      final result = emptyResult(
        riskSignals: {'high_salt_signal': 1},
        recognizedIngredients: [],
      );
      final notes = buildConsumptionNotes(result, null);
      expect(notes.any((n) => n.contains('katkı')), isFalse);
      expect(notes.any((n) => n.contains('tatlandırıcı')), isFalse);
    });

    test('benign acidity_regulator does NOT trigger additive note', () {
      final result = emptyResult(
        riskSignals: {'acidity_regulator': 1},
        recognizedIngredients: [],
      );
      final notes = buildConsumptionNotes(result, null);
      expect(notes.any((n) => n.contains('katkı')), isFalse);
    });

    test('preservative signal DOES trigger additive note', () {
      final result = emptyResult(
        riskSignals: {'preservative': 1},
        recognizedIngredients: [],
      );
      final notes = buildConsumptionNotes(result, null);
      // Note starts with uppercase 'Katkı'; check the lowercase tail 'tatlandırıcı'
      expect(notes.any((n) => n.contains('tatlandırıcı')), isTrue);
    });

    test('artificial_sweetener signal triggers additive note', () {
      final result = emptyResult(
        riskSignals: {'artificial_sweetener': 1},
        recognizedIngredients: [],
      );
      final notes = buildConsumptionNotes(result, null);
      expect(notes.any((n) => n.contains('tatlandırıcı')), isTrue);
    });

    test('no signals + no nutrition + no recognised → empty notes', () {
      final result = emptyResult();
      final notes = buildConsumptionNotes(result, null);
      expect(notes, isEmpty);
    });
  });

  group('buildConsumptionNotes — nutrition thresholds', () {
    test('sugars >22.5g triggers sugar note', () {
      final result = emptyResult();
      final nutrition = const NutritionData(sugars: 23.0);
      final notes = buildConsumptionNotes(result, nutrition);
      expect(notes.any((n) => n.contains('Şeker')), isTrue);
    });

    test('sugars <=22.5g does NOT trigger sugar note', () {
      final result = emptyResult();
      final nutrition = const NutritionData(sugars: 22.0);
      final notes = buildConsumptionNotes(result, nutrition);
      expect(notes.any((n) => n.contains('Şeker')), isFalse);
    });

    test('salt >1.5g triggers salt note', () {
      final result = emptyResult();
      final nutrition = const NutritionData(salt: 2.0);
      final notes = buildConsumptionNotes(result, nutrition);
      expect(notes.any((n) => n.contains('Tuz')), isTrue);
    });

    test('salt <=1.5g does NOT trigger salt note', () {
      final result = emptyResult();
      final nutrition = const NutritionData(salt: 1.5);
      final notes = buildConsumptionNotes(result, nutrition);
      expect(notes.any((n) => n.contains('Tuz')), isFalse);
    });

    test('saturatedFat >5g triggers sat-fat note', () {
      final result = emptyResult();
      final nutrition = const NutritionData(saturatedFat: 6.0);
      final notes = buildConsumptionNotes(result, nutrition);
      expect(notes.any((n) => n.contains('Doymuş yağ')), isTrue);
    });

    test('fiber >=6g triggers strong positive note', () {
      final result = emptyResult();
      final nutrition = const NutritionData(fiber: 6.0);
      final notes = buildConsumptionNotes(result, nutrition);
      expect(notes.any((n) => n.contains('sindirim')), isTrue);
    });

    test('fiber 3-6g triggers positive note', () {
      final result = emptyResult();
      final nutrition = const NutritionData(fiber: 4.0);
      final notes = buildConsumptionNotes(result, nutrition);
      expect(notes.any((n) => n.contains('lif')), isTrue);
    });

    test('protein >=12g triggers strong positive note', () {
      final result = emptyResult();
      final nutrition = const NutritionData(proteins: 14.0);
      final notes = buildConsumptionNotes(result, nutrition);
      expect(notes.any((n) => n.contains('Protein')), isTrue);
    });

    test('no signals + nutrition hasAnyData → reassurance note', () {
      final result = emptyResult();
      final nutrition = const NutritionData(energyKcal: 200.0);
      final notes = buildConsumptionNotes(result, nutrition);
      expect(notes.any((n) => n.contains('porsiyon')), isTrue);
    });
  });
}
