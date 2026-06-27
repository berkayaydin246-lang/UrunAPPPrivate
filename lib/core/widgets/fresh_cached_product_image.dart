import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

const kProductPreviewDiskMaxWidth = 64;
const kProductPreviewDiskMaxHeight = 64;
const kProductGridDecodeWidth = 320;
const kProductGridDecodeHeight = 320;
const kProductGridDiskMaxWidth = 640;
const kProductGridDiskMaxHeight = 640;

class ProductThumbnailCache {
  ProductThumbnailCache._();

  static const cacheKey = 'freshscan_product_thumbnails_v1';

  static final CacheManager instance = _FreshScanProductThumbnailCacheManager();
}

class _FreshScanProductThumbnailCacheManager extends CacheManager
    with ImageCacheManager {
  _FreshScanProductThumbnailCacheManager()
    : super(
        Config(
          ProductThumbnailCache.cacheKey,
          stalePeriod: const Duration(days: 30),
          maxNrOfCacheObjects: 1500,
        ),
      );
}

bool _freshScanImageCacheConfigured = false;

@visibleForTesting
int debugFreshScanImageCacheConfigurationCount = 0;

void configureFreshScanImageCache() {
  if (_freshScanImageCacheConfigured) return;

  final cache = PaintingBinding.instance.imageCache;
  cache.maximumSize = 1000;
  cache.maximumSizeBytes = 128 * 1024 * 1024;

  _freshScanImageCacheConfigured = true;
  debugFreshScanImageCacheConfigurationCount++;
}

@visibleForTesting
void debugResetFreshScanImageCacheConfigurationForTests() {
  _freshScanImageCacheConfigured = false;
  debugFreshScanImageCacheConfigurationCount = 0;
}

String normalizeProductThumbnailUrl(String imageUrl) {
  final trimmed = imageUrl.trim();
  return trimmed.split('#').first.split('?').first;
}

String productThumbnailCacheKey({
  required String productId,
  required String imageUrl,
}) {
  final normalizedUrl = normalizeProductThumbnailUrl(imageUrl);
  return 'product-thumb:$productId:${Uri.encodeComponent(normalizedUrl)}';
}

String productThumbnailPreviewCacheKey({
  required String productId,
  required String imageUrl,
}) {
  return '${productThumbnailCacheKey(productId: productId, imageUrl: imageUrl)}:preview';
}

String productThumbnailGridCacheKey({
  required String productId,
  required String imageUrl,
}) {
  return '${productThumbnailCacheKey(productId: productId, imageUrl: imageUrl)}:grid';
}

CachedNetworkImageProvider buildProductThumbnailPreviewProvider({
  required String productId,
  required String imageUrl,
}) {
  return CachedNetworkImageProvider(
    imageUrl,
    cacheKey: productThumbnailPreviewCacheKey(
      productId: productId,
      imageUrl: imageUrl,
    ),
    cacheManager: ProductThumbnailCache.instance,
    maxWidth: kProductPreviewDiskMaxWidth,
    maxHeight: kProductPreviewDiskMaxHeight,
  );
}

CachedNetworkImageProvider buildProductThumbnailGridProvider({
  required String productId,
  required String imageUrl,
}) {
  return CachedNetworkImageProvider(
    imageUrl,
    cacheKey: productThumbnailGridCacheKey(
      productId: productId,
      imageUrl: imageUrl,
    ),
    cacheManager: ProductThumbnailCache.instance,
    maxWidth: kProductGridDiskMaxWidth,
    maxHeight: kProductGridDiskMaxHeight,
  );
}

ResizeImage buildProductThumbnailDecodeProvider(
  CachedNetworkImageProvider provider,
) {
  return ResizeImage(
    provider,
    width: kProductGridDecodeWidth,
    height: kProductGridDecodeHeight,
  );
}

class ProductThumbnailPrecacheItem {
  final String productId;
  final String? imageUrl;

  const ProductThumbnailPrecacheItem({
    required this.productId,
    required this.imageUrl,
  });
}

void warmProductThumbnailPreviews(
  BuildContext context,
  Iterable<ProductThumbnailPrecacheItem> products, {
  int concurrency = 4,
}) {
  final items = products
      .where((product) => product.imageUrl?.trim().isNotEmpty == true)
      .toList(growable: false);
  if (items.isEmpty) return;

  unawaited(_warmProductThumbnailPreviews(context, items, concurrency));
}

