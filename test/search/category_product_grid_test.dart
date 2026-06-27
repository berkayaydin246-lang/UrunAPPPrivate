import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/core/theme/category_theme.dart';
import 'package:food_analyzer_app/core/widgets/fresh_cached_product_image.dart';
import 'package:food_analyzer_app/core/widgets/fresh_product_image.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/product/repositories/product_repository.dart';
import 'package:food_analyzer_app/features/search/controllers/filtered_search_controller.dart';
import 'package:food_analyzer_app/features/search/models/product_list_context.dart';
import 'package:food_analyzer_app/features/search/models/product_search_filter.dart';
import 'package:food_analyzer_app/features/search/services/canonical_category_mapper.dart';
import 'package:food_analyzer_app/features/search/widgets/product_card.dart';
import 'package:food_analyzer_app/features/search/widgets/product_list_view.dart';
import 'package:go_router/go_router.dart';

class _GridRepo extends ProductRepository {
  final List<Product> products;
  final List<int> offsets = [];

  _GridRepo(this.products);

  @override
  Future<({List<Product> results, bool hasMore})> filteredSearch(
    ProductSearchFilter filter, {
    int pageSize = 20,
    int serverOffset = 0,
  }) async {
    offsets.add(serverOffset);
    final page = products.skip(serverOffset).take(pageSize).toList();
    return (
      results: page,
      hasMore: serverOffset + page.length < products.length,
    );
  }
}

class _SlowRepo extends ProductRepository {
  final Completer<void> completer;

  _SlowRepo(this.completer);

  @override
  Future<({List<Product> results, bool hasMore})> filteredSearch(
    ProductSearchFilter filter, {
    int pageSize = 20,
    int serverOffset = 0,
  }) async {
    await completer.future;
    return (results: const <Product>[], hasMore: false);
  }
}

Product _product(int index, {String? imageUrl, String? name, String? brand}) {
  final now = DateTime(2026, 1, 1);
  return Product(
    id: 'p$index',
    name: name ?? 'Tutku Kakao Kremalı Mozaik Bisküvi ${100 + index} G',
    brand: brand ?? (index.isEven ? 'Eti' : 'Ülker'),
    imageUrl: imageUrl,
    categoryTags: const ['biskuvi', 'biskuvi_kek'],
    verificationStatus: 'verified',
    createdAt: now,
    updatedAt: now,
  );
}

({GoRouter router, _GridRepo repo}) _buildRouterHarness({
  required List<Product> products,
  ProductRepository? repoOverride,
}) {
  final repo = repoOverride is _GridRepo ? repoOverride : _GridRepo(products);
  const listContext = ProductListContext.mainCategory(
    mainCategory: CanonicalCategoryMapper.kAtistirmalik,
  );
  final theme = getCategoryTheme(CanonicalCategoryMapper.kAtistirmalik);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: ProductListView(
            searchHint: 'Atıştırmalık içinde ara',
            listContext: listContext,
            categoryTheme: theme,
            simpleCards: true,
          ),
        ),
      ),
      GoRoute(
        path: '/product/:id',
        builder: (context, state) =>
            Scaffold(body: Text('detail:${state.pathParameters['id']}')),
      ),
    ],
  );

  return (router: router, repo: repo);
}

Future<({GoRouter router, _GridRepo repo})> _pumpGrid(
  WidgetTester tester, {
  List<Product>? products,
  ProductRepository? repoOverride,
}) async {
  final harness = _buildRouterHarness(
    products: products ?? List.generate(6, _product),
    repoOverride: repoOverride,
  );
  const listContext = ProductListContext.mainCategory(
    mainCategory: CanonicalCategoryMapper.kAtistirmalik,
  );

  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        filteredSearchProvider.overrideWith(
          (ref) => FilteredSearchNotifier(
            repoOverride ?? harness.repo,
            initialFilter: listContext.initialFilter(),
          ),
        ),
      ],
      child: MaterialApp.router(routerConfig: harness.router),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(harness.router.dispose);
  return harness;
}

