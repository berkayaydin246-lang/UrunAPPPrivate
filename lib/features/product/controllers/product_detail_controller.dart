import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/product/models/product_review.dart';
import 'package:food_analyzer_app/features/product/models/ingredient.dart';
import 'package:food_analyzer_app/features/product/repositories/product_repository.dart';

/// Provide ProductRepository as a singleton
final productRepositoryProvider = Provider((_) => const ProductRepository());

/// Product detail state containing all data needed for the detail screen
class ProductDetailState {
  final Product? product;
  final ProductReview? review;
  final List<Ingredient> ingredients;
  final bool isLoading;
  final String? error;

  ProductDetailState({
    this.product,
    this.review,
    this.ingredients = const [],
    this.isLoading = false,
    this.error,
  });

  ProductDetailState copyWith({
    Product? product,
    ProductReview? review,
    List<Ingredient>? ingredients,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return ProductDetailState(
      product: product ?? this.product,
      review: review ?? this.review,
      ingredients: ingredients ?? this.ingredients,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }

  bool get isEmpty => product == null;
  bool get hasError => error != null;
}

/// Notifier for managing product detail data
class ProductDetailNotifier extends StateNotifier<ProductDetailState> {
  final ProductRepository _repository;

  ProductDetailNotifier(this._repository) : super(ProductDetailState());

  /// Load product detail by ID
  Future<void> loadProductDetail(String productId) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      // Fetch product
      final product = await _repository.getProductById(productId);
      if (product == null) {
        state = state.copyWith(error: 'Ürün bulunamadı', isLoading: false);
        return;
      }

      // Fetch review and ingredients in parallel
      final reviewFuture = _repository.getProductReviewByProductId(productId);
      final ingredientsFuture = _repository.getProductIngredients(productId);

      final results = await Future.wait([reviewFuture, ingredientsFuture]);
      final review = results[0] as ProductReview?;
      final ingredients = results[1] as List<Ingredient>;

      state = ProductDetailState(
        product: product,
        review: review,
        ingredients: ingredients,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(error: e.toString(), isLoading: false);
    }
  }

  /// Clear state
  void clear() {
    state = ProductDetailState();
  }
}

/// Provide product detail notifier
final productDetailProvider =
    StateNotifierProvider<ProductDetailNotifier, ProductDetailState>(
      (ref) => ProductDetailNotifier(ref.watch(productRepositoryProvider)),
    );

/// Async provider for loading product detail by ID
final productDetailByIdProvider =
    FutureProvider.family<ProductDetailState, String>((ref, productId) async {
      final repository = ref.watch(productRepositoryProvider);

      // Fetch product
      final product = await repository.getProductById(productId);
      if (product == null) {
        throw Exception('Ürün bulunamadı');
      }

      // Fetch review and ingredients in parallel
      final review = await repository.getProductReviewByProductId(productId);
      final ingredients = await repository.getProductIngredients(productId);

      return ProductDetailState(
        product: product,
        review: review,
        ingredients: ingredients,
      );
    });
