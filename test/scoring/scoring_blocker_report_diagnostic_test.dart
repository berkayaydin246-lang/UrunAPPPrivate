import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/scoring/application/legacy_scoring_evidence_recovery.dart';
import 'package:food_analyzer_app/features/scoring/application/scoring_blocker_diagnostic.dart';

import '../../tool/scoring_blocker_report.dart';

/// Focused tests for the read-only [INGREDIENT COMPLETENESS DIAGNOSTIC]
/// subsection added to tool/scoring_blocker_report.dart. These verify the
/// per-condition breakdown matches
/// LegacyStagingScoringEvidence.hasSourceCompleteIngredients()'s actual
/// AND-ed conditions exactly, and that the reported overall boolean is
/// always the real method's result — never independently recomputed.
void main() {
  const service = ScoringBlockerDiagnosticService();

  test('all four conditions pass: reports every condition true', () async {
    final product = _product();
    final staging = _staging(product: product);
    final report = await service.inspect(
      product: product,
      stagingMatches: [staging],
      ingredientCatalogue: const [],
    );

    final output = formatIngredientCompletenessDiagnostic(report);

    expect(output, contains('[INGREDIENT COMPLETENESS DIAGNOSTIC]'));
    expect(output, contains('condition_quality_ok=true'));
    expect(output, contains('condition_web_scraper_source=true'));
    expect(output, contains('condition_ingredients_raw_nonempty=true'));
    expect(output, contains('condition_text_exact_match=true'));
    expect(output, contains('condition_text_normalized_match=true'));
    expect(output, contains('has_source_complete_ingredients=true'));
    expect(report.ingredientsSourceComplete, isTrue);
    expect(
      staging.hasSourceCompleteIngredients(product.ingredientsText),
      isTrue,
    );
  });

  test(
    'ingredients_quality is not ingredients_ok: only that condition fails',
    () async {
      final product = _product();
      final staging = _staging(
        product: product,
        ingredientsQuality: 'ingredients_partial',
      );
      final report = await service.inspect(
        product: product,
        stagingMatches: [staging],
        ingredientCatalogue: const [],
      );

      final output = formatIngredientCompletenessDiagnostic(report);

      expect(
        output,
        contains('staging_ingredients_quality=ingredients_partial'),
      );
      expect(output, contains('condition_quality_ok=false'));
      expect(output, contains('condition_web_scraper_source=true'));
      expect(output, contains('condition_ingredients_raw_nonempty=true'));
      expect(output, contains('condition_text_normalized_match=true'));
      expect(output, contains('has_source_complete_ingredients=false'));
      expect(report.ingredientsSourceComplete, isFalse);
    },
  );

  test(
    'neither ingredients_source nor source is web_scraper: that condition fails',
    () async {
      final product = _product(source: 'manual_seed');
      final staging = _staging(
        product: product,
        source: 'manual_seed',
        ingredientsSource: null,
      );
      final report = await service.inspect(
        product: product,
        stagingMatches: [staging],
        ingredientCatalogue: const [],
      );

      final output = formatIngredientCompletenessDiagnostic(report);

      expect(output, contains('effective_ingredients_source=manual_seed'));
      expect(output, contains('condition_web_scraper_source=false'));
      expect(output, contains('has_source_complete_ingredients=false'));
      expect(report.ingredientsSourceComplete, isFalse);
    },
  );

  test('ingredients_raw is empty: that condition fails alone', () async {
    final product = _product();
    final staging = _staging(product: product, ingredientsRaw: '   ');
    final report = await service.inspect(
      product: product,
      stagingMatches: [staging],
      ingredientCatalogue: const [],
    );

    final output = formatIngredientCompletenessDiagnostic(report);

    expect(output, contains('condition_quality_ok=true'));
    expect(output, contains('condition_web_scraper_source=true'));
    expect(output, contains('condition_ingredients_raw_nonempty=false'));
    expect(output, contains('condition_text_normalized_match=true'));
    expect(output, contains('has_source_complete_ingredients=false'));
    expect(report.ingredientsSourceComplete, isFalse);
  });

  test(
    'text differs only by whitespace/case: exact match fails but normalized match passes',
    () async {
      final product = _product(ingredientsText: 'mısır unu, bitkisel yağ, tuz');
      final staging = _staging(
        product: product,
        stagingIngredientsText: '  Mısır Unu,   Bitkisel  Yağ, Tuz  ',
      );
      final report = await service.inspect(
        product: product,
        stagingMatches: [staging],
        ingredientCatalogue: const [],
      );

      final output = formatIngredientCompletenessDiagnostic(report);

      expect(output, contains('condition_text_exact_match=false'));
      expect(output, contains('condition_text_normalized_match=true'));
      // hasSourceCompleteIngredients() itself normalizes, so this specific
      // case should still be reported complete overall.
      expect(output, contains('has_source_complete_ingredients=true'));
      expect(report.ingredientsSourceComplete, isTrue);
    },
  );

  test(
    'text genuinely differs in content: both text conditions fail',
    () async {
      final product = _product(ingredientsText: 'mısır unu, tuz');
      final staging = _staging(
        product: product,
        stagingIngredientsText: 'buğday unu, şeker',
      );
      final report = await service.inspect(
        product: product,
        stagingMatches: [staging],
        ingredientCatalogue: const [],
      );

      final output = formatIngredientCompletenessDiagnostic(report);

      expect(output, contains('condition_text_exact_match=false'));
      expect(output, contains('condition_text_normalized_match=false'));
      expect(output, contains('has_source_complete_ingredients=false'));
      expect(report.ingredientsSourceComplete, isFalse);
    },
  );

  test(
    'no staging match: reports selected_staging_row=none, never crashes',
    () async {
      final product = _product();
      final report = await service.inspect(
        product: product,
        stagingMatches: const [],
        ingredientCatalogue: const [],
      );

      final output = formatIngredientCompletenessDiagnostic(report);

      expect(output, contains('[INGREDIENT COMPLETENESS DIAGNOSTIC]'));
      expect(output, contains('selected_staging_row=none'));
      expect(output, contains('has_source_complete_ingredients=false'));
      expect(report.ingredientsSourceComplete, isFalse);
    },
  );

  test(
    'reported has_source_complete_ingredients always matches the real method result (no drift), across every scenario above',
    () async {
      final scenarios =
          <({Product product, LegacyStagingScoringEvidence staging})>[
            (
              product: _product(id: 'drift-1'),
              staging: _staging(product: _product(id: 'drift-1')),
            ),
            (
              product: _product(id: 'drift-2'),
              staging: _staging(
                product: _product(id: 'drift-2'),
                ingredientsQuality: 'ingredients_partial',
              ),
            ),
            (
              product: _product(id: 'drift-3'),
              staging: _staging(
                product: _product(id: 'drift-3'),
                ingredientsRaw: '',
              ),
            ),
          ];

      for (final scenario in scenarios) {
        final report = await service.inspect(
          product: scenario.product,
          stagingMatches: [scenario.staging],
          ingredientCatalogue: const [],
        );
        final output = formatIngredientCompletenessDiagnostic(report);
        final expected = scenario.staging.hasSourceCompleteIngredients(
          scenario.product.ingredientsText,
        );

        expect(
          output,
          contains('has_source_complete_ingredients=$expected'),
          reason: scenario.product.id,
        );
        expect(report.ingredientsSourceComplete, expected);
      }
    },
  );
}

