import 'package:food_analyzer_app/features/product/models/nutrition_data.dart';
import 'package:food_analyzer_app/features/product_staging/models/product_candidate.dart';

/// Outcome of evaluating a [ProductCandidate]'s data completeness.
class ProductQualityResult {
  final int qualityScore;
  final List<String> missingFields;
  final String suggestedStatus;

  const ProductQualityResult({
    required this.qualityScore,
    required this.missingFields,
    required this.suggestedStatus,
  });
}

/// Deterministic, rule-based quality evaluator for staged product candidates.
///
/// It NEVER approves products. It only computes a completeness score, the list
/// of missing fields, and a suggested review status. Admin approval (a later
/// task) is what actually promotes a candidate into the `products` catalog.
class ProductCandidateQualityEvaluator {
  const ProductCandidateQualityEvaluator();

  // Field weights (sum can exceed 100; final score is clamped to 100).
  static const int _barcodeWeight = 15;
  static const int _nameWeight = 15;
  static const int _brandWeight = 10;
  static const int _frontImageWeight = 15;
  static const int _ingredientsWeight = 25;
  static const int _nutritionWeight = 20;
  static const int _categoryWeight = 10;

  // Minimum ingredients_text length to count as present.
  static const int _minIngredientsLength = 20;

  // Status thresholds.
  static const int _pendingThreshold = 75;
  static const int _needsReviewThreshold = 45;

  ProductQualityResult evaluate(ProductCandidate candidate) {
    var score = 0;
    final missing = <String>[];

    // Barcode
    if (_hasText(candidate.barcode)) {
      score += _barcodeWeight;
    } else {
      missing.add('barcode');
    }

    // Name
    if (_hasText(candidate.name)) {
      score += _nameWeight;
    } else {
      missing.add('name');
    }

    // Brand
    if (_hasText(candidate.brand)) {
      score += _brandWeight;
    } else {
      missing.add('brand');
    }

    // Front image
    if (_hasText(candidate.imageFrontUrl)) {
      score += _frontImageWeight;
    } else {
      missing.add('front_image');
    }

    // Ingredients
    if (_hasText(candidate.ingredientsText) &&
        candidate.ingredientsText!.trim().length > _minIngredientsLength) {
      score += _ingredientsWeight;
    } else {
      missing.add('ingredients');
    }

    // Nutrition
    if (_hasUsefulNutrition(candidate.nutritionJson)) {
      score += _nutritionWeight;
    } else {
      missing.add('nutrition');
    }

    // Category
    if (_hasText(candidate.categorySuggestion) ||
        (candidate.categoryTags?.isNotEmpty ?? false)) {
      score += _categoryWeight;
    } else {
      missing.add('category');
    }

    if (score > 100) score = 100;

    return ProductQualityResult(
      qualityScore: score,
      missingFields: missing,
      suggestedStatus: _statusFor(score),
    );
  }

  String _statusFor(int score) {
    if (score >= _pendingThreshold) return 'pending';
    if (score >= _needsReviewThreshold) return 'needs_review';
    return 'insufficient_data';
  }

  static bool _hasText(String? value) =>
      value != null && value.trim().isNotEmpty;

  static bool _hasUsefulNutrition(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return false;
    return NutritionData.fromMap(json).hasAnyData;
  }
}
