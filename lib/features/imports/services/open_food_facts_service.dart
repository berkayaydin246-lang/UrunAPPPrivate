import 'package:dio/dio.dart';
import 'package:food_analyzer_app/features/imports/services/product_name_normalizer.dart';
import 'package:food_analyzer_app/features/imports/models/off_product.dart';
import 'package:food_analyzer_app/features/product/models/nutrition_data.dart';

/// Thrown when an OFF request fails due to connectivity or timeout.
class OffNetworkException implements Exception {
  const OffNetworkException();
}

/// Simple Open Food Facts client for barcode lookups and text search.
class OpenFoodFactsService {
  final Dio _dio;

  OpenFoodFactsService([Dio? dio]) : _dio = dio ?? Dio();

  /// Fetch product by barcode from Open Food Facts.
  ///
  /// Returns null when the product is not listed in OFF.
  /// Throws [OffNetworkException] on connectivity or timeout failures.
  Future<OffProduct?> fetchProductByBarcode(String barcode) async {
    final url = 'https://tr.openfoodfacts.org/api/v0/product/$barcode.json';
    try {
      final resp = await _dio.get(
        url,
        queryParameters: {
          'lc': 'tr',
          'fields':
              'code,url,product_name,product_name_tr,product_name_en,'
              'abbreviated_product_name,abbreviated_product_name_tr,'
              'generic_name,generic_name_tr,brands,quantity,categories,'
              'categories_tags,nutriments,ingredients_text,ingredients_text_tr,'
              'image_front_url,selected_images',
        },
        options: Options(
          receiveTimeout: const Duration(milliseconds: 5000),
          sendTimeout: const Duration(milliseconds: 5000),
        ),
      );
      if (resp.statusCode != 200) return null;

      final data = resp.data as Map<String, dynamic>?;
      if (data == null) return null;

      final status = data['status'] as int? ?? 0;
      if (status != 1) return null;

      final product = data['product'] as Map<String, dynamic>?;
      if (product == null) return null;

      final brand = (product['brands'] as String?)?.trim();
      final localizedName = ProductNameNormalizer.pickBestProductName(product);
      final name = ProductNameNormalizer.cleanDisplayName(
        localizedName,
        brand: brand,
      );
      final imageUrl = _selectFrontImage(product);
      final sourceUrl = (product['url'] as String?)?.trim().isNotEmpty == true
          ? (product['url'] as String).trim()
          : 'https://tr.openfoodfacts.org/product/$barcode';
      final categoriesText = (product['categories'] as String?)?.trim();

      // Prefer Turkish ingredients when available, then default, then English
      String? ingredientsText = (product['ingredients_text_tr'] as String?)
          ?.trim();
      if (ingredientsText == null || ingredientsText.isEmpty) {
        ingredientsText = (product['ingredients_text'] as String?)?.trim();
      }
      if (ingredientsText == null || ingredientsText.isEmpty) {
        ingredientsText = (product['ingredients_text_en'] as String?)?.trim();
      }
      if (ingredientsText?.isEmpty ?? false) ingredientsText = null;

      List<String>? categories;
      final catRaw = product['categories_tags'] as List<dynamic>?;
      if (catRaw != null) {
        categories = catRaw.map((e) => e.toString()).toList();
      }

      return OffProduct(
        barcode: barcode,
        name: name.isNotEmpty ? name : 'Bilinmeyen Ürün',
        brand: brand,
        ingredientsText: ingredientsText,
        imageUrl: imageUrl,
        categories: categories,
        categoriesText: categoriesText?.isNotEmpty == true
            ? categoriesText
            : null,
        sourceUrl: sourceUrl,
        nutriments: _extractNutriments(product),
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.connectionError) {
        throw const OffNetworkException();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Search Open Food Facts by text query.
  ///
  /// Returns at most [pageSize] products. Only products with a valid barcode
  /// are included. Returns an empty list on network failure (non-throwing).
  Future<List<OffProduct>> searchByText(
    String query, {
    int pageSize = 10,
  }) async {
    if (query.trim().isEmpty) return [];
    const url = 'https://tr.openfoodfacts.org/cgi/search.pl';
    try {
      final resp = await _dio.get(
        url,
        queryParameters: {
          'search_terms': query.trim(),
          'action': 'process',
          'json': '1',
          'page_size': pageSize.toString(),
          'lc': 'tr',
          'fields':
              'code,url,product_name,product_name_tr,product_name_en,'
              'abbreviated_product_name,abbreviated_product_name_tr,'
              'generic_name,generic_name_tr,brands,quantity,categories,categories_tags,'
              'ingredients_text,ingredients_text_tr,ingredients_text_en,'
              'image_front_url,image_front_small_url,selected_images,nutriments',
        },
        options: Options(
          receiveTimeout: const Duration(milliseconds: 8000),
          sendTimeout: const Duration(milliseconds: 5000),
        ),
      );
      if (resp.statusCode != 200) return [];
      final data = resp.data as Map<String, dynamic>?;
      if (data == null) return [];
      final rawProducts = data['products'] as List<dynamic>?;
      if (rawProducts == null) return [];
      return rawProducts
          .whereType<Map<String, dynamic>>()
          .map(_parseSearchProduct)
          .whereType<OffProduct>()
          .toList();
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.connectionError) {
        throw const OffNetworkException();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  OffProduct? _parseSearchProduct(Map<String, dynamic> product) {
    final barcode = (product['code'] as String?)?.trim();
    if (barcode == null || barcode.isEmpty) return null;

    final brand = (product['brands'] as String?)?.trim();
    final localizedName = ProductNameNormalizer.pickBestProductName(product);
    final name = ProductNameNormalizer.cleanDisplayName(
      localizedName,
      brand: brand,
    );

    String? ingredientsText = (product['ingredients_text_tr'] as String?)
        ?.trim();
    if (ingredientsText == null || ingredientsText.isEmpty) {
      ingredientsText = (product['ingredients_text'] as String?)?.trim();
    }
    if (ingredientsText == null || ingredientsText.isEmpty) {
      ingredientsText = (product['ingredients_text_en'] as String?)?.trim();
    }
    if (ingredientsText?.isEmpty ?? false) ingredientsText = null;

    final imageUrl = _selectFrontImage(product);
    final categoriesText = (product['categories'] as String?)?.trim();

    List<String>? categories;
    final catRaw = product['categories_tags'] as List<dynamic>?;
    if (catRaw != null) {
      categories = catRaw.map((e) => e.toString()).toList(growable: false);
    }

    NutritionData? nutriments;
    final nutriRaw = product['nutriments'] as Map<String, dynamic>?;
    if (nutriRaw != null) nutriments = parseOffNutriments(nutriRaw);

    return OffProduct(
      barcode: barcode,
      name: name.isNotEmpty ? name : 'Bilinmeyen Ürün',
      brand: (brand?.isNotEmpty ?? false) ? brand : null,
      ingredientsText: ingredientsText,
      imageUrl: (imageUrl?.isNotEmpty ?? false) ? imageUrl : null,
      categories: categories,
      categoriesText: categoriesText?.isNotEmpty == true
          ? categoriesText
          : null,
      sourceUrl: (product['url'] as String?)?.trim().isNotEmpty == true
          ? (product['url'] as String).trim()
          : 'https://tr.openfoodfacts.org/product/$barcode',
      nutriments: nutriments,
    );
  }

  /// Pick the best front-of-pack image URL from an OFF product JSON map.
  ///
  /// Priority:
  ///   1. selected_images.front.display.tr  (Turkish locale, display quality)
  ///   2. selected_images.front.display.en  (English locale)
  ///   3. selected_images.front.display.*   (any available locale)
  ///   4. selected_images.front.small.*     (any locale, smaller)
  ///   5. image_front_url                   (full-size front photo)
  ///   6. image_front_small_url             (small front photo)
  ///   7. image_url                         (generic image, last resort)
  String? _selectFrontImage(Map<String, dynamic> product) {
    final selected = product['selected_images'] as Map<String, dynamic>?;
    if (selected != null) {
      final front = selected['front'] as Map<String, dynamic>?;
      if (front != null) {
        // display quality
        final display = front['display'] as Map<String, dynamic>?;
        if (display != null) {
          final tr = (display['tr'] as String?)?.trim();
          if (tr != null && tr.isNotEmpty) return tr;
          final en = (display['en'] as String?)?.trim();
          if (en != null && en.isNotEmpty) return en;
          for (final v in display.values) {
            final url = (v as String?)?.trim();
            if (url != null && url.isNotEmpty) return url;
          }
        }
        // small quality (any locale)
        final small = front['small'] as Map<String, dynamic>?;
        if (small != null) {
          for (final v in small.values) {
            final url = (v as String?)?.trim();
            if (url != null && url.isNotEmpty) return url;
          }
        }
      }
    }

    final frontUrl = (product['image_front_url'] as String?)?.trim();
    if (frontUrl != null && frontUrl.isNotEmpty) return frontUrl;

    final frontSmall = (product['image_front_small_url'] as String?)?.trim();
    if (frontSmall != null && frontSmall.isNotEmpty) return frontSmall;

    final imageUrl = (product['image_url'] as String?)?.trim();
    if (imageUrl != null && imageUrl.isNotEmpty) return imageUrl;

    return null;
  }

  NutritionData? _extractNutriments(Map<String, dynamic> product) {
    final raw = product['nutriments'] as Map<String, dynamic>?;
    if (raw == null) return null;
    return parseOffNutriments(raw);
  }
}

/// Parse an Open Food Facts `nutriments` map into [NutritionData].
///
/// Key-variant priority:
///   1. _100g (solid products)
///   2. _100ml (beverages)
///   3. bare key without suffix (per-serving fallback)
///
/// Accepts int, double, or string values.
/// String values may use comma as decimal separator ("1,5" → 1.5).
/// If energy-kcal is absent but energy-kj is present, kcal is derived
/// (1 kcal ≈ 4.184 kJ).
/// Returns null when no recognised field yields a value.
NutritionData? parseOffNutriments(Map<String, dynamic> raw) {
  // Parse a single key, handling int / double / string / comma-decimal.
  double? n(String key) {
    final v = raw[key];
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) {
      // Support both dot ("1.5") and comma ("1,5") decimal separators.
      return double.tryParse(v) ?? double.tryParse(v.replaceAll(',', '.'));
    }
    return null;
  }

  // Try the full set of known key variants for a given nutrient.
  // Dash-variant first (most common in OFF), then underscore, then 100ml,
  // then bare key (no suffix).
  double? nFat(String base) =>
      n('${base}_100g') ?? n('${base}_100ml') ?? n(base); // bare key fallback

  double? nSaturated() =>
      n('saturated-fat_100g') ??
      n('saturated_fat_100g') ??
      n('saturated-fat_100ml') ??
      n('saturated_fat_100ml') ??
      n('saturated-fat') ??
      n('saturated_fat');

  // Derive kcal from kJ when the kcal key is absent.
  // 1 kcal = 4.184 kJ (rounded; exact conversion varies by source).
  double? energyKcalFromKj() {
    final kj =
        n('energy-kj_100g') ??
        n('energy_kj_100g') ??
        n('energy-kj_100ml') ??
        n('energy_kj_100ml') ??
        n('energy_100g') ??
        n('energy_100ml') ??
        n('energy-kj') ??
        n('energy_kj');
    return kj != null ? kj / 4.184 : null;
  }

  final energyKcal =
      n('energy-kcal_100g') ??
      n('energy_kcal_100g') ??
      n('energy-kcal_100ml') ??
      n('energy_kcal_100ml') ??
      n('energy-kcal') ??
      n('energy_kcal') ??
      energyKcalFromKj();

  final data = NutritionData(
    energyKcal: energyKcal,
    fat: nFat('fat'),
    saturatedFat: nSaturated(),
    carbohydrates: nFat('carbohydrates'),
    sugars: nFat('sugars'),
    fiber: nFat('fiber'),
    proteins: nFat('proteins'),
    salt: nFat('salt'),
    sodium: nFat('sodium'),
  );

  return data.hasAnyData ? data : null;
}
