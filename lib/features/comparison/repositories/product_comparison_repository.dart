import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:food_analyzer_app/core/services/supabase_service.dart';
import 'package:food_analyzer_app/features/comparison/domain/product_comparison.dart';
import 'package:food_analyzer_app/features/product/controllers/product_detail_controller.dart';
import 'package:food_analyzer_app/features/product/models/ingredient.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/product/models/product_review.dart';
import 'package:food_analyzer_app/features/product/repositories/product_repository.dart';

final productComparisonRepositoryProvider =
    Provider<ProductComparisonRepository>((ref) {
      return ProductComparisonRepository(
        productRepository: ref.watch(productRepositoryProvider),
        remoteSource: const SupabaseProductComparisonRemoteSource(),
      );
    });

class ProductComparisonRepository {
  ProductComparisonRepository({
    required ProductRepository productRepository,
    required ProductComparisonRemoteSource remoteSource,
  }) : _productRepository = productRepository,
       _remoteSource = remoteSource;

  final ProductRepository _productRepository;
  final ProductComparisonRemoteSource _remoteSource;

  Future<Product?> getProductById(String id) {
    return _productRepository.getProductById(id);
  }

  Future<List<Product>> findComparisonCandidates({
    required Product source,
    String? query,
    int limit = 40,
  }) async {
    final trimmedQuery = query?.trim();
    final hasSourceTags = _normalizedTags(source.categoryTags).isNotEmpty;
    final fetchLimit = limit.clamp(1, 80);

    final rows = hasSourceTags
        ? await _remoteSource.fetchOverlapProducts(
            overlapLiteral: buildPostgresTextArrayLiteral(
              _normalizedTags(source.categoryTags),
            ),
            query: trimmedQuery,
            limit: fetchLimit * 3,
          )
        : await _remoteSource.searchCatalog(
            query: trimmedQuery,
            limit: fetchLimit * 3,
          );

    final candidates = <Product>[];
    final seenIds = <String>{};

    for (final row in rows) {
      final product = Product.fromJson(row);
      if (!_isEligibleCandidate(product, source)) continue;
      if (!_matchesQuery(product, trimmedQuery)) continue;
      if (seenIds.add(product.id)) {
        candidates.add(product);
      }
    }

    candidates.sort((a, b) => _compareCandidates(source, a, b));
    if (candidates.length > fetchLimit) {
      return List<Product>.unmodifiable(candidates.take(fetchLimit));
    }
    return List<Product>.unmodifiable(candidates);
  }

  Future<ProductComparison> createComparison({
    required Product productA,
    required Product productB,
  }) async {
    final futures = await Future.wait<Object?>([
      _productRepository.getProductReviewByProductId(productA.id),
      _productRepository.getProductReviewByProductId(productB.id),
      _productRepository.getProductIngredients(productA.id),
      _productRepository.getProductIngredients(productB.id),
    ]);

    return ProductComparison.build(
      productA: productA,
      productB: productB,
      reviewA: futures[0] as ProductReview?,
      reviewB: futures[1] as ProductReview?,
      ingredientsA: futures[2] as List<Ingredient>,
      ingredientsB: futures[3] as List<Ingredient>,
    );
  }

  bool _isEligibleCandidate(Product product, Product source) {
    if (product.id == source.id) return false;
    if (product.id.trim().isEmpty) return false;
    if (product.name.trim().isEmpty) return false;
    if (product.name == 'Bilinmeyen Ürün' ||
        product.name == 'Unknown Product') {
      return false;
    }
    if (product.source?.toLowerCase().contains('openfoodfacts') ?? false) {
      return false;
    }
    return true;
  }

  bool _matchesQuery(Product product, String? query) {
    final trimmed = query?.trim().toLowerCase();
    if (trimmed == null || trimmed.isEmpty) return true;

    return product.name.toLowerCase().contains(trimmed) ||
        (product.brand?.toLowerCase().contains(trimmed) ?? false) ||
        (product.normalizedName?.toLowerCase().contains(trimmed) ?? false) ||
        (product.barcode?.toLowerCase().contains(trimmed) ?? false);
  }

