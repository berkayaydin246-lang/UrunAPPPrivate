import 'package:flutter/foundation.dart';
import 'package:food_analyzer_app/features/analysis/services/canonical_ingredient_risk_service.dart';
import 'package:food_analyzer_app/features/comparison/domain/comparison_metric.dart';
import 'package:food_analyzer_app/features/product/models/ingredient.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/product/models/product_review.dart';

@immutable
class ComparisonPickerRouteArgs {
  const ComparisonPickerRouteArgs({
    required this.sourceProductId,
    this.sourceProduct,
  });

  final String sourceProductId;
  final Product? sourceProduct;
}

@immutable
class ProductComparisonRouteArgs {
  const ProductComparisonRouteArgs({
    required this.sourceProductId,
    required this.comparedProductId,
    this.sourceProduct,
    this.comparedProduct,
  });

  final String sourceProductId;
  final String comparedProductId;
  final Product? sourceProduct;
  final Product? comparedProduct;
}

class ComparisonProductData {
  const ComparisonProductData({
    required this.product,
    this.review,
    this.ingredients = const <Ingredient>[],
    this.quantityLabel,
    required this.nutritionBasis,
  });

  final Product product;
  final ProductReview? review;
  final List<Ingredient> ingredients;
  final String? quantityLabel;
  final NutritionBasis nutritionBasis;

  String get ingredientTextOrFallback {
    final text = product.ingredientsText?.trim();
    if (text == null || text.isEmpty) {
      return 'Bilgi yok';
    }
    return text;
  }

  String get allergenText {
    return 'Bilgi yok';
  }

  List<String> get additiveLabels {
    final labels = <String>{};
    final assessment = const CanonicalIngredientRiskService().assessIngredients(
      ingredients,
    );
    for (final item in assessment.canonicalAdditives) {
      final ingredient = item.ingredient;
      final name = ingredient.name.trim();
      if (name.isEmpty) continue;
      if ((ingredient.eCode ?? '').trim().isNotEmpty) {
        labels.add('$name (${ingredient.eCode!.trim()})');
        continue;
      }
      if ((ingredient.additiveGroup ?? '').trim().isNotEmpty) {
        labels.add('$name - ${ingredient.additiveGroup!.trim()}');
      }
    }
    return labels.toList()..sort();
  }

  List<String> get warningLabels {
    final labels = <String>{};
    final assessment = const CanonicalIngredientRiskService().assessIngredients(
      ingredients,
    );
    for (final item in assessment.recognizedIngredients) {
      final ingredient = item.ingredient;
      final name = ingredient.name.trim();
      if (name.isEmpty) continue;
      final childWarning = ingredient.childWarning?.trim();
      if (childWarning != null && childWarning.isNotEmpty) {
        labels.add('$name: $childWarning');
      }
      if (item.riskLevelName == 'high' || item.riskLevelName == 'medium') {
        final label = item.riskLevelName == 'high'
            ? 'Etiketly değerlendirmesi: yüksek düzey'
            : 'Etiketly değerlendirmesi: orta düzey';
        labels.add('$name: $label');
      }
    }
    return labels.toList()..sort();
  }
}

class ProductComparison {
  const ProductComparison({
    required this.productA,
    required this.productB,
    required this.metrics,
  });

  final ComparisonProductData productA;
  final ComparisonProductData productB;
  final List<ComparisonMetric> metrics;

