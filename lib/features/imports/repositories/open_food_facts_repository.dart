import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:food_analyzer_app/core/services/supabase_service.dart';
import 'package:food_analyzer_app/features/imports/models/off_import_result.dart';
import 'package:food_analyzer_app/features/imports/models/off_product.dart';
import 'package:food_analyzer_app/features/imports/services/normalizer.dart';
import 'package:food_analyzer_app/features/imports/services/open_food_facts_service.dart';
import 'package:food_analyzer_app/features/imports/services/product_name_normalizer.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/search/services/product_category_classifier.dart';

/// Repository that fetches from Open Food Facts and persists new products to
/// the local database, preventing duplicate imports.
class OpenFoodFactsRepository {
  final OpenFoodFactsService _service;

  OpenFoodFactsRepository([OpenFoodFactsService? service])
    : _service = service ?? OpenFoodFactsService();

  /// Fetch a product by barcode, persisting it to the local DB when new.
  ///
  /// Priority order:
  ///   1. Existing local product with the same barcode → return as-is.
  ///   2. OFF fetch → check for a name+brand merge candidate → update + return.
  ///   3. OFF fetch → no merge candidate → insert new imported product.
  ///
  /// Returns null when OFF has no data for the barcode.
  /// Throws [OffNetworkException] on connectivity failures.
  Future<OffImportResult?> fetchAndPersistByBarcode(String rawBarcode) async {
    final barcode = ImportNormalizer.normalizeBarcode(rawBarcode);
    final client = SupabaseService.client;

    // 1. Check local DB — return existing product for any verification status.
    final localRow = await client
        .from('products')
        .select()
        .eq('barcode', barcode)
        .maybeSingle();

    if (localRow != null) {
      final local = Product.fromJson(localRow);
      // For verified products, never touch the data.
      if (local.verificationStatus == 'verified') {
        return OffImportResult(
          product: local,
          source: OffImportSource.existingLocal,
          isLimitedData: false,
        );
      }
      // For incomplete products, enrich from OFF if fields are missing.
      final missingImage = local.imageUrl == null;
      final missingIngredients =
          local.ingredientsText == null ||
          local.ingredientsText!.trim().isEmpty;
      final missingNutrition = local.nutritionText == null;
      if (missingImage || missingIngredients || missingNutrition) {
        final enriched = await _enrichFromOff(
          client: client,
          local: local,
          barcode: barcode,
          missingImage: missingImage,
          missingIngredients: missingIngredients,
          missingNutrition: missingNutrition,
        );
        return OffImportResult(
          product: enriched,
          source: OffImportSource.existingLocal,
          isLimitedData:
              enriched.imageUrl == null &&
              (enriched.ingredientsText?.trim().isEmpty ?? true),
        );
      }
      return OffImportResult(
        product: local,
        source: OffImportSource.existingLocal,
        isLimitedData: false,
      );
    }

    // 2. Fetch from Open Food Facts.
    final off = await _service.fetchProductByBarcode(barcode);
    if (off == null) {
      return null;
    }

    // 3. Normalize imported data.
    final rawName = off.name?.trim();
    // Clean display name: strip price/size/duplicate fragments from OFF names.
    final productName = (rawName != null && rawName.isNotEmpty)
        ? ProductNameNormalizer.cleanDisplayName(rawName, brand: off.brand)
        : null;
    final normalizedName = productName != null && productName.isNotEmpty
        ? ImportNormalizer.normalizeText(productName)
        : null;

    final ingredientsText = ImportNormalizer.cleanIngredientsText(
      off.ingredientsText,
    );

    final cleanBrand = (off.brand?.trim().isEmpty ?? true)
        ? null
        : off.brand?.trim();

    final isLimitedData =
        ingredientsText.trim().isEmpty && off.imageUrl == null;

    // 4. Merge heuristic — look for an existing product with the same
    // normalized name + brand but no barcode yet.
    if (normalizedName != null && cleanBrand != null) {
      final candidatesResponse = await client
          .from('products')
          .select()
          .ilike('normalized_name', normalizedName)
          .ilike('brand', cleanBrand)
          .limit(5);

      final candidates = (candidatesResponse as List<dynamic>)
          .cast<Map<String, dynamic>>();

      Map<String, dynamic>? mergeRow;

      for (final row in candidates) {
        final existingBarcode = row['barcode'];
        if (existingBarcode == null || existingBarcode.toString().isEmpty) {
          mergeRow = row;
          break;
        }
      }

      if (mergeRow != null) {
        final updated = await client
            .from('products')
            .update({'barcode': barcode})
            .eq('id', mergeRow['id'] as String)
            .select()
            .single();

        return OffImportResult(
          product: Product.fromJson(updated),
          source: OffImportSource.existingLocal,
          isLimitedData: isLimitedData,
        );
      }
    }

    // Stage 5 (INSERT new OFF product into products) has been intentionally
    // removed. OFF products must not be inserted directly into the products
    // catalog. They are previewed in the barcode flow via fetchExternalPreview
    // and enter the catalog only through the staging/approval pipeline.
    _debugOffLog(
      '[OFF] barcode=$barcode found on OFF but no local match — '
      'returning null (use fetchExternalPreview for preview)',
    );
    return null;
  }