  int _compareCandidates(Product source, Product a, Product b) {
    final sharedA = countSharedCategoryTags(source, a);
    final sharedB = countSharedCategoryTags(source, b);
    if (sharedA != sharedB) {
      return sharedB.compareTo(sharedA);
    }

    final nutritionA = a.hasNutrition ? 1 : 0;
    final nutritionB = b.hasNutrition ? 1 : 0;
    if (nutritionA != nutritionB) {
      return nutritionB.compareTo(nutritionA);
    }

    final brandA = (a.brand ?? '').trim().toLowerCase();
    final brandB = (b.brand ?? '').trim().toLowerCase();
    final nameA = a.name.trim().toLowerCase();
    final nameB = b.name.trim().toLowerCase();
    final brandCompare = brandA.compareTo(brandB);
    if (brandCompare != 0) return brandCompare;
    final nameCompare = nameA.compareTo(nameB);
    if (nameCompare != 0) return nameCompare;
    return a.id.compareTo(b.id);
  }
}

abstract interface class ProductComparisonRemoteSource {
  Future<List<Map<String, dynamic>>> fetchOverlapProducts({
    required String overlapLiteral,
    String? query,
    required int limit,
  });

  Future<List<Map<String, dynamic>>> searchCatalog({
    String? query,
    required int limit,
  });
}

class SupabaseProductComparisonRemoteSource
    implements ProductComparisonRemoteSource {
  const SupabaseProductComparisonRemoteSource();

  @override
  Future<List<Map<String, dynamic>>> fetchOverlapProducts({
    required String overlapLiteral,
    String? query,
    required int limit,
  }) async {
    dynamic q = SupabaseService.client.from('products').select();
    q = _applyCatalogGuardrails(q);
    q = q.filter('category_tags', 'ov', overlapLiteral);
    q = _applyTextSearch(q, query);
    q = q.order('name').limit(limit);
    final rows = (await q) as List<dynamic>;
    return rows
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
  }

  @override
  Future<List<Map<String, dynamic>>> searchCatalog({
    String? query,
    required int limit,
  }) async {
    dynamic q = SupabaseService.client.from('products').select();
    q = _applyCatalogGuardrails(q);
    q = _applyTextSearch(q, query);
    q = q.order('name').limit(limit);
    final rows = (await q) as List<dynamic>;
    return rows
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
  }

  dynamic _applyCatalogGuardrails(dynamic q) {
    return q
        .or('source.is.null,source.not.ilike.%openfoodfacts%')
        .neq('name', 'Bilinmeyen Ürün')
        .neq('name', 'Unknown Product');
  }

  dynamic _applyTextSearch(dynamic q, String? query) {
    final trimmed = query?.trim().toLowerCase();
    if (trimmed == null || trimmed.isEmpty) {
      return q;
    }

    return q.or(
      'name.ilike.%$trimmed%,'
      'brand.ilike.%$trimmed%,'
      'normalized_name.ilike.%$trimmed%,'
      'barcode.ilike.%$trimmed%',
    );
  }
}

String buildPostgresTextArrayLiteral(Iterable<String> values) {
  final escaped = values
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .map(_escapePostgresArrayValue)
      .join(',');
  return '{$escaped}';
}

int countSharedCategoryTags(Product source, Product candidate) {
  final sourceTags = _normalizedTags(source.categoryTags).toSet();
  final candidateTags = _normalizedTags(candidate.categoryTags).toSet();
  return sourceTags.intersection(candidateTags).length;
}

List<String> _normalizedTags(List<String>? tags) {
  final seen = <String>{};
  final values = <String>[];
  for (final tag in tags ?? const <String>[]) {
    final normalized = tag.trim();
    if (normalized.isEmpty || !seen.add(normalized)) continue;
    values.add(normalized);
  }
  return values;
}

String _escapePostgresArrayValue(String value) {
  return '"${value.replaceAll('\\', '\\\\').replaceAll('"', r'\"')}"';
}