Product _product({
  String id = '0001',
  String ingredientsText = 'mısır unu, bitkisel yağ, tuz',
  String source = 'web_scraper:migros',
}) {
  final now = DateTime.utc(2026, 8, 14);
  return Product(
    id: id,
    barcode: '8690000000000',
    name: 'Diagnostic Product',
    brand: 'Test Brand',
    ingredientsText: ingredientsText,
    nutritionText: jsonEncode(_nutrition()),
    source: source,
    sourceUrl: 'https://www.migros.com.tr/product-$id',
    verificationStatus: 'imported',
    categoryTags: const ['cips_kraker'],
    canonicalCategory: 'Atıştırmalık',
    canonicalSubcategory: 'Cips & Kraker',
    createdAt: now,
    updatedAt: now,
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

LegacyStagingScoringEvidence _staging({
  required Product product,
  String basis = 'per_100',
  String source = 'web_scraper:migros',
  String? ingredientsSource = 'web_scraper:migros',
  String ingredientsQuality = 'ingredients_ok',
  String? ingredientsRaw,
  String? stagingIngredientsText,
}) {
  return LegacyStagingScoringEvidence(
    id: 'staging-${product.id}',
    sourceUrl: product.sourceUrl!,
    nutritionBasis: basis,
    source: source,
    ingredientsSource: ingredientsSource,
    ingredientsRaw: ingredientsRaw ?? 'İçindekiler: ${product.ingredientsText}',
    ingredientsText: stagingIngredientsText ?? product.ingredientsText,
    ingredientsQuality: ingredientsQuality,
    nutritionSource: 'web_scraper:migros',
    nutritionStrategy: 'dom',
    nutritionJson: product.nutrition?.toMap(),
  );
}