  /// Fetch a product from Open Food Facts as a read-only external preview.
  ///
  /// Does NOT write to the database. Used by the barcode flow when no local
  /// product row exists. The returned [OffProduct] is shown to the user with
  /// a clear "unverified / external" label; it enters the catalog only via
  /// staging/admin approval.
  ///
  /// Returns null when OFF has no data for the barcode or on network error.
  Future<OffProduct?> fetchExternalPreview(String rawBarcode) async {
    final barcode = ImportNormalizer.normalizeBarcode(rawBarcode);
    try {
      return await _service.fetchProductByBarcode(barcode);
    } on OffNetworkException {
      rethrow;
    } catch (_) {
      return null;
    }
  }

  /// Fetch from OFF and patch only the missing fields on an existing product.
  /// Never called for verified products. Returns the (possibly unchanged) product.
  Future<Product> _enrichFromOff({
    required dynamic client,
    required Product local,
    required String barcode,
    required bool missingImage,
    required bool missingIngredients,
    required bool missingNutrition,
  }) async {
    try {
      final off = await _service.fetchProductByBarcode(barcode);
      if (off == null) return local;

      final patch = <String, dynamic>{};

      if (missingImage && off.imageUrl != null) {
        patch['image_url'] = off.imageUrl;
      }

      if (missingIngredients && off.ingredientsText != null) {
        final cleaned = ImportNormalizer.cleanIngredientsText(
          off.ingredientsText,
        );
        if (cleaned.isNotEmpty) {
          patch['ingredients_text'] = cleaned;
        }
      }

      if (missingNutrition && off.nutriments != null) {
        final nutritionText = jsonEncode(off.nutriments!.toMap());
        patch['nutrition_text'] = nutritionText;
        _debugOffLog(
          '[OFF] enriching barcode=$barcode nutrition_text set '
          'hasAnyData=${off.nutriments!.hasAnyData}',
        );
      }

      // search_keywords is intentionally excluded from this patch.
      // Including it here would cause the UPDATE to fail when the column does
      // not yet exist, which would silently discard the nutrition update above.
      // Keywords/tags are updated separately via _tryUpdateMetadata below.

      if (patch.isEmpty) return local;

      final updated = await client
          .from('products')
          .update(patch)
          .eq('id', local.id)
          .select()
          .single();

      final result = Product.fromJson(updated as Map<String, dynamic>);
      _debugOffLog(
        '[OFF] enriched id=${local.id} '
        'nutrition_text=${result.nutritionText != null}',
      );

      // Best-effort: update keywords after the critical enrichment succeeded.
      if (local.searchKeywords == null || local.searchKeywords!.isEmpty) {
        final keywords = ProductNameNormalizer.buildSearchKeywords(
          displayName: local.name,
          brand: local.brand,
          offCategories: off.categories,
        );
        final categoryTags = ProductCategoryClassifier.classify(
          name: local.name,
          brand: local.brand,
          searchKeywords: keywords,
          offCategories: off.categoriesText != null
              ? [off.categoriesText!]
              : null,
          offCategoryTags: off.categories,
        );
        await _tryUpdateMetadata(
          client,
          local.id,
          searchKeywords: keywords,
          categoryTags: categoryTags.categoryTags,
        );
      }

      return result;
    } catch (_) {
      // Enrichment is best-effort; return the local product unchanged on error.
      return local;
    }
  }

  /// Update products.search_keywords/category_tags without throwing.
  ///
  /// Wrapped in its own try-catch so that a missing search_keywords column
  /// (migration not yet applied) never blocks nutrition or image enrichment.
  Future<void> _tryUpdateMetadata(
    dynamic client,
    String productId, {
    required List<String> searchKeywords,
    required List<String> categoryTags,
  }) async {
    if (searchKeywords.isEmpty && categoryTags.isEmpty) return;
    final payload = <String, dynamic>{};
    if (searchKeywords.isNotEmpty) {
      payload['search_keywords'] = searchKeywords;
    }
    if (categoryTags.isNotEmpty) {
      payload['category_tags'] = categoryTags;
    }

    try {
      await client.from('products').update(payload).eq('id', productId);
    } catch (_) {
      // Silently ignore: column may not exist in all environments.
    }
  }
}

void _debugOffLog(String message) {
  if (!kDebugMode) return;
  debugPrint(message);
}
