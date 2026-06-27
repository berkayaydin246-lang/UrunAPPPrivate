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
import 'package:food_analyzer_app/features/user_library/controllers/user_product_library_controller.dart';
import 'package:food_analyzer_app/features/user_library/models/favorite_product_entry.dart';
import 'package:food_analyzer_app/features/user_library/models/local_product_snapshot.dart';
import 'package:food_analyzer_app/features/user_library/models/product_activity_entry.dart';
import 'package:food_analyzer_app/features/user_library/repositories/user_product_library_repository.dart';

void main() {
  group('Product favorite action', () {
    testWidgets(
      'Product Detail displays a favorite action and reflects current state',
      (tester) async {
        final productRepository = _FakeProductRepository(
          product: _product(id: 'p1'),
        );
        final userLibraryRepository = _SpyUserLibraryRepository();
        await userLibraryRepository.addFavorite(
          localSnapshotFromProduct(_product(id: 'p1')),
        );

        await _pumpProductPage(
          tester,
          productRepository: productRepository,
          userLibraryRepository: userLibraryRepository,
        );

        expect(
          find.byKey(const ValueKey('product-favorite-action')),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
      },
    );

    testWidgets('toggling favorite adds and removes exactly one entry', (
      tester,
    ) async {
      final product = _product(id: 'p1');
      final productRepository = _FakeProductRepository(product: product);
      final userLibraryRepository = _SpyUserLibraryRepository();

      await _pumpProductPage(
        tester,
        productRepository: productRepository,
        userLibraryRepository: userLibraryRepository,
      );

      expect(await userLibraryRepository.getFavorites(), isEmpty);

      await tester.tap(find.byKey(const ValueKey('product-favorite-action')));
      await tester.pumpAndSettle();

      expect(await userLibraryRepository.getFavorites(), hasLength(1));
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('product-favorite-action')));
      await tester.pumpAndSettle();

      expect(await userLibraryRepository.getFavorites(), isEmpty);
      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
    });

    testWidgets(
      'favorite-state changes do not refetch unrelated product detail data',
      (tester) async {
        final product = _product(id: 'p1');
        final productRepository = _FakeProductRepository(product: product);
        final userLibraryRepository = _SpyUserLibraryRepository();

        await _pumpProductPage(
          tester,
          productRepository: productRepository,
          userLibraryRepository: userLibraryRepository,
        );

        final initialDetailFetches = productRepository.getProductByIdCalls;

        await tester.tap(find.byKey(const ValueKey('product-favorite-action')));
        await tester.pumpAndSettle();

        expect(productRepository.getProductByIdCalls, initialDetailFetches);
        expect(productRepository.getReviewCalls, 1);
        expect(productRepository.getIngredientsCalls, 1);
      },
    );

    testWidgets('viewed activity is not recorded repeatedly on rebuild', (
      tester,
    ) async {
      final product = _product(id: 'p1');
      final productRepository = _FakeProductRepository(product: product);
      final userLibraryRepository = _SpyUserLibraryRepository();

      await _pumpProductPage(
        tester,
        productRepository: productRepository,
        userLibraryRepository: userLibraryRepository,
      );

      expect(userLibraryRepository.recordViewedCallCount, 1);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            productRepositoryProvider.overrideWithValue(productRepository),
            userProductLibraryRepositoryProvider.overrideWithValue(
              userLibraryRepository,
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme(),
            home: const ProductScreen(productId: 'p1'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(userLibraryRepository.recordViewedCallCount, 1);

      await tester.tap(find.byKey(const ValueKey('product-favorite-action')));
      await tester.pumpAndSettle();

      expect(userLibraryRepository.recordViewedCallCount, 1);
    });

    testWidgets(
      'opening the same product in a new Product Detail instance refreshes viewed order',
      (tester) async {
        final product = _product(id: 'p1');
        final productRepository = _FakeProductRepository(product: product);
        final userLibraryRepository = _SpyUserLibraryRepository();
        final container = ProviderContainer(
          overrides: [
            productRepositoryProvider.overrideWithValue(productRepository),
            userProductLibraryRepositoryProvider.overrideWithValue(
              userLibraryRepository,
            ),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: AppTheme.lightTheme(),
              home: const ProductScreen(
                key: ValueKey('product-screen-1'),
                productId: 'p1',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await container
            .read(recentProductActivityProvider.notifier)
            .recordViewedProduct(
              const LocalProductSnapshot(
                productId: 'p2',
                name: 'İkinci Ürün',
                brand: 'Marka',
                imageUrl: 'https://img.example.test/p2.png',
                categoryTags: ['icecek'],
              ),
            );

        expect(
          container
              .read(viewedProductActivityEntriesProvider)
              .map((entry) => entry.product.productId),
          ['p2', 'p1'],
        );
        final callsBeforeSecondOpen =
            userLibraryRepository.recordViewedCallCount;

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: AppTheme.lightTheme(),
              home: const ProductScreen(
                key: ValueKey('product-screen-2'),
                productId: 'p1',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          container
              .read(viewedProductActivityEntriesProvider)
              .map((entry) => entry.product.productId),
          ['p1', 'p2'],
        );
        expect(
          userLibraryRepository.recordViewedCallCount,
          callsBeforeSecondOpen + 1,
        );
      },
    );
  });
}

Future<void> _pumpProductPage(
  WidgetTester tester, {
  required _FakeProductRepository productRepository,
  required _SpyUserLibraryRepository userLibraryRepository,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        productRepositoryProvider.overrideWithValue(productRepository),
        userProductLibraryRepositoryProvider.overrideWithValue(
          userLibraryRepository,
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme(),
        home: const ProductScreen(productId: 'p1'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Product _product({required String id}) {
  final now = DateTime.utc(2026, 6, 26, 12);
  return Product(
    id: id,
    name: 'Coca Cola Zero Sugar',
    brand: 'Coca Cola',
    imageUrl: 'https://img.example.test/$id.png',
    verificationStatus: 'verified',
    createdAt: now,
    updatedAt: now,
    categoryTags: const ['icecek'],
  );
}

class _FakeProductRepository extends ProductRepository {
  _FakeProductRepository({required this.product});

  final Product product;
  int getProductByIdCalls = 0;
  int getReviewCalls = 0;
  int getIngredientsCalls = 0;

  @override
  Future<Product?> getProductById(String id) async {
    getProductByIdCalls++;
    return product.id == id ? product : null;
  }

  @override
  Future<ProductReview?> getProductReviewByProductId(String productId) async {
    getReviewCalls++;
    return null;
  }

  @override
  Future<List<Ingredient>> getProductIngredients(String productId) async {
    getIngredientsCalls++;
    return const <Ingredient>[];
  }

  @override
  Future<List<Ingredient>> getAllIngredients() async {
    return const <Ingredient>[];
  }
}

class _SpyUserLibraryRepository implements UserProductLibraryRepository {
  _SpyUserLibraryRepository()
    : _delegate = LocalUserProductLibraryRepository(
        storage: _MemoryStorage(),
        clock: _TestClock().call,
      );

  final LocalUserProductLibraryRepository _delegate;
  int recordViewedCallCount = 0;

  @override
  Future<void> addFavorite(LocalProductSnapshot product) {
    return _delegate.addFavorite(product);
  }

  @override
  Future<void> clearRecentActivity({ProductActivityType? type}) {
    return _delegate.clearRecentActivity(type: type);
  }

  @override
  Future<List<FavoriteProductEntry>> getFavorites() {
    return _delegate.getFavorites();
  }

  @override
  Future<List<ProductActivityEntry>> getRecentActivity({
    ProductActivityType? type,
    int? limit,
  }) {
    return _delegate.getRecentActivity(type: type, limit: limit);
  }

  @override
  Future<bool> isFavorite(String productId) {
    return _delegate.isFavorite(productId);
  }

  @override
  Future<void> recordScannedProduct(LocalProductSnapshot product) {
    return _delegate.recordScannedProduct(product);
  }

  @override
  Future<void> recordViewedProduct(LocalProductSnapshot product) {
    recordViewedCallCount++;
    return _delegate.recordViewedProduct(product);
  }

  @override
  Future<void> removeFavorite(String productId) {
    return _delegate.removeFavorite(productId);
  }

  @override
  Future<bool> toggleFavorite(LocalProductSnapshot product) {
    return _delegate.toggleFavorite(product);
  }
}

class _TestClock {
  _TestClock() : _current = DateTime.utc(2026, 6, 26, 13);

  DateTime _current;

  DateTime call() {
    final result = _current;
    _current = _current.add(const Duration(minutes: 1));
    return result;
  }
}

class _MemoryStorage implements UserProductLibraryStorage {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> readString(String key) async => _values[key];

  @override
  Future<void> writeString(String key, String value) async {
    _values[key] = value;
  }
}
