import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/core/widgets/fresh_cached_product_image.dart';

void main() {
  setUpAll(_mockPathProvider);

  const productId = 'product-123';
  const imageUrl = 'https://img.example.test/path/front.png?sig=old#frag';
  const changedQueryUrl = 'https://img.example.test/path/front.png?sig=new';

  test(
    'product thumbnail cache keys are stable for query-only URL changes',
    () {
      expect(
        productThumbnailPreviewCacheKey(
          productId: productId,
          imageUrl: imageUrl,
        ),
        productThumbnailPreviewCacheKey(
          productId: productId,
          imageUrl: changedQueryUrl,
        ),
      );
      expect(
        productThumbnailGridCacheKey(productId: productId, imageUrl: imageUrl),
        productThumbnailGridCacheKey(
          productId: productId,
          imageUrl: changedQueryUrl,
        ),
      );
      expect(
        productThumbnailPreviewCacheKey(
          productId: productId,
          imageUrl: imageUrl,
        ),
        contains(productId),
      );
    },
  );

  test('preview and grid providers use stable thumbnail dimensions', () {
    final preview = buildProductThumbnailPreviewProvider(
      productId: productId,
      imageUrl: imageUrl,
    );
    final grid = buildProductThumbnailGridProvider(
      productId: productId,
      imageUrl: imageUrl,
    );
    final decoded = buildProductThumbnailDecodeProvider(grid);

    expect(preview, isA<CachedNetworkImageProvider>());
    expect(preview.maxWidth, kProductPreviewDiskMaxWidth);
    expect(preview.maxHeight, kProductPreviewDiskMaxHeight);
    expect(
      preview.cacheKey,
      productThumbnailPreviewCacheKey(productId: productId, imageUrl: imageUrl),
    );
    expect(
      identical(preview.cacheManager, ProductThumbnailCache.instance),
      true,
    );

    expect(grid.maxWidth, kProductGridDiskMaxWidth);
    expect(grid.maxHeight, kProductGridDiskMaxHeight);
    expect(
      grid.cacheKey,
      productThumbnailGridCacheKey(productId: productId, imageUrl: imageUrl),
    );
    expect(identical(grid.cacheManager, ProductThumbnailCache.instance), true);

    expect(decoded.width, kProductGridDecodeWidth);
    expect(decoded.height, kProductGridDecodeHeight);
    expect(identical(decoded.imageProvider, grid), true);
  });

  testWidgets('preview remains behind the full thumbnail while pending', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 120,
          height: 120,
          child: ProductThumbnail(
            productId: productId,
            imageUrl: imageUrl,
            accentColor: Colors.red,
          ),
        ),
      ),
    );

    final stack = tester.widget<Stack>(find.byType(Stack));
    final previewImage = tester.widget<Image>(
      find.byKey(const ValueKey('product-thumbnail-preview-$productId')),
    );
    final gridImage = tester.widget<Image>(
      find.byKey(const ValueKey('product-thumbnail-grid-$productId')),
    );

    expect(stack.fit, StackFit.expand);
    expect(previewImage.gaplessPlayback, isTrue);
    expect(gridImage.gaplessPlayback, isTrue);
    expect(gridImage.image, isA<ResizeImage>());
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(ProductImageFallback), findsNothing);
  });

  testWidgets('thumbnail providers are preserved across repeated builds', (
    tester,
  ) async {
    Future<void> pump(String url) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 120,
            height: 120,
            child: ProductThumbnail(
              key: const ValueKey('stable-thumb'),
              productId: productId,
              imageUrl: url,
              accentColor: Colors.green,
            ),
          ),
        ),
      );
    }

    await pump(imageUrl);
    final firstPreview = tester
        .widget<Image>(
          find.byKey(const ValueKey('product-thumbnail-preview-$productId')),
        )
        .image;
    final firstGrid = tester
        .widget<Image>(
          find.byKey(const ValueKey('product-thumbnail-grid-$productId')),
        )
        .image;

    await pump(changedQueryUrl);
    final secondPreview = tester
        .widget<Image>(
          find.byKey(const ValueKey('product-thumbnail-preview-$productId')),
        )
        .image;
    final secondGrid = tester
        .widget<Image>(
          find.byKey(const ValueKey('product-thumbnail-grid-$productId')),
        )
        .image;

    expect(identical(firstPreview, secondPreview), isTrue);
    expect(identical(firstGrid, secondGrid), isTrue);
  });

  test('Flutter ImageCache configuration is idempotent', () {
    debugResetFreshScanImageCacheConfigurationForTests();

    configureFreshScanImageCache();
    configureFreshScanImageCache();

    final cache = PaintingBinding.instance.imageCache;
    expect(debugFreshScanImageCacheConfigurationCount, 1);
    expect(cache.maximumSize, 1000);
    expect(cache.maximumSizeBytes, 128 * 1024 * 1024);
  });
}

void _mockPathProvider() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final tempDir = Directory.systemTemp.createTempSync(
    'freshscan_product_thumbnail_test_',
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
