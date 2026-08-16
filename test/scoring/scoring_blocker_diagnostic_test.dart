import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/scoring/application/legacy_scoring_evidence_recovery.dart';
import 'package:food_analyzer_app/features/scoring/application/scoring_blocker_diagnostic.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_evidence_snapshot.dart';

void main() {
  const service = ScoringBlockerDiagnosticService();
  const formatter = ScoringBlockerReportFormatter();

  test(
    'null scoring evidence is recovered in memory and fully reported',
    () async {
      final product = _product();
      final report = await service.inspect(
        product: product,
        stagingMatches: [_staging(product: product)],
        ingredientCatalogue: const [],
      );
      final output = formatter.format(report);

      expect(report.recovery, isNotNull);
      expect(report.recoveredInMemory, isTrue);
      expect(report.nutritionReady, isTrue);
      expect(report.additiveReady, isTrue);
      expect(report.finalScoreReady, isTrue);
      for (final field in const [
        '[PRODUCT]',
        'existing_scoring_evidence=no',
        'matching_staging_row=yes',
        '[NUTRITION EVIDENCE]',
        'raw_staging_nutrition_basis=per_100',
        'resolved_basis=per100g',
        'nutrition_complete=yes',
        '[CLASSIFICATION]',
        'resolved_scoring_category=generalFood',
        '[FVL / NNS]',
        'fvl_ready=yes',
        '[INGREDIENT / ADDITIVE SCORING]',
        'unmatched_ordinary_food_ingredients_count=3',
        'additive_like_unresolved_ingredients_count=0',
        '[FINAL]',
        'final_score_ready=yes',
        'calculated_score=',
        'ordered_blocker_reasons=none',
      ]) {
        expect(output, contains(field), reason: field);
      }
      expect(report.evaluation?.result.score, isNotNull);
      expect(output, isNot(contains('calculated_score=-')));
    },
  );

  test('missing fiber is reported as real missing nutrition data', () async {
    final nutrition = _nutrition()..remove('fiber');
    final product = _product(nutrition: nutrition);
    final report = await service.inspect(
      product: product,
      stagingMatches: [_staging(product: product)],
      ingredientCatalogue: const [],
    );
    final output = formatter.format(report);

    expect(report.nutritionReady, isFalse);
    expect(report.finalScoreReady, isFalse);
    expect(report.finalBlockers, contains('missing_fiber'));
    expect(output, contains('fiber=-'));
    expect(output, contains('nutrition_complete=no'));
    expect(
      output,
      contains(
        'blocker[0]=missing_fiber cause=A_genuinely_missing_source_data',
      ),
    );
  });

  test('additive-like unmatched token remains a canonical blocker', () async {
    final product = _product(
      ingredientsText: 'mısır unu, bilinmeyen koruyucu, tuz',
    );
    final report = await service.inspect(
      product: product,
      stagingMatches: [_staging(product: product)],
      ingredientCatalogue: const [],
    );
    final output = formatter.format(report);

    expect(report.nutritionReady, isTrue);
    expect(report.additiveReady, isFalse);
    expect(report.finalScoreReady, isFalse);
    expect(report.finalBlockers, contains('canonical_additive_unresolved'));
    expect(report.unmatchedOrdinaryIngredients, hasLength(2));
    expect(report.scoringAssessment.unresolvedIngredients, hasLength(1));
    expect(output, contains('bilinmeyen koruyucu'));
    expect(
      output,
      contains('cause=D_canonical_additive_catalogue_or_matching_gap'),
    );
  });

  test(
    'generic flavouring is reported separately and does not block',
    () async {
      final product = _product(ingredientsText: 'mısır unu, aroma vericiler');
      final report = await service.inspect(
        product: product,
        stagingMatches: [_staging(product: product)],
        ingredientCatalogue: const [],
      );
      final output = formatter.format(report);

      expect(report.additiveReady, isTrue);
      expect(report.scoringAssessment.unresolvedIngredients, isEmpty);
      expect(
        report.scoringAssessment.outOfScopeFlavouringEvidence,
        hasLength(1),
      );
      expect(output, contains('classification=outOfScopeFlavouringEvidence'));
      expect(output, contains('out_of_scope_flavouring_evidence_count=1'));
    },
  );

  test('unknown staging basis preserves the recovery early blocker', () async {
    final product = _product();
    final report = await service.inspect(
      product: product,
      stagingMatches: [_staging(product: product, basis: 'unknown')],
      ingredientCatalogue: const [],
    );
    final output = formatter.format(report);

    expect(report.effectiveEvidence, isNull);
    expect(report.finalBlockers, ['basis_unknown']);
    expect(output, contains('raw_staging_nutrition_basis=unknown'));
    expect(output, contains('resolved_basis=unknown'));
    expect(output, contains('cause=B_unverified_basis_or_provenance'));
  });

  test(
    'existing evidence is evaluated without running legacy recovery',
    () async {
      final product = _product();
      final recovered = await service.inspect(
        product: product,
        stagingMatches: [_staging(product: product)],
        ingredientCatalogue: const [],
      );
      final existing = _withEvidence(product, recovered.effectiveEvidence!);
      final report = await service.inspect(
        product: existing,
        stagingMatches: [_staging(product: existing)],
        ingredientCatalogue: const [],
      );
      final output = formatter.format(report);

      expect(report.recovery, isNull);
      expect(report.recoveredInMemory, isFalse);
      expect(report.finalScoreReady, isTrue);
      expect(output, contains('existing_scoring_evidence=yes'));
      expect(output, contains('recovered_in_memory=no'));
    },
  );
}