void main() {
  setUpAll(_mockPathProvider);

  testWidgets('category results use a compact 3-column product grid', (
    tester,
  ) async {
    await _pumpGrid(tester);

    final grid = tester.widget<SliverGrid>(
      find.byKey(const ValueKey('category-product-grid')),
    );
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    final childDelegate = grid.delegate as SliverChildBuilderDelegate;

    expect(delegate.crossAxisCount, 3);
    expect(delegate.crossAxisSpacing, 10);
    expect(delegate.mainAxisSpacing, 16);
    expect(delegate.mainAxisExtent, isNotNull);
    expect(childDelegate.addAutomaticKeepAlives, isFalse);
    expect(
      find.byKey(const ValueKey('compact-product-tile-p0')),
      findsOneWidget,
    );
    expect(find.byType(FreshProductImage), findsNothing);
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
  });

  testWidgets(
    'compact grid images use progressive thumbnails without spinners',
    (tester) async {
      await _pumpGrid(
        tester,
        products: List.generate(
          6,
          (index) => _product(
            index,
            imageUrl: 'https://img.example.test/product-$index.png',
          ),
        ),
      );

      final thumbnail = tester.widget<ProductThumbnail>(
        find.descendant(
          of: find.byKey(const ValueKey('compact-product-image-p0')),
          matching: find.byType(ProductThumbnail),
        ),
      );
      final previewImage = tester.widget<Image>(
        find.byKey(const ValueKey('product-thumbnail-preview-p0')),
      );
      final gridImage = tester.widget<Image>(
        find.byKey(const ValueKey('product-thumbnail-grid-p0')),
      );

      expect(thumbnail.productId, 'p0');
      expect(thumbnail.imageUrl, 'https://img.example.test/product-0.png');
      expect(previewImage.gaplessPlayback, isTrue);
      expect(previewImage.filterQuality, FilterQuality.low);
      expect(gridImage.gaplessPlayback, isTrue);
      expect(gridImage.filterQuality, FilterQuality.medium);
      expect(gridImage.image, isA<ResizeImage>());
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('compact-product-image-p0')),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsNothing,
      );
    },
  );

  testWidgets('compact tile shows image above brand and product name', (
    tester,
  ) async {
    await _pumpGrid(tester);

    final image = find.byKey(const ValueKey('compact-product-image-p0'));
    final brand = find.byKey(const ValueKey('compact-product-brand-p0'));
    final name = find.byKey(const ValueKey('compact-product-name-p0'));

    expect(tester.getTopLeft(image).dy, lessThan(tester.getTopLeft(brand).dy));
    expect(tester.getTopLeft(brand).dy, lessThan(tester.getTopLeft(name).dy));

    final brandText = tester.widget<Text>(brand);
    final nameText = tester.widget<Text>(name);
    expect(brandText.maxLines, 1);
    expect(brandText.overflow, TextOverflow.ellipsis);
    expect(nameText.maxLines, 2);
    expect(nameText.overflow, TextOverflow.ellipsis);
  });

  testWidgets('compact product name area keeps descenders visible', (
    tester,
  ) async {
    await _pumpGrid(
      tester,
      products: [
        _product(
          0,
          name: 'Coca Cola Zero Sugar Cam Şişe 6 x 250 Ml',
          brand: 'Coca Cola',
        ),
        ...List.generate(5, (index) => _product(index + 1)),
      ],
    );

    final tile = find.byKey(const ValueKey('compact-product-tile-p0'));
    final image = find.byKey(const ValueKey('compact-product-image-p0'));
    final nameArea = find.byKey(const ValueKey('compact-product-name-area-p0'));
    final name = find.byKey(const ValueKey('compact-product-name-p0'));
    final nameText = tester.widget<Text>(name);
    final nameAreaSize = tester.getSize(nameArea);
    final imageSize = tester.getSize(image);
    final tileSize = tester.getSize(tile);
    final textPainter = TextPainter(
      text: TextSpan(text: nameText.data, style: nameText.style),
      textDirection: TextDirection.ltr,
      maxLines: nameText.maxLines,
      ellipsis: '...',
      textHeightBehavior: nameText.textHeightBehavior,
    )..layout(maxWidth: nameAreaSize.width);

    expect(
      nameAreaSize.height,
      kCompactProductNameMinHeight + kCompactProductNameBottomPadding,
    );
    expect(tileSize.height, compactProductTileHeight(imageSize.width));
    expect(nameText.maxLines, 2);
    expect(nameText.overflow, TextOverflow.ellipsis);
    expect(nameText.style?.height, 1.28);
    expect(
      nameText.textHeightBehavior,
      const TextHeightBehavior(
        applyHeightToFirstAscent: true,
        applyHeightToLastDescent: true,
        leadingDistribution: TextLeadingDistribution.even,
      ),
    );
    expect(textPainter.didExceedMaxLines, isTrue);
    expect(textPainter.height, lessThanOrEqualTo(nameAreaSize.height));
    expect(
      tester.getBottomLeft(name).dy,
      lessThan(tester.getBottomLeft(tile).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('product tap still opens product detail route', (tester) async {
    await _pumpGrid(tester);

    await tester.tap(find.byKey(const ValueKey('compact-product-tile-p0')));
    await tester.pumpAndSettle();

    expect(find.text('detail:p0'), findsOneWidget);
  });

  testWidgets('grid pagination keeps loading more products on scroll', (
    tester,
  ) async {
    final products = List.generate(25, _product);
    final harness = await _pumpGrid(tester, products: products);

    expect(harness.repo.offsets, contains(0));

    await tester.drag(
      find.byKey(const ValueKey('category-product-grid-scroll')),
      const Offset(0, -1800),
    );
    await tester.pumpAndSettle();

    expect(harness.repo.offsets, contains(20));
  });

  testWidgets('pagination keeps visible product tile elements stable', (
    tester,
  ) async {
    final products = List.generate(25, _product);
    final harness = await _pumpGrid(tester, products: products);
    final firstTile = find.byKey(const ValueKey('product-p0'));
    final before = tester.element(firstTile);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ProductListView)),
    );

    await container.read(filteredSearchProvider.notifier).loadMore();
    await tester.pumpAndSettle();

    expect(harness.repo.offsets, contains(20));
    expect(identical(before, tester.element(firstTile)), isTrue);
  });

  testWidgets('empty state remains available', (tester) async {
    await _pumpGrid(tester, products: const []);
    expect(find.text('Sonuç bulunamadı'), findsOneWidget);
  });

  testWidgets('loading state remains available', (tester) async {
    final completer = Completer<void>();
    final slowRepo = _SlowRepo(completer);
    final harness = _buildRouterHarness(
      products: const [],
      repoOverride: slowRepo,
    );
    const listContext = ProductListContext.mainCategory(
      mainCategory: CanonicalCategoryMapper.kAtistirmalik,
    );

    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          filteredSearchProvider.overrideWith(
            (ref) => FilteredSearchNotifier(
              slowRepo,
              initialFilter: listContext.initialFilter(),
            ),
          ),
        ],
        child: MaterialApp.router(routerConfig: harness.router),
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete();
    await tester.pumpAndSettle();
    addTearDown(harness.router.dispose);
  });

  testWidgets('category result background uses a subtle category tint', (
    tester,
  ) async {
    await _pumpGrid(tester);

    final background = tester.widget<ColoredBox>(
      find.byKey(const ValueKey('category-product-results-background')),
    );
    final theme = getCategoryTheme(CanonicalCategoryMapper.kAtistirmalik);

    expect(
      background.color,
      Color.lerp(Colors.white, theme.primaryColor, 0.035),
    );
  });

  testWidgets('compact grid has no render overflow on narrow phones', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;

    await _pumpGrid(tester);

    expect(tester.takeException(), isNull);
  });
}

void _mockPathProvider() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final tempDir = Directory.systemTemp.createTempSync(
    'freshscan_category_grid_test_',
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
