import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:food_analyzer_app/core/theme/app_theme.dart';
import 'package:food_analyzer_app/core/widgets/fresh_cached_product_image.dart';
import 'package:food_analyzer_app/features/home/home_page.dart';
import 'package:food_analyzer_app/features/history/history_page.dart';
import 'package:food_analyzer_app/features/product/controllers/product_detail_controller.dart';
import 'package:food_analyzer_app/features/product/models/ingredient.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/product/models/product_review.dart';
import 'package:food_analyzer_app/features/product/product_page.dart';
import 'package:food_analyzer_app/features/product/repositories/product_repository.dart';
import 'package:food_analyzer_app/features/search/search_page.dart';
import 'package:food_analyzer_app/features/user_library/models/local_product_snapshot.dart';
import 'package:food_analyzer_app/features/user_library/repositories/user_product_library_repository.dart';

void main() {
  setUpAll(_mockPathProvider);

  group('User library UI', () {
    testWidgets(
      'library page contains Favoriler, Goruntulenenler and Tarananlar',
      (tester) async {
        await _pumpLibraryPage(
          tester,
          userLibraryRepository: await _buildSeededLibraryRepository(),
        );

        expect(find.text('Favoriler'), findsOneWidget);
        expect(find.text('Görüntülenenler'), findsOneWidget);
        expect(find.text('Tarananlar'), findsOneWidget);
      },
    );

    testWidgets(
      'favorites render from local snapshots without a network dependency',
      (tester) async {
        final libraryRepository = await _buildSeededLibraryRepository(
          favorites: [_snapshot('fav-1', name: 'Yer Fistigi Ezmesi')],
        );
        final productRepository = _FakeProductRepository();

        await _pumpLibraryPage(
          tester,
          userLibraryRepository: libraryRepository,
          productRepository: productRepository,
        );

        expect(find.text('Yer Fistigi Ezmesi'), findsOneWidget);
        expect(find.byType(ProductThumbnail), findsOneWidget);
        expect(productRepository.getProductByIdCalls, 0);
      },
    );

    testWidgets('favorite removal updates immediately', (tester) async {
      final libraryRepository = await _buildSeededLibraryRepository(
        favorites: [_snapshot('fav-1')],
      );

      await _pumpLibraryPage(tester, userLibraryRepository: libraryRepository);

      expect(find.byKey(const ValueKey('favorite-tile-fav-1')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('favorite-remove-fav-1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('favorite-tile-fav-1')), findsNothing);
      expect(find.text('Henüz favori ürünün yok'), findsOneWidget);
    });

    testWidgets('viewed and scanned lists remain separate', (tester) async {
      final libraryRepository = await _buildSeededLibraryRepository(
        viewed: [_snapshot('viewed-1', name: 'Goruntulenen Urun')],
        scanned: [_snapshot('scanned-1', name: 'Taranan Urun')],
      );

      await _pumpLibraryPage(tester, userLibraryRepository: libraryRepository);

      await tester.tap(find.text('Görüntülenenler'));
      await tester.pumpAndSettle();
      expect(find.text('Goruntulenen Urun'), findsOneWidget);
      expect(find.text('Taranan Urun'), findsNothing);

      await tester.tap(find.text('Tarananlar'));
      await tester.pumpAndSettle();
      expect(find.text('Taranan Urun'), findsOneWidget);
      expect(find.text('Goruntulenen Urun'), findsNothing);
    });

    testWidgets(
      'clear viewed history preserves scanned history and favorites',
      (tester) async {
        final libraryRepository = await _buildSeededLibraryRepository(
          favorites: [_snapshot('fav-1', name: 'Favori Urun')],
          viewed: [_snapshot('viewed-1', name: 'Goruntulenen Urun')],
          scanned: [_snapshot('scanned-1', name: 'Taranan Urun')],
        );

        await _pumpLibraryPage(
          tester,
          userLibraryRepository: libraryRepository,
        );

        await tester.tap(find.text('Görüntülenenler'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('clear-viewed-history-button')),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Görüntüleme geçmişi temizlensin mi?'),
          findsOneWidget,
        );

        await tester.tap(find.text('Temizle'));
        await tester.pumpAndSettle();

        expect(find.text('Henüz görüntüleme geçmişin yok'), findsOneWidget);

        await tester.tap(find.text('Tarananlar'));
        await tester.pumpAndSettle();
        expect(find.text('Taranan Urun'), findsOneWidget);

        await tester.tap(find.text('Favoriler'));
        await tester.pumpAndSettle();
        expect(find.text('Favori Urun'), findsOneWidget);
      },
    );

    testWidgets(
      'clear scanned history preserves viewed history and favorites',
      (tester) async {
        final libraryRepository = await _buildSeededLibraryRepository(
          favorites: [_snapshot('fav-1', name: 'Favori Urun')],
          viewed: [_snapshot('viewed-1', name: 'Goruntulenen Urun')],
          scanned: [_snapshot('scanned-1', name: 'Taranan Urun')],
        );

        await _pumpLibraryPage(
          tester,
          userLibraryRepository: libraryRepository,
        );

        await tester.tap(find.text('Tarananlar'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('clear-scanned-history-button')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Tarama geçmişi temizlensin mi?'), findsOneWidget);

        await tester.tap(find.text('Temizle'));
        await tester.pumpAndSettle();

        expect(find.text('Henüz tarama geçmişin yok'), findsOneWidget);

        await tester.tap(find.text('Görüntülenenler'));
        await tester.pumpAndSettle();
        expect(find.text('Goruntulenen Urun'), findsOneWidget);

        await tester.tap(find.text('Favoriler'));
        await tester.pumpAndSettle();
        expect(find.text('Favori Urun'), findsOneWidget);
      },
    );

    testWidgets('confirmation is required before clearing', (tester) async {
      final libraryRepository = await _buildSeededLibraryRepository(
        viewed: [_snapshot('viewed-1', name: 'Goruntulenen Urun')],
      );

      await _pumpLibraryPage(tester, userLibraryRepository: libraryRepository);

      await tester.tap(find.text('Görüntülenenler'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('clear-viewed-history-button')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Görüntüleme geçmişi temizlensin mi?'), findsOneWidget);
      expect(
        find.text('Bu işlem favorilerini ve tarama geçmişini etkilemez.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Vazgeç'));
      await tester.pumpAndSettle();

      expect(find.text('Goruntulenen Urun'), findsOneWidget);
      expect(find.byKey(const ValueKey('viewed-history-list')), findsOneWidget);
    });

    testWidgets('empty states render correctly', (tester) async {
      await _pumpLibraryPage(
        tester,
        userLibraryRepository: await _buildSeededLibraryRepository(),
      );

      expect(find.text('Henüz favori ürünün yok'), findsOneWidget);

      await tester.tap(find.text('Görüntülenenler'));
      await tester.pumpAndSettle();
      expect(find.text('Henüz görüntüleme geçmişin yok'), findsOneWidget);

      await tester.tap(find.text('Tarananlar'));
      await tester.pumpAndSettle();
      expect(find.text('Henüz tarama geçmişin yok'), findsOneWidget);
    });

    testWidgets('snapshot tap navigates by product ID', (tester) async {
      final libraryRepository = await _buildSeededLibraryRepository(
        favorites: [_snapshot('p1', name: 'Cikolata')],
      );
      final productRepository = _FakeProductRepository(
        products: {'p1': _product(id: 'p1', name: 'Cikolata')},
      );

      await _pumpLibraryPage(
        tester,
        userLibraryRepository: libraryRepository,
        productRepository: productRepository,
      );

      await tester.tap(find.byKey(const ValueKey('favorite-tile-p1')));
      await tester.pumpAndSettle();

      expect(find.text('detail:p1'), findsOneWidget);
    });

    testWidgets('missing products fail safely', (tester) async {
      final libraryRepository = await _buildSeededLibraryRepository(
        favorites: [_snapshot('missing-1', name: 'Kayip Urun')],
      );
      final productRepository = _FakeProductRepository(products: const {});

      await _pumpLibraryPage(
        tester,
        userLibraryRepository: libraryRepository,
        productRepository: productRepository,
      );

      await tester.tap(find.byKey(const ValueKey('favorite-tile-missing-1')));
      await tester.pumpAndSettle();

      expect(
        find.text('Bu ürün artık veritabanında bulunamıyor.'),
        findsOneWidget,
      );
      expect(find.text('Kitaplığım'), findsOneWidget);
      expect(find.text('detail:missing-1'), findsNothing);
    });

    testWidgets(
      'product images use the existing optimized thumbnail implementation',
      (tester) async {
        final libraryRepository = await _buildSeededLibraryRepository(
          favorites: [_snapshot('fav-1')],
          viewed: [_snapshot('viewed-1')],
        );

        await _pumpLibraryPage(
          tester,
          userLibraryRepository: libraryRepository,
        );

        expect(find.byType(ProductThumbnail), findsWidgets);
        expect(find.byType(CircularProgressIndicator), findsNothing);
      },
    );

    testWidgets('no render overflow occurs on the current Android test size', (
      tester,
    ) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;

      final libraryRepository = await _buildSeededLibraryRepository(
        favorites: List.generate(
          6,
          (index) => _snapshot('fav-$index', name: 'Favori Urun $index'),
        ),
      );

      await _pumpLibraryPage(tester, userLibraryRepository: libraryRepository);

      expect(tester.takeException(), isNull);
    });

    testWidgets('library entry point is visible on the home page', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.lightTheme(useGoogleFonts: false),
            home: const SearchScreen(),
          ),
        ),
      );

      expect(find.byTooltip('Kitaplığım'), findsOneWidget);
    });

    testWidgets('Kitaplığım card is visible on HomeScreen', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme(useGoogleFonts: false),
          home: const HomeScreen(),
        ),
      );

      expect(find.text('Kitaplığım'), findsOneWidget);
    });

    testWidgets('history wrapper route shows the user library page', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.lightTheme(useGoogleFonts: false),
            home: const HistoryScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Kitaplığım'), findsOneWidget);
      expect(find.text('Favoriler'), findsOneWidget);
    });

    testWidgets(
      'recently viewed list updates immediately after returning from Product Detail',
      (tester) async {
        final router = await _pumpLibraryPage(
          tester,
          userLibraryRepository: await _buildSeededLibraryRepository(),
          productRepository: _FakeProductRepository(
            products: {'p1': _product(id: 'p1', name: 'Anında Görünen Ürün')},
          ),
          useRealProductScreen: true,
        );

        router.push('/product/p1');
        await tester.pumpAndSettle();

        expect(find.text('Ürün Detayı'), findsOneWidget);

        await tester.tap(find.byIcon(Icons.arrow_back));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Görüntülenenler'));
        await tester.pumpAndSettle();

        expect(find.text('Anında Görünen Ürün'), findsOneWidget);
      },
    );
  });
}