Future<void> _warmProductThumbnailPreviews(
  BuildContext context,
  List<ProductThumbnailPrecacheItem> products,
  int concurrency,
) async {
  var nextIndex = 0;
  final workerCount = concurrency.clamp(1, 6);

  Future<void> worker() async {
    while (nextIndex < products.length) {
      final item = products[nextIndex++];
      final imageUrl = item.imageUrl!.trim();
      final provider = buildProductThumbnailPreviewProvider(
        productId: item.productId,
        imageUrl: imageUrl,
      );

      try {
        await precacheImage(
          provider,
          context,
          size: Size(
            kProductPreviewDiskMaxWidth.toDouble(),
            kProductPreviewDiskMaxHeight.toDouble(),
          ),
        );
      } catch (_) {
        // Preview warming is opportunistic; the visible thumbnail still handles
        // network and decode errors with its fallback layer.
      }
    }
  }

  await Future.wait([
    for (var i = 0; i < workerCount && i < products.length; i++) worker(),
  ]);
}

Future<void> debugThumbnailCacheStatus(
  CachedNetworkImageProvider provider,
  String productId,
) async {
  if (!kDebugMode) return;

  final status = await provider.obtainCacheStatus(
    configuration: const ImageConfiguration(),
  );

  debugPrint(
    '[thumbnail_cache] '
    'product=$productId '
    'pending=${status?.pending} '
    'live=${status?.live} '
    'keepAlive=${status?.keepAlive}',
  );
}

void debugFreshScanImageCacheStats() {
  if (!kDebugMode) return;

  final cache = PaintingBinding.instance.imageCache;
  debugPrint(
    '[image_cache] '
    'count=${cache.currentSize} '
    'bytes=${cache.currentSizeBytes} '
    'live=${cache.liveImageCount}',
  );
}

class ProductThumbnail extends StatefulWidget {
  final String productId;
  final String? imageUrl;
  final Color accentColor;
  final IconData placeholderIcon;
  final double iconSize;
  final BoxFit fit;

  const ProductThumbnail({
    super.key,
    required this.productId,
    required this.imageUrl,
    required this.accentColor,
    this.placeholderIcon = Icons.shopping_bag_outlined,
    this.iconSize = 28,
    this.fit = BoxFit.contain,
  });

  @override
  State<ProductThumbnail> createState() => _ProductThumbnailState();
}

class _ProductThumbnailState extends State<ProductThumbnail> {
  CachedNetworkImageProvider? _previewProvider;
  ResizeImage? _gridDecodeProvider;
  String? _normalizedImageUrl;

  @override
  void initState() {
    super.initState();
    _configureProviders();
  }

  @override
  void didUpdateWidget(covariant ProductThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);

    final nextNormalizedUrl = _normalizedUrlOrNull(widget.imageUrl);
    if (widget.productId != oldWidget.productId ||
        nextNormalizedUrl != _normalizedImageUrl) {
      _configureProviders();
    }
  }

  void _configureProviders() {
    final imageUrl = widget.imageUrl?.trim();
    final normalizedUrl = _normalizedUrlOrNull(imageUrl);
    _normalizedImageUrl = normalizedUrl;

    if (imageUrl == null || imageUrl.isEmpty || normalizedUrl == null) {
      _previewProvider = null;
      _gridDecodeProvider = null;
      return;
    }

    final previewProvider = buildProductThumbnailPreviewProvider(
      productId: widget.productId,
      imageUrl: imageUrl,
    );
    final gridProvider = buildProductThumbnailGridProvider(
      productId: widget.productId,
      imageUrl: imageUrl,
    );

    _previewProvider = previewProvider;
    _gridDecodeProvider = buildProductThumbnailDecodeProvider(gridProvider);
  }

  String? _normalizedUrlOrNull(String? imageUrl) {
    if (imageUrl == null || imageUrl.trim().isEmpty) return null;
    return normalizeProductThumbnailUrl(imageUrl);
  }

  @override
  Widget build(BuildContext context) {
    final previewProvider = _previewProvider;
    final gridDecodeProvider = _gridDecodeProvider;

    if (previewProvider == null || gridDecodeProvider == null) {
      return ProductImageFallback(
        accentColor: widget.accentColor,
        icon: widget.placeholderIcon,
        iconSize: widget.iconSize,
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Image(
          key: ValueKey('product-thumbnail-preview-${widget.productId}'),
          image: previewProvider,
          fit: widget.fit,
          filterQuality: FilterQuality.low,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => ProductImageFallback(
            accentColor: widget.accentColor,
            icon: widget.placeholderIcon,
            iconSize: widget.iconSize,
          ),
        ),
        Image(
          key: ValueKey('product-thumbnail-grid-${widget.productId}'),
          image: gridDecodeProvider,
          fit: widget.fit,
          filterQuality: FilterQuality.medium,
          gaplessPlayback: true,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded || frame != null) return child;
            return const SizedBox.expand();
          },
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class ProductImageFallback extends StatelessWidget {
  final Color accentColor;
  final IconData icon;
  final double iconSize;

  const ProductImageFallback({
    super.key,
    required this.accentColor,
    this.icon = Icons.shopping_bag_outlined,
    this.iconSize = 28,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.transparent,
      child: Center(
        child: Icon(
          icon,
          size: iconSize,
          color: accentColor.withValues(alpha: 0.62),
        ),
      ),
    );
  }
}
