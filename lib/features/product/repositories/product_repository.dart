// ignore_for_file: unnecessary_cast

import 'package:food_analyzer_app/core/services/supabase_service.dart';
import 'package:food_analyzer_app/features/imports/services/product_name_normalizer.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/product/models/product_review.dart';
import 'package:food_analyzer_app/features/product/models/ingredient.dart';
import 'package:food_analyzer_app/features/search/models/product_category.dart';
import 'package:food_analyzer_app/features/search/models/product_search_filter.dart';
import 'package:food_analyzer_app/features/search/services/category_relevance.dart';

/// Repository for product-related database queries
class ProductRepository {
  const ProductRepository();

  /// Search products by name, normalized_name, brand, or search_keywords.
  ///
  /// Runs two parallel queries:
  ///   1. ilike on name / normalized_name / brand (catches prefix/contains matches)
  ///   2. GIN array overlap on search_keywords (catches synonym/token matches)
  ///
  /// Results are merged, deduplicated, and sorted so prefix-matches come first.
  Future<List<Product>> searchByQuery(String query, {int limit = 50}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    final normalizedQuery = trimmed.toLowerCase();
    final asciiQuery = ProductNameNormalizer.toSearchable(normalizedQuery);
    final tokens = ProductNameNormalizer.tokenizeQuery(trimmed);

    final client = SupabaseService.client;

    // Build OR conditions: original + ASCII-normalized variant (deduped).
    final orParts = <String>[
      'name.ilike.%$normalizedQuery%',
      'normalized_name.ilike.%$normalizedQuery%',
      'brand.ilike.%$normalizedQuery%',
    ];
    if (asciiQuery != normalizedQuery) {
      orParts.add('normalized_name.ilike.%$asciiQuery%');
    }

    try {
      // Query 1: ilike text search
      final q1 = client
          .from('products')
          .select()
          .or(orParts.join(','))
          .or('source.is.null,source.not.ilike.%openfoodfacts%')
          .neq('name', 'Bilinmeyen Ürün')
          .neq('name', 'Unknown Product')
          .order('name')
          .limit(limit);

      // Query 2: keyword array overlap (only useful when we have ≥2 tokens)
      final Future<List<dynamic>>? q2 = tokens.length >= 2
          ? client
                .from('products')
                .select()
                .filter('search_keywords', 'ov', '{${tokens.join(",")}}')
                .or('source.is.null,source.not.ilike.%openfoodfacts%')
                .neq('name', 'Bilinmeyen Ürün')
                .neq('name', 'Unknown Product')
                .order('name')
                .limit(limit)
          : null;

      final futures = <Future<List<dynamic>>>[q1];
      if (q2 != null) futures.add(q2);
      final results = await Future.wait(futures);

      final seen = <String>{};
      final products = <Product>[];

      for (final batch in results) {
        for (final row in batch) {
          final p = Product.fromJson(row as Map<String, dynamic>);
          if (seen.add(p.id)) products.add(p);
        }
      }

      // Sort: exact/prefix name matches first, then alphabetical.
      final lq = normalizedQuery;
      final queryTokens = ProductNameNormalizer.tokenizeQuery(trimmed);
      final meatIntent = _isMeatIntentQuery(queryTokens);
      products.sort((a, b) {
        final aScore = _searchScore(a, lq, queryTokens, meatIntent);
        final bScore = _searchScore(b, lq, queryTokens, meatIntent);
        if (aScore != bScore) return bScore.compareTo(aScore);
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

      return products.take(limit).toList();
    } catch (e) {
      throw Exception('Ürün aranırken hata oluştu: $e');
    }
  }

  /// Get a single product by ID
  Future<Product?> getProductById(String id) async {
    try {
      final response = await SupabaseService.client
          .from('products')
          .select()
          .eq('id', id)
          .maybeSingle();

      if (response == null) {
        return null;
      }

      return Product.fromJson(response as Map<String, dynamic>);
    } catch (e) {
      throw Exception('Ürün detayı alınırken hata oluştu: $e');
    }
  }

  /// Get products by category ID.
  ///
  /// DEPRECATED: `category_id` is NULL for all Migros products (~3513 rows).
  /// Use [filteredSearch] with a [ProductSearchFilter] carrying `mainCategory`
  /// and the `category_tags` overlap filter instead.
  Future<List<Product>> getProductsByCategory(String categoryId) async {
    try {
      final response = await SupabaseService.client
          .from('products')
          .select()
          .eq('category_id', categoryId)
          .order('name');

      if (response.isEmpty) {
        return [];
      }

      // response is already iterable from Supabase
      return (response as List<dynamic>)
          .map<Product>(
            (json) => Product.fromJson(json as Map<String, dynamic>),
          )
          .toList();
    } catch (e) {
      throw Exception('Kategori ürünleri alınırken hata oluştu: $e');
    }
  }

  /// Search products by a list of category keywords.
  ///
  /// Matches against name, normalized_name, and brand using ilike.
  /// Returns at most [limit] results ordered by name.
  Future<List<Product>> searchByKeywords(
    List<String> keywords, {
    int limit = 40,
  }) async {
    if (keywords.isEmpty) return [];
    try {
      final parts = keywords
          .expand(
            (kw) => [
              'name.ilike.%$kw%',
              'brand.ilike.%$kw%',
              'normalized_name.ilike.%$kw%',
            ],
          )
          .join(',');

      final response = await SupabaseService.client
          .from('products')
          .select()
          .or(parts)
          .order('name')
          .limit(limit);

      if (response.isEmpty) return [];
      return (response as List<dynamic>)
          .map<Product>(
            (json) => Product.fromJson(json as Map<String, dynamic>),
          )
          .toList();
    } catch (e) {
      throw Exception('Kategori ürünleri alınırken hata oluştu: $e');
    }
  }

  /// Get relevant products for a category with strict deterministic filtering.
  ///
  /// Priority:
  /// 1. category_tags overlap candidates
  /// 2. keyword candidates
  /// 3. relevance scoring + threshold filtering
  Future<List<Product>> getProductsByCategoryStrict(
    ProductCategory category, {
    int limit = 40,
  }) async {
    final client = SupabaseService.client;
    final candidates = <Product>[];
    final seen = <String>{};

    try {
      if (category.databaseTags.isNotEmpty) {
        final overlapArg = '{${category.databaseTags.join(',')}}';
        final rows = await client
            .from('products')
            .select()
            .filter('category_tags', 'ov', overlapArg)
            .limit(limit * 3);
        for (final row in rows as List<dynamic>) {
          final p = Product.fromJson(row as Map<String, dynamic>);
          if (seen.add(p.id)) candidates.add(p);
        }
      }

      // Keyword-based candidate fetch is limited to product-type terms.
      // Name/brand-only fallbacks are intentionally avoided here.
      final keywordTokens = ProductNameNormalizer.tokenizeQuery(
        category.keywords.join(' '),
      );
      if (keywordTokens.isNotEmpty) {
        final keywordRows = await client
            .from('products')
            .select()
            .filter('search_keywords', 'ov', '{${keywordTokens.join(',')}}')
            .limit(limit * 4);

        for (final row in keywordRows as List<dynamic>) {
          final p = Product.fromJson(row as Map<String, dynamic>);
          if (seen.add(p.id)) candidates.add(p);
        }
      }

      final scored = candidates
          .map((p) {
            final result = CategoryRelevance.evaluateProduct(p, category);
            return (product: p, score: result.score, accepted: result.accepted);
          })
          .where((e) => e.accepted)
          .toList();

      scored.sort((a, b) {
        if (a.score != b.score) return b.score.compareTo(a.score);
        return a.product.name.toLowerCase().compareTo(
          b.product.name.toLowerCase(),
        );
      });

      return scored.map((e) => e.product).take(limit).toList(growable: false);
    } catch (e) {
      throw Exception('Kategori ürünleri alınırken hata oluştu: $e');
    }
  }

  int _searchScore(
    Product product,
    String normalizedQuery,
    List<String> queryTokens,
    bool meatIntent,
  ) {
    final name = product.name.toLowerCase();
    final brand = (product.brand ?? '').toLowerCase();
    final normalizedName = (product.normalizedName ?? '').toLowerCase();
    final keywords = (product.searchKeywords ?? const <String>[])
        .map((e) => e.toLowerCase())
        .toSet();

    var score = 0;

    if (name == normalizedQuery) score += 120;
    if (name.startsWith(normalizedQuery)) score += 70;
    if (name.contains(normalizedQuery)) score += 30;
    if (brand == normalizedQuery) score += 40;
    if (brand.startsWith(normalizedQuery)) score += 15;

    for (final token in queryTokens) {
      if (token.isEmpty) continue;
      if (_containsToken(name, token) ||
          _containsToken(normalizedName, token)) {
        score += 12;
      }
      if (_containsToken(brand, token)) score += 8;
      if (keywords.contains(token)) score += 10;
    }

    if (meatIntent) {
      final meatSignals = <String>{
        'salam',
        'sucuk',
        'sosis',
        'jambon',
        'pastirma',
        'pastırma',
        'hindi',
        'dana',
        'tavuk',
        'meat',
        'sarkuteri',
        'şarküteri',
      };
      final hasMeatSignal = meatSignals.any((t) {
        final st = ProductNameNormalizer.toSearchable(t);
        return _containsToken(ProductNameNormalizer.toSearchable(name), st) ||
            _containsToken(
              ProductNameNormalizer.toSearchable(normalizedName),
              st,
            ) ||
            keywords.contains(st) ||
            (product.categoryTags ?? const <String>[])
                .map((e) => e.toLowerCase())
                .contains('et_sarkuteri');
      });
      if (hasMeatSignal) score += 50;

      // Explicitly prevent "Eti" brand from dominating "et şarküteri" intent.
      if (ProductNameNormalizer.toSearchable(brand) == 'eti' &&
          !hasMeatSignal) {
        score -= 60;
      }
    }

    return score;
  }

  bool _isMeatIntentQuery(List<String> queryTokens) {
    final tokenSet = queryTokens
        .map(ProductNameNormalizer.toSearchable)
        .toSet();
    final meatSignals = <String>{
      'salam',
      'sucuk',
      'sosis',
      'jambon',
      'pastirma',
      'hindi',
      'dana',
      'tavuk',
      'sarkuteri',
      'şarküteri',
      'meat',
    };
    if (tokenSet.any(meatSignals.contains)) return true;
    return tokenSet.contains('et') && tokenSet.contains('sarkuteri');
  }

  /// Paginated, filter-aware product search for the public search screen.
  ///
  /// Server-side: source/name guardrails, text search, category_tags overlap,
  /// optional search_keywords overlap (for broad-tag subcategories), brand
  /// filter, and ordering for non-nutrition sorts.  All category and subcategory
  /// filtering is applied server-side BEFORE `.range()`.
  ///
  /// Returns [pageSize] products plus a [hasMore] flag. Nutrition filtering,
  /// ingredient filtering, and nutrition-based sorting are applied by the caller
  /// client-side.  Subcategory filtering is also applied client-side only when
  /// [filter.queryPlan.requiresClientValidation] is true.
  Future<({List<Product> results, bool hasMore})> filteredSearch(
    ProductSearchFilter filter, {
    int pageSize = 20,
    int serverOffset = 0,
  }) async {
    final client = SupabaseService.client;

    // Use dynamic to allow conditional filter chaining across builder types.
    dynamic q = client.from('products').select();

    // Guardrails: exclude OFF-sourced rows (allow null source) and invalid names.
    q = q
        .or('source.is.null,source.not.ilike.%openfoodfacts%')
        .neq('name', 'Bilinmeyen Ürün')
        .neq('name', 'Unknown Product');

    // Text search.
    if (filter.hasQuery) {
      final qStr = filter.query.trim().toLowerCase();
      q = q.or(
        'name.ilike.%$qStr%,'
        'brand.ilike.%$qStr%,'
        'normalized_name.ilike.%$qStr%',
      );
    }

    // Category filter — applied BEFORE .range() via the central query plan.
    // category_tags is the source of truth; canonical_category is not used.
    final plan = filter.queryPlan;
    if (plan.hasFilter) {
      if (plan.categoryTagsAny.isNotEmpty) {
        q = q.filter(
          'category_tags',
          'ov',
          '{${plan.categoryTagsAny.join(',')}}',
        );
      } else {
        // Category selected but tag list is empty — must never fall back to
        // an unfiltered scan of all products. Return an empty result so the
        // UI shows the correct empty-state instead of unrelated products.
        return (results: <Product>[], hasMore: false);
      }
      if (plan.searchKeywordsAny.isNotEmpty) {
        q = q.filter(
          'search_keywords',
          'ov',
          '{${plan.searchKeywordsAny.join(',')}}',
        );
      }
    }

    // Brand: exact match, one or many.
    if (filter.brands.isNotEmpty) {
      q = q.inFilter('brand', filter.brands);
    }

    // Server-side ordering (nutrition sorts fall back to name; client will sort).
    switch (filter.sortOrder) {
      case SearchSortOrder.nameAsc:
        q = q.order('name', ascending: true);
      case SearchSortOrder.nameDesc:
        q = q.order('name', ascending: false);
      case SearchSortOrder.brandAsc:
        q = q.order('brand', ascending: true).order('name', ascending: true);
      case SearchSortOrder.brandDesc:
        q = q.order('brand', ascending: false).order('name', ascending: false);
      case SearchSortOrder.newestFirst:
        q = q.order('created_at', ascending: false);
      case SearchSortOrder.relevance:
      case SearchSortOrder.energyAsc:
      case SearchSortOrder.energyDesc:
      case SearchSortOrder.proteinsAsc:
      case SearchSortOrder.proteinsDesc:
      case SearchSortOrder.sugarsAsc:
      case SearchSortOrder.sugarsDesc:
      case SearchSortOrder.fatAsc:
      case SearchSortOrder.fatDesc:
      case SearchSortOrder.saturatedFatAsc:
      case SearchSortOrder.saturatedFatDesc:
      case SearchSortOrder.saltAsc:
      case SearchSortOrder.saltDesc:
      case SearchSortOrder.fiberAsc:
      case SearchSortOrder.fiberDesc:
        q = q.order('name', ascending: true);
    }

    // Fetch pageSize + 1 to detect whether more pages exist.
    final fetchCount = pageSize + 1;
    q = q.range(serverOffset, serverOffset + fetchCount - 1);

    try {
      final rows = (await q) as List<dynamic>;
      final hasMore = rows.length == fetchCount;
      final products = rows
          .take(pageSize)
          .map<Product>((r) => Product.fromJson(r as Map<String, dynamic>))
          .toList();
      return (results: products, hasMore: hasMore);
    } catch (e) {
      throw Exception('Ürün araması başarısız: $e');
    }
  }

  /// Returns the distinct brand names scoped to [filter]'s category context.
  ///
  /// Used by the filter sheet brand checkbox list. Ignores [filter.brands] so
  /// it always returns all available brands for the current category/query,
  /// allowing the user to re-select previously removed brands.
  Future<List<String>> getBrandFacets(ProductSearchFilter filter) async {
    final client = SupabaseService.client;

    dynamic q = client
        .from('products')
        .select('brand')
        .or('source.is.null,source.not.ilike.%openfoodfacts%')
        .neq('name', 'Bilinmeyen Ürün')
        .neq('name', 'Unknown Product')
        .not('brand', 'is', null);

    if (filter.hasQuery) {
      final qStr = filter.query.trim().toLowerCase();
      q = q.or(
        'name.ilike.%$qStr%,'
        'brand.ilike.%$qStr%,'
        'normalized_name.ilike.%$qStr%',
      );
    }

    final plan = filter.queryPlan;
    if (plan.hasFilter) {
      if (plan.categoryTagsAny.isNotEmpty) {
        q = q.filter(
          'category_tags',
          'ov',
          '{${plan.categoryTagsAny.join(',')}}',
        );
      }
      if (plan.searchKeywordsAny.isNotEmpty) {
        q = q.filter(
          'search_keywords',
          'ov',
          '{${plan.searchKeywordsAny.join(',')}}',
        );
      }
    }

    q = q.order('brand').limit(300);

    try {
      final rows = await q as List<dynamic>;
      final brands = <String>{};
      for (final row in rows) {
        final brand = (row as Map<String, dynamic>)['brand'] as String?;
        if (brand != null && brand.trim().isNotEmpty) {
          brands.add(brand.trim());
        }
      }
      final sorted = brands.toList()..sort();
      return sorted;
    } catch (_) {
      return const [];
    }
  }

  bool _containsToken(String haystack, String token) {
    if (token.trim().isEmpty || haystack.trim().isEmpty) return false;
    final escaped = RegExp.escape(token);
    return RegExp(
      '(^|[^a-z0-9])$escaped([^a-z0-9]|\$)',
      caseSensitive: false,
    ).hasMatch(haystack);
  }

  /// Get products by barcode
  Future<Product?> getProductByBarcode(String barcode) async {
    try {
      final response = await SupabaseService.client
          .from('products')
          .select()
          .eq('barcode', barcode)
          .maybeSingle();

      if (response == null) {
        return null;
      }

      return Product.fromJson(response as Map<String, dynamic>);
    } catch (e) {
      throw Exception('Barkod aranırken hata oluştu: $e');
    }
  }

  /// Get product review by product ID
  Future<ProductReview?> getProductReviewByProductId(String productId) async {
    try {
      final response = await SupabaseService.client
          .from('product_reviews')
          .select()
          .eq('product_id', productId)
          .eq('review_status', 'published')
          .maybeSingle();

      if (response == null) {
        return null;
      }

      return ProductReview.fromJson(response as Map<String, dynamic>);
    } catch (e) {
      throw Exception('Ürün incelemesi alınırken hata oluştu: $e');
    }
  }

  /// Get ingredients linked to a product with confidence scores
  Future<List<Ingredient>> getProductIngredients(String productId) async {
    try {
      // Query product_ingredients with joined ingredient data
      final response = await SupabaseService.client
          .from('product_ingredients')
          .select(
            'ingredients:ingredient_id(id, name, normalized_name, alternative_names, aliases, common_names, english_names, e_code, category, risk_level, additive_group, short_description, long_description, child_warning, source_references, source_url, ingredient_type, short_purpose, short_risk_summary, caution_groups, processing_role, created_at, updated_at)',
          )
          .eq('product_id', productId);

      if (response.isEmpty) {
        return [];
      }

      // Extract ingredient data from nested response
      final ingredients = <Ingredient>[];
      for (final item in response as List) {
        if (item is Map<String, dynamic> && item['ingredients'] != null) {
          final ingredientData = item['ingredients'];
          if (ingredientData is Map<String, dynamic>) {
            ingredients.add(Ingredient.fromJson(ingredientData));
          }
        }
      }

      return ingredients;
    } catch (e) {
      throw Exception('Ürün içindekileri alınırken hata oluştu: $e');
    }
  }

  /// Get all ingredients from the database
  Future<List<Ingredient>> getAllIngredients() async {
    try {
      final response = await SupabaseService.client
          .from('ingredients')
          .select()
          .order('name');

      if (response.isEmpty) {
        return [];
      }

      return (response as List<dynamic>)
          .map<Ingredient>(
            (json) => Ingredient.fromJson(json as Map<String, dynamic>),
          )
          .toList();
    } catch (e) {
      throw Exception('İçerikler yüklenirken hata oluştu: $e');
    }
  }
}