Future<GoRouter> _pumpLibraryPage(
  WidgetTester tester, {
  required UserProductLibraryRepository userLibraryRepository,
  ProductRepository? productRepository,
  bool useRealProductScreen = false,
  String initialLocation = '/history',
}) async {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        name: 'history',
        path: '/history',
        builder: (context, state) => const HistoryScreen(),
      ),
      GoRoute(
        name: 'search',
        path: '/search',
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('search'))),
      ),
      GoRoute(
        name: 'barcode',
        path: '/barcode',
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('barcode'))),
      ),
      GoRoute(
        path: '/product/:id',
        builder: (context, state) => useRealProductScreen
            ? ProductScreen(productId: state.pathParameters['id']!)
            : Scaffold(
                body: Center(
                  child: Text('detail:${state.pathParameters['id']}'),
                ),
              ),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        userProductLibraryRepositoryProvider.overrideWithValue(
          userLibraryRepository,
        ),
        productRepositoryProvider.overrideWithValue(
          productRepository ?? _FakeProductRepository(),
        ),
      ],
      child: MaterialApp.router(
        theme: AppTheme.lightTheme(useGoogleFonts: false),
        routerConfig: router,
      ),
    ),
  );
  addTearDown(router.dispose);
  await tester.pumpAndSettle();
  return router;
}