  factory ProductComparison.build({
    required Product productA,
    required Product productB,
    ProductReview? reviewA,
    ProductReview? reviewB,
    List<Ingredient> ingredientsA = const <Ingredient>[],
    List<Ingredient> ingredientsB = const <Ingredient>[],
  }) {
    final basisA = inferNutritionBasis(productA);
    final basisB = inferNutritionBasis(productB);

    return ProductComparison(
      productA: ComparisonProductData(
        product: productA,
        review: reviewA,
        ingredients: List<Ingredient>.unmodifiable(ingredientsA),
        quantityLabel: extractProductQuantityLabel(productA),
        nutritionBasis: basisA,
      ),
      productB: ComparisonProductData(
        product: productB,
        review: reviewB,
        ingredients: List<Ingredient>.unmodifiable(ingredientsB),
        quantityLabel: extractProductQuantityLabel(productB),
        nutritionBasis: basisB,
      ),
      metrics: List<ComparisonMetric>.unmodifiable([
        buildNumericComparisonMetric(
          key: 'energy',
          label: 'Enerji',
          productAValue: productA.nutrition?.energyKcal,
          productBValue: productB.nutrition?.energyKcal,
          displayUnit: 'kcal',
          basisA: basisA,
          basisB: basisB,
          preference: ComparisonPreference.neutral,
          equalityTolerance: 1,
        ),
        buildNumericComparisonMetric(
          key: 'fat',
          label: 'Yağ',
          productAValue: productA.nutrition?.fat,
          productBValue: productB.nutrition?.fat,
          displayUnit: 'g',
          basisA: basisA,
          basisB: basisB,
          preference: ComparisonPreference.neutral,
        ),
        buildNumericComparisonMetric(
          key: 'saturated_fat',
          label: 'Doymuş yağ',
          productAValue: productA.nutrition?.saturatedFat,
          productBValue: productB.nutrition?.saturatedFat,
          displayUnit: 'g',
          basisA: basisA,
          basisB: basisB,
          preference: ComparisonPreference.lowerIsBetter,
        ),
        buildNumericComparisonMetric(
          key: 'carbohydrates',
          label: 'Karbonhidrat',
          productAValue: productA.nutrition?.carbohydrates,
          productBValue: productB.nutrition?.carbohydrates,
          displayUnit: 'g',
          basisA: basisA,
          basisB: basisB,
          preference: ComparisonPreference.neutral,
        ),
        buildNumericComparisonMetric(
          key: 'sugars',
          label: 'Şeker',
          productAValue: productA.nutrition?.sugars,
          productBValue: productB.nutrition?.sugars,
          displayUnit: 'g',
          basisA: basisA,
          basisB: basisB,
          preference: ComparisonPreference.lowerIsBetter,
        ),
        buildNumericComparisonMetric(
          key: 'proteins',
          label: 'Protein',
          productAValue: productA.nutrition?.proteins,
          productBValue: productB.nutrition?.proteins,
          displayUnit: 'g',
          basisA: basisA,
          basisB: basisB,
          preference: ComparisonPreference.higherIsBetter,
        ),
        buildNumericComparisonMetric(
          key: 'fiber',
          label: 'Lif',
          productAValue: productA.nutrition?.fiber,
          productBValue: productB.nutrition?.fiber,
          displayUnit: 'g',
          basisA: basisA,
          basisB: basisB,
          preference: ComparisonPreference.higherIsBetter,
        ),
        buildNumericComparisonMetric(
          key: 'salt',
          label: 'Tuz',
          productAValue: productA.nutrition?.salt,
          productBValue: productB.nutrition?.salt,
          displayUnit: 'g',
          basisA: basisA,
          basisB: basisB,
          preference: ComparisonPreference.lowerIsBetter,
        ),
      ]),
    );
  }
}

NutritionBasis inferNutritionBasis(Product product) {
  final nutrition = product.nutrition;
  if (nutrition == null || !nutrition.hasAnyData) {
    return NutritionBasis.unknown;
  }

  final quantityLabel = extractProductQuantityLabel(product)?.toLowerCase();
  final hasLiquidUnit = _hasAnyToken(quantityLabel, _liquidUnitSignals);
  final hasSolidUnit =
      _hasAnyToken(quantityLabel, _solidUnitSignals) ||
      _hasAnyToken(quantityLabel, const {'adet'});

  if (hasLiquidUnit && !hasSolidUnit) {
    return NutritionBasis.per100ml;
  }
  if (hasSolidUnit && !hasLiquidUnit) {
    return NutritionBasis.per100g;
  }

  final tags = _normalizedSearchTokens(
    product.categoryTags ?? const <String>[],
  );
  final taxonomySignals = _normalizedSearchTokens([
    product.canonicalCategory,
    product.canonicalSubcategory,
  ]);
  final name = product.name.toLowerCase();

  final hasLiquidSignals =
      _containsAnySignal(tags, _liquidCategorySignals) ||
      _containsAnySignal(taxonomySignals, _liquidCategorySignals) ||
      _stringContainsSignal(name, _liquidNameSignals);
  final hasSolidSignals =
      _containsAnySignal(tags, _solidCategorySignals) ||
      _containsAnySignal(taxonomySignals, _solidCategorySignals) ||
      _stringContainsSignal(name, _solidNameSignals);

  if (hasLiquidSignals && !hasSolidSignals) {
    return NutritionBasis.per100ml;
  }
  if (hasSolidSignals && !hasLiquidSignals) {
    return NutritionBasis.per100g;
  }

  // The current app model stores imported nutrition values using the
  // established UI convention "100 g/ml başına", but it does not persist a
  // reliable concrete 100g vs 100ml basis for every product row.
  return NutritionBasis.per100Generic;
}