Product _product({
  String id = '0001',
  Map<String, dynamic>? nutrition,
  String ingredientsText = 'mısır unu, bitkisel yağ, tuz',
  ScoringEvidenceSnapshot? scoringEvidence,
}) {
  final now = DateTime.utc(2026, 8, 14);
  return Product(
    id: id,
    barcode: '8690000000000',
    name: 'Diagnostic Product',
    brand: 'Test Brand',
    ingredientsText: ingredientsText,
    nutritionText: jsonEncode(nutrition ?? _nutrition()),
    source: 'web_scraper:migros',
    sourceUrl: 'https://www.migros.com.tr/product-$id',
    verificationStatus: 'imported',
    categoryTags: const ['cips_kraker'],
    canonicalCategory: 'Atıştırmalık',
    canonicalSubcategory: 'Cips & Kraker',
    scoringEvidence: scoringEvidence,
    createdAt: now,
    updatedAt: now,
  );
}

Map<String, dynamic> _nutrition() => {
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

// Basis independence correction: 'per_100' (the real Migros contract's
// only value) never distinguishes g/ml and now correctly resolves to
// NutritionBasis.unknown rather than a category-invented value. This
// file's tests are about diagnostic reporting, not basis itself, so the
// default models proven basis evidence ('per_100g', forward-compatible —
// see legacy_scoring_evidence_recovery.dart's _recoveredBasisFromEvidence).
LegacyStagingScoringEvidence _staging({
  required Product product,
  String basis = 'per_100g',
}) {
  return LegacyStagingScoringEvidence(
    id: 'staging-${product.id}',
    sourceUrl: product.sourceUrl!,
    nutritionBasis: basis,
    source: 'web_scraper:migros',
    ingredientsSource: 'web_scraper:migros',
    ingredientsRaw: 'İçindekiler: ${product.ingredientsText}',
    ingredientsText: product.ingredientsText,
    ingredientsQuality: 'ingredients_ok',
    nutritionSource: 'web_scraper:migros',
    nutritionStrategy: 'dom',
    nutritionJson: product.nutrition?.toMap(),
  );
}

Product _withEvidence(Product product, ScoringEvidenceSnapshot evidence) {
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
    scoringEvidence: evidence,
    createdAt: product.createdAt,
    updatedAt: product.updatedAt,
  );
}
