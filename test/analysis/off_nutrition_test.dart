import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/imports/services/open_food_facts_service.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';

void main() {
  // ── parseOffNutriments — key variants ─────────────────────────────────────

  group('parseOffNutriments — standard dash keys', () {
    test('parses energy-kcal_100g as energyKcal', () {
      final d = parseOffNutriments({'energy-kcal_100g': 424})!;
      expect(d.energyKcal, 424.0);
      expect(d.hasAnyData, isTrue);
    });

    test('parses saturated-fat_100g as saturatedFat', () {
      final d = parseOffNutriments({'saturated-fat_100g': 10.0})!;
      expect(d.saturatedFat, 10.0);
    });

    test('full Popkek-like sample (barcode 8690526069906)', () {
      final raw = {
        'energy-kcal_100g': 424,
        'fat_100g': 20,
        'saturated-fat_100g': 10,
        'carbohydrates_100g': 55,
        'sugars_100g': 35,
        'proteins_100g': 6,
        'salt_100g': 0.8,
      };
      final d = parseOffNutriments(raw)!;
      expect(d.hasAnyData, isTrue);
      expect(d.energyKcal, 424.0);
      expect(d.fat, 20.0);
      expect(d.saturatedFat, 10.0);
      expect(d.carbohydrates, 55.0);
      expect(d.sugars, 35.0);
      expect(d.proteins, 6.0);
      expect(d.salt, 0.8);
    });
  });

  group('parseOffNutriments — string numeric values', () {
    test('parses string integer', () {
      final d = parseOffNutriments({'fat_100g': '20'})!;
      expect(d.fat, 20.0);
    });

    test('parses string decimal with dot', () {
      final d = parseOffNutriments({'salt_100g': '0.8'})!;
      expect(d.salt, 0.8);
    });

    test('parses string decimal with comma', () {
      final d = parseOffNutriments({'salt_100g': '0,8'})!;
      expect(d.salt, 0.8);
    });

    test('parses comma decimal for all fields', () {
      final raw = {
        'fat_100g': '20,5',
        'saturated-fat_100g': '10,2',
        'sugars_100g': '35,0',
      };
      final d = parseOffNutriments(raw)!;
      expect(d.fat, closeTo(20.5, 0.001));
      expect(d.saturatedFat, closeTo(10.2, 0.001));
      expect(d.sugars, closeTo(35.0, 0.001));
    });
  });

  group('parseOffNutriments — kJ→kcal derivation', () {
    test('derives kcal from energy-kj_100g when kcal absent', () {
      final d = parseOffNutriments({'energy-kj_100g': 1775, 'fat_100g': 20})!;
      expect(d.energyKcal, isNotNull);
      // 1775 / 4.184 ≈ 424.2
      expect(d.energyKcal!, closeTo(424.2, 1.0));
    });

    test('derives kcal from energy_100g (plain energy key)', () {
      final d = parseOffNutriments({'energy_100g': 1675, 'fat_100g': 10})!;
      expect(d.energyKcal, isNotNull);
      expect(d.energyKcal!, closeTo(400.4, 1.0));
    });

    test('prefers energy-kcal_100g over kJ derivation', () {
      final d = parseOffNutriments({
        'energy-kcal_100g': 400,
        'energy-kj_100g': 9999,
        'fat_100g': 10,
      })!;
      expect(d.energyKcal, 400.0);
    });
  });

  group('parseOffNutriments — 100ml fallback (beverages)', () {
    test('falls back to _100ml when _100g absent', () {
      final d = parseOffNutriments({
        'energy-kcal_100ml': 42,
        'sugars_100ml': 9.8,
      })!;
      expect(d.energyKcal, 42.0);
      expect(d.sugars, 9.8);
    });
  });

  group('parseOffNutriments — non-per-100 bare key fallback', () {
    test('uses bare fat key when _100g and _100ml absent', () {
      final d = parseOffNutriments({'fat': 15.0, 'proteins': 5.0})!;
      expect(d.fat, 15.0);
      expect(d.proteins, 5.0);
    });
  });

  group('parseOffNutriments — null/missing cases', () {
    test('returns null when map has no recognised fields', () {
      expect(parseOffNutriments({'unknown': 5}), isNull);
    });

    test('returns null when map is empty', () {
      expect(parseOffNutriments({}), isNull);
    });

    test('integer 0 is treated as present (not missing)', () {
      final d = parseOffNutriments({'sugars_100g': 0, 'fat_100g': 0})!;
      expect(d.sugars, 0.0);
      expect(d.fat, 0.0);
      expect(d.hasAnyData, isTrue);
    });
  });

  // ── Product.hasNutrition uses parsed data ─────────────────────────────────

  final now = DateTime(2026, 1, 1);

  Product makeProduct({String? nutritionText}) => Product(
    id: 'test',
    name: 'Test',
    verificationStatus: 'pending',
    nutritionText: nutritionText,
    createdAt: now,
    updatedAt: now,
  );

  group('Product.hasNutrition', () {
    test('true when nutrition_text has real data', () {
      final p = makeProduct(
        nutritionText: jsonEncode({'energy_kcal': 200.0, 'fat': 10.0}),
      );
      expect(p.hasNutrition, isTrue);
    });

    test('false when nutrition_text is null', () {
      expect(makeProduct().hasNutrition, isFalse);
    });

    test('false when nutrition_text is empty JSON object', () {
      expect(makeProduct(nutritionText: '{}').hasNutrition, isFalse);
    });

    test('false when nutrition_text is malformed JSON', () {
      expect(makeProduct(nutritionText: 'not-json').hasNutrition, isFalse);
    });
  });
}
