import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/core/theme/app_theme.dart';
import 'package:food_analyzer_app/features/product/controllers/product_detail_controller.dart';
import 'package:food_analyzer_app/features/product/models/ingredient.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/product/models/product_review.dart';
import 'package:food_analyzer_app/features/product/product_page.dart';
import 'package:food_analyzer_app/features/product/repositories/product_repository.dart';
import 'package:food_analyzer_app/features/user_library/models/favorite_product_entry.dart';
import 'package:food_analyzer_app/features/user_library/models/local_product_snapshot.dart';
import 'package:food_analyzer_app/features/user_library/models/product_activity_entry.dart';
import 'package:food_analyzer_app/features/user_library/repositories/user_product_library_repository.dart';

void main() {
  testWidgets('Product detail shows the compare action', (tester) async {
    final product = _product();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          productRepositoryProvider.overrideWithValue(
            _FakeProductRepository(product: product),
          ),
          userProductLibraryRepositoryProvider.overrideWithValue(
            _NoopUserLibraryRepository(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme(),
          home: const ProductScreen(productId: 'p1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('product-compare-button')),
      findsOneWidget,
    );
    expect(find.text('Karşılaştır'), findsOneWidget);
  });
}

Product _product() {
  final now = DateTime.utc(2026, 6, 26, 12);
  return Product(
    id: 'p1',
    name: 'Coca Cola Zero Sugar 1 L',
    brand: 'Coca Cola',
    verificationStatus: 'verified',
    categoryTags: const ['icecekler'],
    createdAt: now,
    updatedAt: now,
  );
}

class _FakeProductRepository extends ProductRepository {
  _FakeProductRepository({required this.product});

  final Product product;

  @override
  Future<Product?> getProductById(String id) async => product;

  @override
  Future<ProductReview?> getProductReviewByProductId(String productId) async =>
      null;

  @override
  Future<List<Ingredient>> getProductIngredients(String productId) async =>
      const <Ingredient>[];

  @override
  Future<List<Ingredient>> getAllIngredients() async => const <Ingredient>[];
}

class _NoopUserLibraryRepository implements UserProductLibraryRepository {
  @override
  Future<void> addFavorite(LocalProductSnapshot product) async {}

  @override
  Future<void> clearRecentActivity({ProductActivityType? type}) async {}

  @override
  Future<List<FavoriteProductEntry>> getFavorites() async =>
      const <FavoriteProductEntry>[];

  @override
  Future<List<ProductActivityEntry>> getRecentActivity({
    ProductActivityType? type,
    int? limit,
  }) async => const <ProductActivityEntry>[];

  @override
  Future<bool> isFavorite(String productId) async => false;

  @override
  Future<void> recordScannedProduct(LocalProductSnapshot product) async {}

  @override
  Future<void> recordViewedProduct(LocalProductSnapshot product) async {}

  @override
  Future<void> removeFavorite(String productId) async {}

  @override
  Future<bool> toggleFavorite(LocalProductSnapshot product) async => true;
}
