import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:food_analyzer_app/features/analysis/engines/analysis_engine.dart';
import 'package:food_analyzer_app/features/analysis/models/product_analysis_result.dart';
import 'package:food_analyzer_app/features/analysis/services/ingredient_canonicalizer.dart';
import 'package:food_analyzer_app/features/analysis/services/ingredient_matcher_service.dart';
import 'package:food_analyzer_app/features/product/controllers/product_detail_controller.dart';
import 'package:food_analyzer_app/features/scoring/adapters/product_scoring_input_adapter.dart';

/// Runs the full analysis pipeline on a product's ingredients_text.
///
/// Chains on [productDetailByIdProvider] so the product is only loaded once.
/// Returns null (not an error) when the product has no ingredients_text —
/// the UI should offer a "photograph the label" fallback in that case.
final productAnalysisProvider = FutureProvider.family<ProductAnalysisResult?, String>((
  ref,
  productId,
) async {
  final detail = await ref.watch(productDetailByIdProvider(productId).future);
  final product = detail.product!;

  final text = product.ingredientsText?.trim() ?? '';
  if (text.isEmpty) return null;
  _debugProductAnalysisLog(
    '[ProductDetailIngredients] raw ingredients_text length=${text.length}',
  );

  final repo = ref.read(productRepositoryProvider);
  final allIngredients = await repo.getAllIngredients();

  // Use the same matching + engine as the OCR analysis flow.
  const matcher = IngredientMatcherService();
  const engine = AnalysisEngine();
  final scoringCategory = const ProductScoringInputAdapter()
      .fromProduct(product)
      .categoryEvidence
      .resolvedCategory;
  final allergenTokens = IngredientCanonicalizer.extractAllergenTokens(text);

  final structuredIngredients = matcher.parseIngredients(text);
  _debugProductAnalysisLog(
    '[ProductDetailIngredients] parsed token count=${structuredIngredients.length}',
  );
  _debugProductAnalysisLog(
    '[ProductDetailIngredients] parsed tokens=$structuredIngredients',
  );
  _debugProductAnalysisLog(
    '[ProductDetailIngredients] allergen token count=${allergenTokens.length}',
  );
  if (structuredIngredients.isEmpty) {
    if (allergenTokens.isEmpty) return null;
    return ProductAnalysisResult(
      scoreLabel: AnalysisScoreLabel.orta,
      summary: '',
      allergenTokens: allergenTokens,
    );
  }

  final matchingResult = await matcher.matchIngredientTokens(
    structuredIngredients,
    allIngredients,
  );
  final result = engine.analyze(
    matchingResult,
    scoringCategory: scoringCategory,
  );
  final displayItemCount = _displayItemCount(result);
  final displayedUnknowns = result.unknownIngredients.toSet();
  final droppedTokens = matchingResult
      .getUnmatched()
      .map((match) => match.originalToken)
      .where((token) => !displayedUnknowns.contains(token))
      .toList(growable: false);
  _debugProductAnalysisLog(
    '[ProductDetailIngredients] matched display item count=$displayItemCount',
  );
  _debugProductAnalysisLog(
    '[ProductDetailIngredients] dropped token count=${droppedTokens.length} reason=sanitized_noise_or_duplicate tokens=$droppedTokens',
  );
  return result.copyWith(allergenTokens: allergenTokens);
});

int _displayItemCount(ProductAnalysisResult result) {
  final ids = <String>{};
  var count = 0;

  for (final ingredient in result.recognizedIngredients) {
    if (ids.add(ingredient.id)) count++;
  }
  for (final ingredient in result.detectedRiskIngredients) {
    if (ids.add(ingredient.id)) count++;
  }

  return count + result.unknownIngredients.toSet().length;
}

void _debugProductAnalysisLog(String message) {
  if (!kDebugMode) return;
  debugPrint(message);
}