Future<LocalUserProductLibraryRepository> _buildSeededLibraryRepository({
  List<LocalProductSnapshot> favorites = const [],
  List<LocalProductSnapshot> viewed = const [],
  List<LocalProductSnapshot> scanned = const [],
}) async {
  final repository = LocalUserProductLibraryRepository(
    storage: _MemoryStorage(),
    clock: _TestClock().call,
  );

  for (final favorite in favorites) {
    await repository.addFavorite(favorite);
  }
  for (final item in viewed) {
    await repository.recordViewedProduct(item);
  }
  for (final item in scanned) {
    await repository.recordScannedProduct(item);
  }

  return repository;
}

LocalProductSnapshot _snapshot(
  String id, {
  String? name,
  String? brand,
  String? imageUrl,
}) {
  return LocalProductSnapshot(
    productId: id,
    name: name ?? 'Urun $id',
    brand: brand ?? 'Marka',
    imageUrl: imageUrl ?? 'https://img.example.test/$id.png',
    categoryTags: const ['icecek'],
  );
}

Product _product({
  required String id,
  String? name,
  String? brand,
  String? imageUrl,
}) {
  final now = DateTime.utc(2026, 6, 26, 12);
  return Product(
    id: id,
    name: name ?? 'Urun $id',
    brand: brand ?? 'Marka',
    imageUrl: imageUrl ?? 'https://img.example.test/$id.png',
    verificationStatus: 'verified',
    createdAt: now,
    updatedAt: now,
    categoryTags: const ['icecek'],
  );
}

class _FakeProductRepository extends ProductRepository {
  _FakeProductRepository({Map<String, Product>? products})
    : _products = products ?? <String, Product>{};

  final Map<String, Product> _products;
  int getProductByIdCalls = 0;

  @override
  Future<Product?> getProductById(String id) async {
    getProductByIdCalls++;
    return _products[id];
  }

  @override
  Future<ProductReview?> getProductReviewByProductId(String productId) async {
    return null;
  }

  @override
  Future<List<Ingredient>> getProductIngredients(String productId) async {
    return const <Ingredient>[];
  }

  @override
  Future<List<Ingredient>> getAllIngredients() async {
    return const <Ingredient>[];
  }
}

class _TestClock {
  _TestClock() : _current = DateTime.utc(2026, 6, 26, 12);

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

void _mockPathProvider() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final tempDir = Directory.systemTemp.createTempSync(
    'freshscan_user_library_test_',
  );
  const channel = MethodChannel('plugins.flutter.io/path_provider');

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'getTemporaryDirectory':
          case 'getApplicationSupportDirectory':
          case 'getApplicationDocumentsDirectory':
            return tempDir.path;
          default:
            return tempDir.path;
        }
      });
}