String? extractProductQuantityLabel(Product product) {
  final name = product.name.trim();
  if (name.isEmpty) return null;

  final match = RegExp(
    r'(\d+\s*x\s*\d+[\.,]?\d*\s*(?:kg|gr|g|lt|l|ml|cl)|\d+[\.,]?\d*\s*(?:kg|gr|g|lt|l|ml|cl)|\d+\s*adet)',
    caseSensitive: false,
  ).firstMatch(name);
  final value = match?.group(0)?.trim();
  if (value == null || value.isEmpty) {
    return null;
  }
  return value;
}

const _liquidUnitSignals = {'ml', 'cl', 'l', 'lt'};
const _solidUnitSignals = {'g', 'gr', 'kg'};
const _liquidCategorySignals = {
  'icecek',
  'icecekler',
  'gazli_icecek',
  'gazsiz_icecek',
  'enerji_icecekleri',
  'kahve',
  'cay',
  'meyve_suyu',
  'ayran',
  'kefir',
  'su',
  'maden_suyu',
  'beverage',
};
const _solidCategorySignals = {
  'atistirmalik',
  'biskuvi',
  'biskuvi_kek',
  'cips',
  'cips_kraker',
  'cikolata',
  'dondurma_tatli',
  'et_sarkuteri',
  'hazir_yemek',
  'kahvaltilik',
  'konserve',
  'makarna_bakliyat',
  'peynir',
  'peynir_yogurt',
  'sos',
  'sut',
  'sut_urunleri',
  'yogurt',
};
const _liquidNameSignals = {
  'içecek',
  'icecek',
  'kola',
  'cola',
  'gazoz',
  'soda',
  'limonata',
  'meyve suyu',
  'enerji içeceği',
  'enerji icecegi',
  'ayran',
  'kefir',
  'su',
  'maden suyu',
  'çay',
  'cay',
  'kahve',
};
const _solidNameSignals = {
  'cips',
  'kraker',
  'bisküvi',
  'biskuvi',
  'çikolata',
  'cikolata',
  'gofret',
  'yoğurt',
  'yogurt',
  'peynir',
  'makarna',
  'salam',
  'sucuk',
  'sosis',
  'dondurma',
  'puding',
};

List<String> _normalizedSearchTokens(Iterable<String?> values) {
  final tokens = <String>[];
  for (final value in values) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) continue;
    tokens.add(normalized);
  }
  return tokens;
}

bool _containsAnySignal(Iterable<String> haystack, Set<String> signals) {
  for (final value in haystack) {
    if (_stringContainsSignal(value, signals)) {
      return true;
    }
  }
  return false;
}

bool _stringContainsSignal(String haystack, Set<String> signals) {
  final normalized = haystack.trim().toLowerCase();
  if (normalized.isEmpty) return false;

  for (final signal in signals) {
    if (normalized.contains(signal)) {
      return true;
    }
  }
  return false;
}

bool _hasAnyToken(String? value, Set<String> tokens) {
  final normalized = value?.trim().toLowerCase();
  if (normalized == null || normalized.isEmpty) return false;

  for (final token in tokens) {
    final pattern = RegExp(
      '(^|[^a-z])${RegExp.escape(token)}'
      r'($|[^a-z])',
    );
    if (pattern.hasMatch(normalized)) {
      return true;
    }
  }
  return false;
}
