import 'package:dio/dio.dart';
import 'package:food_analyzer_app/features/imports/services/open_food_facts_service.dart';
import 'package:food_analyzer_app/features/imports/services/product_name_normalizer.dart';
import 'package:food_analyzer_app/features/product_staging/models/product_candidate.dart';

/// Minimal Open Food Facts → [ProductCandidate] connector for testing the
/// staging pipeline with a single barcode or product JSON.
///
/// This is NOT a bulk importer. It writes nothing to `products`. Its only job
/// is to map one OFF product into a [ProductCandidate] so the candidate can be
/// staged (via ProductStagingRepository) for admin review.
class OpenFoodFactsCandidateConnector {
  final Dio _dio;

  OpenFoodFactsCandidateConnector([Dio? dio]) : _dio = dio ?? Dio();

  static const String _source = 'open_food_facts';

  /// Fetch a single OFF product by barcode and map it to a [ProductCandidate].
  ///
  /// Returns null when the product is not listed in OFF.
  /// Throws [OffNetworkException] on connectivity/timeout failures.
  Future<ProductCandidate?> fetchCandidateByBarcode(String barcode) async {
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
              'ingredients_text_en,image_front_url,image_url,selected_images',
        },
        options: Options(
          receiveTimeout: const Duration(milliseconds: 5000),
          sendTimeout: const Duration(milliseconds: 5000),
        ),
      );
      if (resp.statusCode != 200) return null;

      final data = resp.data as Map<String, dynamic>?;
      if (data == null) return null;
      if ((data['status'] as int? ?? 0) != 1) return null;

      final product = data['product'] as Map<String, dynamic>?;
      if (product == null) return null;

      return candidateFromOffJson(product);
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

  /// Map a raw OFF product JSON object into a [ProductCandidate].
  ///
  /// Name priority: product_name_tr → product_name → generic_name_tr →
  /// generic_name → product_name_en (handled by
  /// [ProductNameNormalizer.pickBestProductName]).
  ProductCandidate candidateFromOffJson(Map<String, dynamic> productJson) {
    final barcode = (productJson['code'] as String?)?.trim();

    final brand = _firstBrand(productJson['brands'] as String?);

    final rawName = ProductNameNormalizer.pickBestProductName(productJson);
    final cleanedName = ProductNameNormalizer.cleanDisplayName(
      rawName,
      brand: brand,
    );
    final name = cleanedName.isNotEmpty ? cleanedName : null;

    final ingredientsText = _pickIngredients(productJson);
    final imageFrontUrl = _selectFrontImage(productJson);

    // Reuse the shared OFF nutriments parser → NutritionData → toMap so the
    // nutrition_json shape stays compatible with the rest of the app.
    final nutriRaw = productJson['nutriments'] as Map<String, dynamic>?;
    final nutrition = nutriRaw != null ? parseOffNutriments(nutriRaw) : null;
    final nutritionJson = nutrition?.toMap();

    final categorySuggestion = (productJson['categories'] as String?)?.trim();
    final categoryTags = _stringList(productJson['categories_tags']);

    final searchKeywords = name != null
        ? ProductNameNormalizer.buildSearchKeywords(
            displayName: name,
            brand: brand,
            offCategories: categoryTags,
          )
        : null;

    final sourceUrl = (productJson['url'] as String?)?.trim().isNotEmpty == true
        ? (productJson['url'] as String).trim()
        : (barcode != null
              ? 'https://tr.openfoodfacts.org/product/$barcode'
              : null);

    return ProductCandidate(
      barcode: (barcode?.isNotEmpty ?? false) ? barcode : null,
      name: name,
      brand: brand,
      categorySuggestion: (categorySuggestion?.isNotEmpty ?? false)
          ? categorySuggestion
          : null,
      categoryTags: (categoryTags?.isNotEmpty ?? false) ? categoryTags : null,
      searchKeywords: (searchKeywords?.isNotEmpty ?? false)
          ? searchKeywords
          : null,
      imageFrontUrl: imageFrontUrl,
      ingredientsText: ingredientsText,
      nutritionJson: (nutritionJson?.isNotEmpty ?? false)
          ? nutritionJson
          : null,
      source: _source,
      sourceUrl: sourceUrl,
      rawSourcePayload: productJson,
      // Field-level provenance: every populated field came from OFF.
      nameSource: name != null ? _source : null,
      brandSource: brand != null ? _source : null,
      imageSource: imageFrontUrl != null ? _source : null,
      ingredientsSource: ingredientsText != null ? _source : null,
      nutritionSource: nutritionJson != null ? _source : null,
      categorySource:
          (categorySuggestion != null || (categoryTags?.isNotEmpty ?? false))
          ? _source
          : null,
    );
  }

  // ── helpers ──────────────────────────────────────────────────────────────

  /// OFF `brands` is a comma-separated list; use the first entry.
  String? _firstBrand(String? brands) {
    final trimmed = brands?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    final first = trimmed.split(',').first.trim();
    return first.isNotEmpty ? first : null;
  }

  String? _pickIngredients(Map<String, dynamic> product) {
    String? text = (product['ingredients_text_tr'] as String?)?.trim();
    if (text == null || text.isEmpty) {
      text = (product['ingredients_text'] as String?)?.trim();
    }
    if (text == null || text.isEmpty) {
      text = (product['ingredients_text_en'] as String?)?.trim();
    }
    return (text?.isNotEmpty ?? false) ? text : null;
  }

  /// Front image priority: selected_images.front.display.tr/en/any →
  /// image_front_url → image_url.
  String? _selectFrontImage(Map<String, dynamic> product) {
    final selected = product['selected_images'] as Map<String, dynamic>?;
    final front = selected?['front'] as Map<String, dynamic>?;
    final display = front?['display'] as Map<String, dynamic>?;
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

    final frontUrl = (product['image_front_url'] as String?)?.trim();
    if (frontUrl != null && frontUrl.isNotEmpty) return frontUrl;

    final imageUrl = (product['image_url'] as String?)?.trim();
    if (imageUrl != null && imageUrl.isNotEmpty) return imageUrl;

    return null;
  }

  static List<String>? _stringList(dynamic value) {
    if (value is! List) return null;
    final list = value.map((e) => e.toString()).toList();
    return list.isNotEmpty ? list : null;
  }
}
