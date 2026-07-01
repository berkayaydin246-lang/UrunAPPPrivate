import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:food_analyzer_app/core/errors/user_message.dart';
import 'package:food_analyzer_app/features/analysis/models/ingredient_match.dart';
import 'package:food_analyzer_app/features/analysis/services/ingredient_matcher_service.dart';
import 'package:food_analyzer_app/features/product/models/ingredient.dart';
import 'package:food_analyzer_app/features/product/repositories/product_repository.dart';

/// State for ingredient matching
class IngredientMatchingState {
  final String? ocrText;
  final IngredientMatchingResult? result;
  final bool isProcessing;
  final String? error;

  IngredientMatchingState({
    this.ocrText,
    this.result,
    this.isProcessing = false,
    this.error,
  });

  IngredientMatchingState copyWith({
    String? ocrText,
    IngredientMatchingResult? result,
    bool? isProcessing,
    String? error,
    bool clearError = false,
  }) {
    return IngredientMatchingState(
      ocrText: ocrText ?? this.ocrText,
      result: result ?? this.result,
      isProcessing: isProcessing ?? this.isProcessing,
      error: clearError ? null : (error ?? this.error),
    );
  }

  bool get hasResult => result != null;
  bool get hasError => error != null;
}

/// Notifier for ingredient matching
class IngredientMatchingNotifier
    extends StateNotifier<IngredientMatchingState> {
  final IngredientMatcherService _matcherService;
  final ProductRepository _repository;

  IngredientMatchingNotifier(this._matcherService, this._repository)
    : super(IngredientMatchingState());

  /// Match OCR text against ingredient database
  Future<void> matchIngredients(String ocrText) async {
    state = state.copyWith(isProcessing: true, error: null);

    try {
      // Fetch all ingredients from database
      // We'll create a method in ProductRepository for this
      final allIngredients = await _repository.getAllIngredients();

      // Match ingredients
      final result = await _matcherService.matchIngredients(
        ocrText,
        allIngredients,
      );

      state = state.copyWith(
        ocrText: ocrText,
        result: result,
        isProcessing: false,
      );
    } catch (e) {
      state = state.copyWith(
        error: UserMessage.forAnalysis(e),
        isProcessing: false,
      );
    }
  }

  /// Clear results
  void reset() {
    state = IngredientMatchingState();
  }

  /// Clear error message
  void clearError() {
    state = state.copyWith(error: null);
  }
}

/// Provide ProductRepository
final productRepositoryProvider = Provider((_) => const ProductRepository());

/// Provide IngredientMatcherService
final ingredientMatcherServiceProvider = Provider(
  (ref) => const IngredientMatcherService(),
);

/// Provide ingredient matching notifier
final ingredientMatchingProvider =
    StateNotifierProvider<IngredientMatchingNotifier, IngredientMatchingState>(
      (ref) => IngredientMatchingNotifier(
        ref.watch(ingredientMatcherServiceProvider),
        ref.watch(productRepositoryProvider),
      ),
    );

/// Async provider to fetch all ingredients
final allIngredientsProvider = FutureProvider<List<Ingredient>>((ref) async {
  final repository = ref.watch(productRepositoryProvider);
  return repository.getAllIngredients();
});
