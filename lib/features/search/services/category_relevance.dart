import 'package:food_analyzer_app/features/imports/models/off_product.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/search/models/product_category.dart';
import 'package:food_analyzer_app/features/search/services/product_category_classifier.dart';

class CategoryMatchResult {
  final int score;
  final bool accepted;
  final bool hasStrongNegative;
  final bool hasRequiredSignal;

  const CategoryMatchResult({
    required this.score,
    required this.accepted,
    required this.hasStrongNegative,
    required this.hasRequiredSignal,
  });
}

class CategoryRelevance {
  static const int acceptThreshold = 5;

  static CategoryMatchResult evaluateProduct(
    Product product,
    ProductCategory category,
  ) {
    final classification = ProductCategoryClassifier.classify(
      name: product.name,
      brand: product.brand,
      searchKeywords: product.searchKeywords,
      categoryTags: product.categoryTags,
      ingredientsText: product.ingredientsText,
    );
    final decision = _bestDecision(classification, category.databaseTags);

    final score = decision?.score ?? 0;
    final hasStrongNegative = decision?.strongNegative ?? false;
    final accepted = decision?.accepted ?? false;
    final hasRequiredSignal = accepted;

    return CategoryMatchResult(
      score: score,
      accepted: accepted,
      hasStrongNegative: hasStrongNegative,
      hasRequiredSignal: hasRequiredSignal,
    );
  }

  static CategoryMatchResult evaluateOffProduct(
    OffProduct product,
    ProductCategory category,
  ) {
    final classification = ProductCategoryClassifier.classify(
      name: product.name ?? '',
      brand: product.brand,
      offCategories: product.categoriesText != null
          ? [product.categoriesText!]
          : null,
      offCategoryTags: product.categories,
    );
    final decision = _bestDecision(classification, category.databaseTags);

    final score = decision?.score ?? 0;
    final hasStrongNegative = decision?.strongNegative ?? false;
    final accepted = decision?.accepted ?? false;
    final hasRequiredSignal = accepted;

    return CategoryMatchResult(
      score: score,
      accepted: accepted,
      hasStrongNegative: hasStrongNegative,
      hasRequiredSignal: hasRequiredSignal,
    );
  }

  static CategoryTagDecision? _bestDecision(
    CategoryClassificationResult classification,
    List<String> databaseTags,
  ) {
    CategoryTagDecision? best;
    for (final tag in databaseTags) {
      final decision = classification.decisions[tag];
      if (decision == null) continue;
      if (best == null || decision.score > best.score) {
        best = decision;
      }
    }
    return best;
  }
}
