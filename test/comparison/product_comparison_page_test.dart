import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:food_analyzer_app/core/theme/app_theme.dart';
import 'package:food_analyzer_app/core/widgets/fresh_product_image.dart';
import 'package:food_analyzer_app/features/comparison/domain/product_comparison.dart';
import 'package:food_analyzer_app/features/comparison/pages/comparison_product_picker_page.dart';
import 'package:food_analyzer_app/features/comparison/pages/product_comparison_page.dart';
import 'package:food_analyzer_app/features/comparison/repositories/product_comparison_repository.dart';
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
  group('Comparison picker redesign', () {
    testWidgets('uses compact source summary and updated search placeholder', (
      tester,
    ) async {
      final source = _product(
        id: 'source',
        name: 'Kaynak Cips 150 G',
        brand: 'FreshScan',
        categoryTags: const ['cips'],
      );
      final completer = Completer<List<Product>>();
      final repository = _FakeComparisonRepository(
        findHandler: ({required source, query, limit = 40}) => completer.future,
      );

      await _pumpPickerPage(
        tester,
        source: source,
        comparisonRepository: repository,
      );

      expect(find.text('Ürün A'), findsNothing);
      expect(find.text('Kaynak Cips 150 G'), findsOneWidget);
      expect(find.text('Karşılaştırılacak ürün ara'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsWidgets);
    });
  });

  group('Comparison flow', () {
    testWidgets('navigates from product detail to picker to comparison', (
      tester,
    ) async {
      final productA = _product(
        id: 'a',
        name: 'Protein Yoğurt 150 G',
        brand: 'FreshScan',
        categoryTags: const ['yogurt'],
        nutrition: const {'proteins': 9.0, 'sugars': 3.0},
      );
      final productB = _product(
        id: 'b',
        name: 'Rakip Yoğurt 150 G',
        brand: 'Rakip',
        categoryTags: const ['yogurt'],
        nutrition: const {'proteins': 7.0, 'sugars': 5.0},
      );
      final router = _buildComparisonRouter();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            productRepositoryProvider.overrideWithValue(
              _FakeProductRepository(products: {'a': productA, 'b': productB}),
            ),
            productComparisonRepositoryProvider.overrideWithValue(
              _FakeComparisonRepository(
                findHandler: ({required source, query, limit = 40}) async => [
                  productB,
                ],
                createHandler: ({required productA, required productB}) async =>
                    ProductComparison.build(
                      productA: productA,
                      productB: productB,
                    ),
              ),
            ),
            userProductLibraryRepositoryProvider.overrideWithValue(
              _NoopUserLibraryRepository(),
            ),
          ],
          child: MaterialApp.router(
            theme: AppTheme.lightTheme(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const ValueKey('product-compare-button')),
      );
      await tester.tap(find.byKey(const ValueKey('product-compare-button')));
      await tester.pumpAndSettle();

      expect(find.text('Benzer ürünler'), findsOneWidget);
      expect(find.text('Karşılaştırılacak ürün ara'), findsOneWidget);

      await tester.tap(find.text('Rakip Yoğurt 150 G'));
      await tester.pumpAndSettle();

      expect(find.text('Ürün Karşılaştırma'), findsOneWidget);
      expect(find.text('Protein Yoğurt 150 G'), findsOneWidget);
      expect(find.text('Rakip Yoğurt 150 G'), findsOneWidget);
    });

    testWidgets('removes old labels and renders product headers side by side', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final productA = _product(
        id: 'a',
        name: 'Protein Yoğurt 150 G',
        brand: 'FreshScan',
        categoryTags: const ['yogurt'],
        nutrition: const {'proteins': 9.0, 'sugars': 3.0, 'energy_kcal': 120.0},
      );
      final productB = _product(
        id: 'b',
        name: 'Rakip Yoğurt 150 G',
        brand: 'Rakip',
        categoryTags: const ['yogurt'],
        nutrition: const {'proteins': 7.0, 'sugars': 5.0, 'energy_kcal': 140.0},
      );

      await _pumpComparisonPage(
        tester,
        productA: productA,
        productB: productB,
        comparisonRepository: _FakeComparisonRepository(
          createHandler: ({required productA, required productB}) async =>
              ProductComparison.build(productA: productA, productB: productB),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ürün A'), findsNothing);
      expect(find.text('Ürün B'), findsNothing);
      expect(find.text('Barkod'), findsNothing);
      expect(find.text('Besin temeli'), findsNothing);
      expect(find.text('Kategori etiketleri'), findsNothing);
      expect(find.text('Katkılar ve uyarılar'), findsNothing);

      final leftName = tester.getTopLeft(find.text('Protein Yoğurt 150 G'));
      final rightName = tester.getTopLeft(find.text('Rakip Yoğurt 150 G'));
      expect((leftName.dy - rightName.dy).abs(), lessThan(36));
      expect(leftName.dx, lessThan(rightName.dx));
      final images = tester.widgetList<FreshProductImage>(
        find.byType(FreshProductImage),
      );
      expect(images.length, greaterThanOrEqualTo(2));
      expect(images.every((image) => image.size >= 96), isTrue);
      expect(find.text('Ürünü değiştir'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('styles nutrition winners visually without explicit labels', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final productA = _product(
        id: 'a',
        name: 'Şekersiz Yoğurt 150 G',
        categoryTags: const ['yogurt'],
        nutrition: const {
          'energy_kcal': 120.0,
          'fat': 3.0,
          'carbohydrates': 6.0,
          'sugars': 2.0,
          'proteins': 9.0,
          'salt': 0.2,
        },
      );
      final productB = _product(
        id: 'b',
        name: 'Tatlı Yoğurt 150 G',
        categoryTags: const ['yogurt'],
        nutrition: const {
          'energy_kcal': 150.0,
          'fat': 4.0,
          'carbohydrates': 9.0,
          'sugars': 8.0,
          'proteins': 6.0,
          'salt': 0.5,
        },
      );

      await _pumpComparisonPage(
        tester,
        productA: productA,
        productB: productB,
        comparisonRepository: _FakeComparisonRepository(
          createHandler: ({required productA, required productB}) async =>
              ProductComparison.build(productA: productA, productB: productB),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.cake_outlined), findsOneWidget);
      expect(find.byIcon(Icons.fitness_center_outlined), findsOneWidget);
      expect(find.text('100 g başına'), findsOneWidget);
      expect(find.text('Daha düşük'), findsNothing);
      expect(find.text('Daha yüksek'), findsNothing);
      expect(find.text('Yorum yok'), findsNothing);
      expect(
        find.byWidgetPredicate((widget) {
          if (widget is! Container || widget.decoration is! BoxDecoration) {
            return false;
          }
          final decoration = widget.decoration! as BoxDecoration;
          final colorValue = decoration.color?.toARGB32();
          return colorValue ==
              AppColors.positiveSoft.withValues(alpha: 0.72).toARGB32();
        }),
        findsNothing,
      );
      expect(
        _textColorFor(tester, 'comparison-metric-sugars-a-text').toARGB32(),
        AppColors.positive.toARGB32(),
      );
      expect(
        _textColorFor(tester, 'comparison-metric-sugars-b-text').toARGB32(),
        AppColors.danger.withValues(alpha: 0.68).toARGB32(),
      );
      expect(
        find.byKey(const ValueKey('comparison-metric-sugars-a-underline')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('comparison-metric-sugars-b-underline')),
        findsNothing,
      );
      expect(
        _textColorFor(tester, 'comparison-metric-proteins-a-text').toARGB32(),
        AppColors.positive.toARGB32(),
      );
      expect(
        _textColorFor(tester, 'comparison-metric-proteins-b-text').toARGB32(),
        AppColors.danger.withValues(alpha: 0.68).toARGB32(),
      );
      expect(
        _textColorFor(tester, 'comparison-metric-energy-a-text').toARGB32(),
        AppColors.textPrimary.toARGB32(),
      );
      expect(
        _textColorFor(tester, 'comparison-metric-fat-b-text').toARGB32(),
        AppColors.textPrimary.toARGB32(),
      );
      expect(
        find.byKey(const ValueKey('comparison-metric-salt-icon')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('comparison-metric-salt-icon')),
          matching: find.byIcon(Icons.grain_outlined),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(
            const ValueKey('comparison-metric-carbohydrates-icon'),
          ),
          matching: find.byIcon(Icons.grain_outlined),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('keeps missing nutrition data calm and unjudged', (
      tester,
    ) async {
      final productA = _product(
        id: 'a',
        name: 'Yoğurt 150 G',
        categoryTags: const ['yogurt'],
        nutrition: const {
          'energy_kcal': 120.0,
          'fat': 3.0,
          'sugars': 5.0,
          'salt': 0.2,
        },
      );
      final productB = _product(
        id: 'b',
        name: 'Yoğurt 150 G Light',
        categoryTags: const ['yogurt'],
        nutrition: const {'energy_kcal': 110.0, 'fat': 2.0, 'sugars': 4.0},
      );

      await _pumpComparisonPage(
        tester,
        productA: productA,
        productB: productB,
        comparisonRepository: _FakeComparisonRepository(
          createHandler: ({required productA, required productB}) async =>
              ProductComparison.build(productA: productA, productB: productB),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Bilgi yok'), findsWidgets);
      expect(
        _textColorFor(tester, 'comparison-metric-salt-b-text').toARGB32(),
        AppColors.textSecondary.toARGB32(),
      );
      expect(
        find.byKey(const ValueKey('comparison-metric-salt-b-underline')),
        findsNothing,
      );
    });

    testWidgets('bounds ingredient previews and expands to the full list', (
      tester,
    ) async {
      final productA = _product(
        id: 'a',
        name: 'Atıştırmalık 150 G',
        categoryTags: const ['cips'],
        ingredientsText:
            'Patates, palm yağı, aroma verici, maltodekstrin, sodyum nitrit, tartrazin, sukraloz, monosodyum glutamat.',
      );
      final productB = _product(
        id: 'b',
        name: 'Karşı ürün 150 G',
        categoryTags: const ['cips'],
        ingredientsText: 'Patates, tuz.',
      );

      await _pumpComparisonPage(
        tester,
        productA: productA,
        productB: productB,
        comparisonRepository: _FakeComparisonRepository(
          createHandler: ({required productA, required productB}) async =>
              ProductComparison.build(
                productA: productA,
                productB: productB,
                ingredientsA: [
                  _ingredient(name: 'Sodyum Nitrit', riskLevel: 'high'),
                  _ingredient(name: 'Tartrazin', riskLevel: 'high'),
                  _ingredient(name: 'Palm Yağı', riskLevel: 'medium'),
                  _ingredient(name: 'Aroma Verici', riskLevel: 'medium'),
                  _ingredient(name: 'Maltodekstrin', riskLevel: 'medium'),
                  _ingredient(name: 'Sukraloz', riskLevel: 'medium'),
                  _ingredient(name: 'Monosodyum Glutamat', riskLevel: 'medium'),
                  _ingredient(name: 'Patates', riskLevel: 'low'),
                ],
                ingredientsB: [_ingredient(name: 'Patates', riskLevel: 'low')],
              ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Nitrit/Nitrat koruyucu'), findsOneWidget);
      expect(find.text('Tartrazin'), findsOneWidget);
      expect(find.text('Tümünü gör'), findsOneWidget);
      final nitritTop = tester.getTopLeft(find.text('Nitrit/Nitrat koruyucu'));
      final palmTop = tester.getTopLeft(find.text('Palm yağı'));
      expect(nitritTop.dy, lessThan(palmTop.dy));

      await tester.ensureVisible(find.text('Tümünü gör'));
      await tester.tap(find.text('Tümünü gör'));
      await tester.pumpAndSettle();

      expect(find.text('Maltodekstrin'), findsOneWidget);
      expect(find.text('Aroma Verici'), findsWidgets);
    });

    testWidgets('cleans raw ingredient fallback and shows allergen states', (
      tester,
    ) async {
      final productA = _product(
        id: 'a',
        name: 'Meyveli İçecek 1 L',
        categoryTags: const ['gazli_icecek'],
        nutrition: const {
          'energy_kcal': 42.0,
          'fat': 0.0,
          'saturated_fat': 0.0,
          'carbohydrates': 10.0,
          'sugars': 9.0,
          'proteins': 0.0,
          'fiber': 0.0,
          'salt': 0.0,
        },
        ingredientsText: r'Su\r\nElma püresi\nMeyve suyu konsantresi',
      );
      final productB = _product(
        id: 'b',
        name: 'Sütlü İçecek 1 L',
        categoryTags: const ['gazli_icecek'],
        nutrition: const {
          'energy_kcal': 64.0,
          'fat': 1.5,
          'saturated_fat': 1.0,
          'carbohydrates': 8.0,
          'sugars': 8.0,
          'proteins': 4.0,
          'fiber': 0.0,
          'salt': 0.1,
        },
      );

      await _pumpComparisonPage(
        tester,
        productA: productA,
        productB: productB,
        comparisonRepository: _FakeComparisonRepository(
          createHandler: ({required productA, required productB}) async =>
              ProductComparison.build(
                productA: productA,
                productB: productB,
                ingredientsA: const [],
                ingredientsB: [_ingredient(name: 'Süt Tozu', riskLevel: 'low')],
              ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining(r'\r\n'), findsNothing);
      expect(find.textContaining(r'\n'), findsNothing);
      expect(find.text('İçindekiler metni'), findsOneWidget);
      expect(
        find.text('Su\nElma püresi\nMeyve suyu konsantresi'),
        findsOneWidget,
      );
      expect(find.text('Süt'), findsOneWidget);
    });

    testWidgets('uses cleaned Migros ingredients and separated allergen text', (
      tester,
    ) async {
      final productA = _product(
        id: 'a',
        name: 'Beyaz Leblebi 180 G',
        categoryTags: const ['kuruyemis'],
        nutrition: const {
          'energy_kcal': 367.0,
          'fat': 5.0,
          'saturated_fat': 0.7,
          'carbohydrates': 57.5,
          'sugars': 7.5,
          'proteins': 20.8,
          'fiber': 17.0,
          'salt': 0.6,
        },
        ingredientsText:
            'İçindekiler\n'
            'BEYAZ LEBLEBİ, TUZ A\n\n'
            'Alerjen Uyarısı\n'
            'eser miktarda badem, ceviz, buğday gluteni içerir.',
      );
      final productB = _product(
        id: 'b',
        name: 'Sade Leblebi 180 G',
        categoryTags: const ['kuruyemis'],
        nutrition: const {
          'energy_kcal': 360.0,
          'fat': 4.8,
          'saturated_fat': 0.6,
          'carbohydrates': 55.0,
          'sugars': 5.5,
          'proteins': 21.0,
          'fiber': 15.0,
          'salt': 0.3,
        },
      );

      await _pumpComparisonPage(
        tester,
        productA: productA,
        productB: productB,
        comparisonRepository: _FakeComparisonRepository(
          createHandler: ({required productA, required productB}) async =>
              ProductComparison.build(productA: productA, productB: productB),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('TUZ A'), findsNothing);
      expect(find.text('Alerjen Uyarısı'), findsNothing);
      expect(find.text('Tuz'), findsWidgets);
      expect(find.text('Badem'), findsOneWidget);
      expect(find.text('Gluten / Buğday'), findsOneWidget);
    });

    testWidgets('uses product-detail allergen source and keeps unknown state', (
      tester,
    ) async {
      final nutrition = const {
        'energy_kcal': 110.0,
        'fat': 2.0,
        'saturated_fat': 0.5,
        'carbohydrates': 18.0,
        'sugars': 4.0,
        'proteins': 5.0,
        'fiber': 1.0,
        'salt': 0.2,
      };
      final productA = _product(
        id: 'a',
        name: 'Sandviç Ekmeği 300 G',
        categoryTags: const ['firin'],
        nutrition: nutrition,
        ingredientsText: 'Buğday unu, su, tuz.',
      );
      final productB = _product(
        id: 'b',
        name: 'Sade Kraker 200 G',
        categoryTags: const ['firin'],
        nutrition: nutrition,
      );

      await _pumpComparisonPage(
        tester,
        productA: productA,
        productB: productB,
        comparisonRepository: _FakeComparisonRepository(
          createHandler: ({required productA, required productB}) async =>
              ProductComparison.build(productA: productA, productB: productB),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Gluten / Buğday'), findsOneWidget);
      expect(find.text('Bilgi yok'), findsWidgets);
    });

    testWidgets('shows incompatible basis warning for g vs ml products', (
      tester,
    ) async {
      final productA = _product(
        id: 'a',
        name: 'Patates Cipsi 150 G',
        categoryTags: const ['cips'],
        nutrition: const {'sugars': 2.0, 'salt': 1.0},
      );
      final productB = _product(
        id: 'b',
        name: 'Kola 1 L',
        categoryTags: const ['gazli_icecek'],
        nutrition: const {'sugars': 9.0, 'salt': 0.1},
      );

      await _pumpComparisonPage(
        tester,
        productA: productA,
        productB: productB,
        comparisonRepository: _FakeComparisonRepository(
          createHandler: ({required productA, required productB}) async =>
              ProductComparison.build(productA: productA, productB: productB),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('doğrudan karşılaştırılamıyor'),
        findsOneWidget,
      );
    });
  });
}

Future<void> _pumpPickerPage(
  WidgetTester tester, {
  required Product source,
  required ProductComparisonRepository comparisonRepository,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        productComparisonRepositoryProvider.overrideWithValue(
          comparisonRepository,
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme(),
        home: ComparisonProductPickerPage(
          routeArgs: ComparisonPickerRouteArgs(
            sourceProductId: source.id,
            sourceProduct: source,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _pumpComparisonPage(
  WidgetTester tester, {
  required Product productA,
  required Product productB,
  required ProductComparisonRepository comparisonRepository,
  ProductRepository? productRepository,
}) async {
  final effectiveRepository =
      productRepository ??
      _FakeProductRepository(
        products: {productA.id: productA, productB.id: productB},
      );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        productComparisonRepositoryProvider.overrideWithValue(
          comparisonRepository,
        ),
        productRepositoryProvider.overrideWithValue(effectiveRepository),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme(),
        home: ProductComparisonPage(
          routeArgs: ProductComparisonRouteArgs(
            sourceProductId: productA.id,
            comparedProductId: productB.id,
            sourceProduct: productA,
            comparedProduct: productB,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Color _textColorFor(WidgetTester tester, String key) {
  final text = tester.widget<Text>(find.byKey(ValueKey(key)));
  return text.style?.color ?? Colors.transparent;
}

GoRouter _buildComparisonRouter() {
  return GoRouter(
    initialLocation: '/product/a',
    routes: [
      GoRoute(
        name: 'product',
        path: '/product/:id',
        builder: (context, state) =>
            ProductScreen(productId: state.pathParameters['id'] ?? ''),
      ),
      GoRoute(
        name: 'comparison_picker',
        path: '/product/:id/compare',
        builder: (context, state) => ComparisonProductPickerPage(
          routeArgs: state.extra! as ComparisonPickerRouteArgs,
        ),
      ),
      GoRoute(
        name: 'product_comparison',
        path: '/product/:id/compare/:otherId',
        builder: (context, state) => ProductComparisonPage(
          routeArgs: state.extra! as ProductComparisonRouteArgs,
        ),
      ),
    ],
  );
}

Product _product({
  required String id,
  required String name,
  String? brand,
  String? ingredientsText,
  List<String>? categoryTags,
  Map<String, dynamic>? nutrition,
}) {
  final now = DateTime.utc(2026, 6, 26, 12);
  return Product(
    id: id,
    name: name,
    brand: brand,
    ingredientsText: ingredientsText,
    nutritionText: nutrition == null ? null : jsonEncode(nutrition),
    verificationStatus: 'verified',
    categoryTags: categoryTags,
    createdAt: now,
    updatedAt: now,
  );
}

Ingredient _ingredient({
  required String name,
  required String riskLevel,
  String? normalizedName,
}) {
  final now = DateTime.utc(2026, 6, 26, 12);
  return Ingredient(
    id: '${name}_id',
    name: name,
    normalizedName: normalizedName ?? name.toLowerCase(),
    riskLevel: riskLevel,
    createdAt: now,
    updatedAt: now,
  );
}

class _FakeComparisonRepository extends ProductComparisonRepository {
  _FakeComparisonRepository({this.findHandler, this.createHandler})
    : super(
        productRepository: _FakeProductRepository(products: const {}),
        remoteSource: const _NoopRemoteSource(),
      );

  final Future<List<Product>> Function({
    required Product source,
    String? query,
    int limit,
  })?
  findHandler;
  final Future<ProductComparison> Function({
    required Product productA,
    required Product productB,
  })?
  createHandler;

  @override
  Future<List<Product>> findComparisonCandidates({
    required Product source,
    String? query,
    int limit = 40,
  }) async {
    return findHandler?.call(source: source, query: query, limit: limit) ??
        const <Product>[];
  }

  @override
  Future<ProductComparison> createComparison({
    required Product productA,
    required Product productB,
  }) async {
    return createHandler?.call(productA: productA, productB: productB) ??
        ProductComparison.build(productA: productA, productB: productB);
  }
}

class _FakeProductRepository extends ProductRepository {
  _FakeProductRepository({
    required Map<String, Product> products,
    Map<String, List<Ingredient>> ingredientsByProduct = const {},
    List<Ingredient> allIngredients = const <Ingredient>[],
  }) : _products = products,
       _ingredientsByProduct = ingredientsByProduct,
       _allIngredients = allIngredients;

  final Map<String, Product> _products;
  final Map<String, List<Ingredient>> _ingredientsByProduct;
  final List<Ingredient> _allIngredients;

  @override
  Future<Product?> getProductById(String id) async => _products[id];

  @override
  Future<ProductReview?> getProductReviewByProductId(String productId) async =>
      null;

  @override
  Future<List<Ingredient>> getProductIngredients(String productId) async =>
      _ingredientsByProduct[productId] ?? const <Ingredient>[];

  @override
  Future<List<Ingredient>> getAllIngredients() async => _allIngredients;
}

class _NoopRemoteSource implements ProductComparisonRemoteSource {
  const _NoopRemoteSource();

  @override
  Future<List<Map<String, dynamic>>> fetchOverlapProducts({
    required String overlapLiteral,
    String? query,
    required int limit,
  }) async => const <Map<String, dynamic>>[];

  @override
  Future<List<Map<String, dynamic>>> searchCatalog({
    String? query,
    required int limit,
  }) async => const <Map<String, dynamic>>[];
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
