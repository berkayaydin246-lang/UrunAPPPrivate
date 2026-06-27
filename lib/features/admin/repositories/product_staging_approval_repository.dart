import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:food_analyzer_app/core/services/supabase_service.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/product_staging/models/product_candidate.dart';

/// Outcome of approving a staged product.
enum ApproveStagedResult {
  approved, // new product row created + staging marked approved
  updatedExisting, // existing product enriched + staging marked approved
  notFound, // staging id not found
  invalidBarcode, // no barcode AND source is not eligible for no-barcode approval
  alreadyProcessed, // staging row is not pending/needs_review
  productSavedStagingFailed, // product written, but staging status update failed
  // No-barcode HARD blockers (web_scraper / manual_seed sources).
  // Manual approval blocks ONLY on absolute minimum identity fields — missing
  // nutrition, ingredients, image, or brand are non-blocking warnings shown to
  // the admin in the UI. A low quality_score never blocks by itself.
  insufficientData, // no barcode and name missing
  missingBrand, // informational only — no longer a hard blocker
  missingImage, // informational only — no longer a hard blocker
  missingIngredients, // informational only — no longer a hard blocker
  missingNutrition, // informational only — no longer a hard blocker
  missingSourceLink, // no barcode and no source_url (cannot dedupe/match safely)
  autoRejectedNoAnalysisData, // BOTH ingredients and nutrition missing — auto-rejected, not inserted into products
}

extension ApproveStagedResultX on ApproveStagedResult {
  bool get productWasSaved =>
      this == ApproveStagedResult.approved ||
      this == ApproveStagedResult.updatedExisting ||
      this == ApproveStagedResult.productSavedStagingFailed;

  bool get stagingWasApproved =>
      this == ApproveStagedResult.approved ||
      this == ApproveStagedResult.updatedExisting;
}

/// Edited field overrides an admin may supply before approving a staged product.
class StagingApprovalEdits {
  final String? name;
  final String? brand;
  final String? ingredientsText;
  final String? categorySuggestion;
  final String? adminNote;

  const StagingApprovalEdits({
    this.name,
    this.brand,
    this.ingredientsText,
    this.categorySuggestion,
    this.adminNote,
  });
}

/// Moves reviewed `product_staging` rows into the final `products` catalog.
///
/// Approval NEVER deletes the staging row — it only flips its status to
/// `approved`. It NEVER overwrites existing non-null product fields (verified or
/// manual data is preserved); it only fills gaps.
class ProductStagingApprovalRepository {
  const ProductStagingApprovalRepository();

  static const String _stagingTable = 'product_staging';
  static const String _productsTable = 'products';

  // Staging rows in these statuses are eligible for the review queue / approval.
  static const _reviewableStatuses = {'pending', 'needs_review'};

  // ── eligibility (pure, testable) ────────────────────────────────────────────

  // ── analysis-data helpers (pure, testable) ─────────────────────────────────

  static bool hasMissingIngredients(ProductCandidate candidate) =>
      candidate.hasMissingIngredients;

  static bool hasMissingNutrition(ProductCandidate candidate) =>
      candidate.hasMissingNutrition;

  /// True when the candidate has BOTH missing ingredients and missing nutrition.
  ///
  /// Such products have no analyzable data and must be auto-rejected instead of
  /// staged for approval — they cannot support ingredient analysis or nutrition
  /// queries and would only clutter the review queue.
  static bool shouldAutoRejectForNoAnalysisData(ProductCandidate candidate) =>
      candidate.hasNoAnalysisData;

  /// Whether [source] may be approved without a barcode (web-discovered or
  /// manually seeded products). Barcode-based imports (e.g. open_food_facts)
  /// still require a barcode.
  static bool sourceAllowsNoBarcode(String? source) {
    final s = (source ?? '').trim();
    return s.startsWith('web_scraper:') || s == 'manual_seed';
  }

  /// The blocking reason for approving a candidate, or null when it may be
  /// approved. Pure so the UI/tests can reason about it without a DB.
  ///
  /// Barcode present → always allowed (barcode flow unchanged). Barcode absent →
  /// allowed for eligible sources when the admin-corrected fields are complete;
  /// a low quality_score alone never blocks manual approval.
  static ApproveStagedResult? approvalBlockReason(
    ProductCandidate candidate,
    StagingApprovalEdits edits,
  ) {
    final barcode = candidate.barcode?.trim();
    if (barcode != null && barcode.isNotEmpty) return null;

    if (!sourceAllowsNoBarcode(candidate.source)) {
      return ApproveStagedResult.invalidBarcode;
    }
    return _noBarcodeBlock(candidate, edits);
  }

  /// Hard-blocker check for no-barcode MANUAL approval.
  ///
  /// Only the absolute minimum identity fields can block manual approval:
  ///   • name — without a name the product cannot be catalogued
  ///   • source_url — without this (and no barcode) deduplication is impossible
  ///
  /// Missing brand, image, ingredients, and nutrition are WARNINGS only —
  /// they are shown as advisory chips in the admin UI but never prevent the
  /// admin from approving. Partial products are inserted with null for those
  /// fields and can be enriched later. Auto-approval strictness (score >= 100,
  /// no suspicious ingredients) lives in the import pipeline, not here.
  static ApproveStagedResult? _noBarcodeBlock(
    ProductCandidate candidate,
    StagingApprovalEdits edits,
  ) {
    final name = _resolve(edits.name) ?? _resolve(candidate.name);
    final sourceUrl = _resolve(candidate.sourceUrl);

    if (name == null) return ApproveStagedResult.insufficientData;
    if (sourceUrl == null) return ApproveStagedResult.missingSourceLink;
    return null;
  }

  /// Non-blocking warnings for recommended but not required fields.
  ///
  /// Returns a set of [ApproveStagedResult] values that correspond to missing
  /// recommended fields. These are informational only — [approvalBlockReason]
  /// returning null means the admin CAN approve regardless of these warnings.
  static Set<ApproveStagedResult> approvalWarnings(
    ProductCandidate candidate,
    StagingApprovalEdits edits,
  ) {
    final warnings = <ApproveStagedResult>{};
    final brand = _resolve(edits.brand) ?? _resolve(candidate.brand);
    final image =
        _resolve(candidate.imageFrontUrl) ??
        _resolve(candidate.imageFrontStoragePath);
    final ingredients =
        _resolve(edits.ingredientsText) ?? _resolve(candidate.ingredientsText);
    final hasNutrition = candidate.nutritionJson?.isNotEmpty ?? false;

    if (brand == null) warnings.add(ApproveStagedResult.missingBrand);
    if (image == null) warnings.add(ApproveStagedResult.missingImage);
    if (ingredients == null) {
      warnings.add(ApproveStagedResult.missingIngredients);
    }
    if (!hasNutrition) warnings.add(ApproveStagedResult.missingNutrition);
    return warnings;
  }

  /// Lightweight heuristic: does [text] look like a real ingredients list?
  ///
  /// Used for non-blocking admin warnings (and mirrored in the Python import
  /// pipeline where it gates auto-approval). Suspicious when: empty/too short,
  /// only a net-amount line, nutrition labels mixed in, or no separator with
  /// very few tokens.
  static bool isSuspiciousIngredients(String? text) {
    final t = text?.trim() ?? '';
    if (t.length < 20) return true;
    final lower = t.toLowerCase();
    if (lower.startsWith('net miktar')) return true;
    if (lower.contains('besin değer') || lower.contains('besin deger')) {
      return true; // nutrition table text leaked into ingredients
    }
    final tokens = t.split(RegExp(r'\s+'));
    if (!t.contains(',') && !t.contains(';') && tokens.length < 5) {
      return true;
    }
    return false;
  }

  // ── read ──────────────────────────────────────────────────────────────────

  /// Fetch staging rows awaiting review (`pending` or `needs_review`), newest
  /// first.
  Future<List<ProductCandidate>> fetchPendingStagedProducts({
    int limit = 100,
  }) async {
    final rows = await SupabaseService.client
        .from(_stagingTable)
        .select()
        .inFilter('status', _reviewableStatuses.toList())
        .order('created_at', ascending: false)
        .limit(limit);
    return (rows as List)
        .map((r) => ProductCandidate.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<ProductCandidate?> fetchStagedProductById(String stagingId) async {
    final row = await SupabaseService.client
        .from(_stagingTable)
        .select()
        .eq('id', stagingId)
        .maybeSingle();
    if (row == null) return null;
    return ProductCandidate.fromJson(row);
  }

  // ── approval ──────────────────────────────────────────────────────────────

  /// Approve a staged product: create or enrich a `products` row by barcode,
  /// then flip the staging row to `approved`.
  Future<ApproveStagedResult> approveStagedProduct(
    String stagingId, {
    StagingApprovalEdits edits = const StagingApprovalEdits(),
  }) async {
    final client = SupabaseService.client;
    _debugStagingApprovalLog('[Staging] approve started — id=$stagingId');

    final row = await client
        .from(_stagingTable)
        .select()
        .eq('id', stagingId)
        .maybeSingle();
    if (row == null) {
      _debugStagingApprovalLog('[Staging] not found');
      return ApproveStagedResult.notFound;
    }

    final candidate = ProductCandidate.fromJson(row);
    if (!_reviewableStatuses.contains(candidate.status)) {
      _debugStagingApprovalLog(
        '[Staging] already processed (status=${candidate.status})',
      );
      return ApproveStagedResult.alreadyProcessed;
    }

    // Auto-reject: products with neither ingredients nor nutrition have no
    // analyzable data and are never inserted into the products catalog.
    if (shouldAutoRejectForNoAnalysisData(candidate)) {
      _debugStagingApprovalLog(
        '[Staging] auto-reject — missing both ingredients and nutrition',
      );
      try {
        await client
            .from(_stagingTable)
            .update({
              'status': 'rejected',
              'admin_notes':
                  'İçindekiler ve besin değerleri eksik olduğu için otomatik reddedildi.',
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', stagingId);
      } on PostgrestException catch (e) {
        _debugStagingApprovalLog(
          '[Staging] auto-reject update failed — ${e.message}',
        );
      }
      return ApproveStagedResult.autoRejectedNoAnalysisData;
    }

    // Eligibility: barcode present → always OK; barcode absent → only for
    // eligible sources with complete, high-quality data (no fake barcode).
    final block = approvalBlockReason(candidate, edits);
    if (block != null) {
      _debugStagingApprovalLog('[Staging] approval blocked — reason=$block');
      return block;
    }

    final barcode = candidate.barcode?.trim();
    final hasBarcode = barcode != null && barcode.isNotEmpty;

    final ApproveStagedResult result;
    if (hasBarcode) {
      result = await _upsertProductByColumn(
        client,
        column: 'barcode',
        value: barcode,
        candidate: candidate,
        edits: edits,
      );
    } else {
      // No-barcode (web-discovered) product: dedupe by source_url so the same
      // page approved twice never creates a duplicate product.
      final sourceUrl = candidate.sourceUrl!.trim();
      result = await _upsertProductByColumn(
        client,
        column: 'source_url',
        value: sourceUrl,
        candidate: candidate,
        edits: edits,
      );
    }

    return _finalizeStagingApproval(
      client,
      stagingId,
      candidate,
      edits,
      result,
    );
  }

  /// Insert a new product, or enrich the existing one matched by [column]==
  /// [value] (filling only empty fields). Returns approved / updatedExisting.
  Future<ApproveStagedResult> _upsertProductByColumn(
    SupabaseClient client, {
    required String column,
    required String value,
    required ProductCandidate candidate,
    required StagingApprovalEdits edits,
  }) async {
    final existingRow = await client
        .from(_productsTable)
        .select()
        .eq(column, value)
        .maybeSingle();
    _debugStagingApprovalLog(
      '[Staging] products upsert started ($column=$value existing=${existingRow != null})',
    );

    if (existingRow == null) {
      _debugStagingApprovalLog('[Staging] no existing product — inserting');
      await client
          .from(_productsTable)
          .insert(buildProductInsertMap(candidate, edits));
      _debugStagingApprovalLog('[Staging] products upsert succeeded (insert)');
      return ApproveStagedResult.approved;
    }

    _debugStagingApprovalLog(
      '[Staging] existing product — filling missing fields only',
    );
    final existing = Product.fromJson(existingRow);
    final patch = buildProductEnrichPatch(existing, candidate, edits);
    if (patch.isNotEmpty) {
      _debugStagingApprovalLog(
        '[Staging] updating product keys=${patch.keys.toList()}',
      );
      await client.from(_productsTable).update(patch).eq(column, value);
      _debugStagingApprovalLog('[Staging] products upsert succeeded (update)');
    } else {
      _debugStagingApprovalLog(
        '[Staging] existing product already complete — no patch',
      );
    }
    return ApproveStagedResult.updatedExisting;
  }

  /// Flip the staging row to `approved` (never deleted, matched strictly by id)
  /// and confirm it landed. `category_suggestion` is preserved for audit only.
  Future<ApproveStagedResult> _finalizeStagingApproval(
    SupabaseClient client,
    String stagingId,
    ProductCandidate candidate,
    StagingApprovalEdits edits,
    ApproveStagedResult result,
  ) async {
    final categorySuggestion =
        _resolve(edits.categorySuggestion) ??
        _resolve(candidate.categorySuggestion);
    _debugStagingApprovalLog(
      '[Staging] updating product_staging id=$stagingId status=approved',
    );
    try {
      await client
          .from(_stagingTable)
          .update(
            buildStagingApprovalUpdateMap(
              adminNote: _resolve(edits.adminNote),
              categorySuggestion: categorySuggestion,
            ),
          )
          .eq('id', stagingId);

      final refreshedRow = await client
          .from(_stagingTable)
          .select('id,status')
          .eq('id', stagingId)
          .maybeSingle();

      final refreshedStatus = refreshedRow == null
          ? null
          : refreshedRow['status'] as String?;
      _debugStagingApprovalLog(
        '[Staging] staging row reloaded status=$refreshedStatus — result=$result',
      );

      if (refreshedStatus == 'approved') {
        return result;
      }

      _debugStagingApprovalLog(
        '[Staging] WARNING: staging row did not reach approved state '
        '(status=$refreshedStatus) — product saved but staging stays pending',
      );
      return ApproveStagedResult.productSavedStagingFailed;
    } on PostgrestException catch (e) {
      _debugStagingApprovalLog(
        '[Staging] PostgrestException on staging update — '
        'code=${e.code} message=${e.message} details=${e.details}',
      );
      // The product was already written; surface the staging-update failure
      // distinctly instead of pretending the whole approval succeeded.
      return ApproveStagedResult.productSavedStagingFailed;
    }
  }

  // ── pure mapping (DB-free, testable) ────────────────────────────────────────

  /// Build the `products` INSERT map for a new product from a staged candidate.
  ///
  /// Admin [edits] take precedence over staged values. The staged `nutrition_json`
  /// (NutritionData-compatible map) is encoded into `nutrition_text`.
  /// `category_suggestion` is intentionally excluded (no such products column).
  static Map<String, dynamic> buildProductInsertMap(
    ProductCandidate candidate,
    StagingApprovalEdits edits,
  ) {
    return {
      'barcode': candidate.barcode?.trim(),
      'name': _resolveName(candidate, edits),
      'verification_status': 'pending',
      'source': candidate.source,
      ...?_entry('brand', _resolveBrand(candidate, edits)),
      ...?_entry('image_url', _resolveImage(candidate)),
      ...?_entry('ingredients_text', _resolveIngredients(candidate, edits)),
      ...?_entry('nutrition_text', _resolveNutritionText(candidate)),
      ...?_entry('source_url', _resolve(candidate.sourceUrl)),
      ...?_entryList('category_tags', candidate.categoryTags),
      ...?_entryList('search_keywords', candidate.searchKeywords),
    };
  }

  /// Build a fill-missing PATCH for an existing product.
  ///
  /// Only null/empty existing fields are filled; existing non-null values are
  /// NEVER overwritten (verified/manual data is preserved).
  static Map<String, dynamic> buildProductEnrichPatch(
    Product existing,
    ProductCandidate candidate,
    StagingApprovalEdits edits,
  ) {
    final patch = <String, dynamic>{};

    if (existing.name.trim().isEmpty) {
      patch['name'] = _resolveName(candidate, edits);
    }
    if (existing.brand == null) {
      patch.addAll(_entry('brand', _resolveBrand(candidate, edits)) ?? {});
    }
    if (existing.imageUrl == null) {
      patch.addAll(_entry('image_url', _resolveImage(candidate)) ?? {});
    }
    if (existing.ingredientsText == null) {
      patch.addAll(
        _entry('ingredients_text', _resolveIngredients(candidate, edits)) ?? {},
      );
    }
    if (existing.nutritionText == null) {
      patch.addAll(
        _entry('nutrition_text', _resolveNutritionText(candidate)) ?? {},
      );
    }
    if (existing.source == null) {
      patch.addAll(_entry('source', candidate.source) ?? {});
    }
    if (existing.categoryTags == null || existing.categoryTags!.isEmpty) {
      patch.addAll(_entryList('category_tags', candidate.categoryTags) ?? {});
    }
    if (existing.searchKeywords == null || existing.searchKeywords!.isEmpty) {
      patch.addAll(
        _entryList('search_keywords', candidate.searchKeywords) ?? {},
      );
    }
    return patch;
  }

  static String _resolveName(ProductCandidate c, StagingApprovalEdits e) =>
      _resolve(e.name) ?? _resolve(c.name) ?? 'İsimsiz Ürün';

  static String? _resolveBrand(ProductCandidate c, StagingApprovalEdits e) =>
      _resolve(e.brand) ?? _resolve(c.brand);

  static String? _resolveIngredients(
    ProductCandidate c,
    StagingApprovalEdits e,
  ) => _resolve(e.ingredientsText) ?? _resolve(c.ingredientsText);

  static String? _resolveImage(ProductCandidate c) =>
      _resolve(c.imageFrontUrl) ?? _resolve(c.imageFrontStoragePath);

  /// nutrition_json (NutritionData-compatible map) → nutrition_text JSON string.
  static String? _resolveNutritionText(ProductCandidate c) =>
      c.nutrition != null ? jsonEncode(c.nutritionJson) : null;

  /// Build update payload for transitioning a staging row to approved.
  static Map<String, dynamic> buildStagingApprovalUpdateMap({
    String? adminNote,
    String? categorySuggestion,
    DateTime? now,
  }) {
    final effectiveNow = (now ?? DateTime.now()).toUtc().toIso8601String();
    return {
      'status': 'approved',
      'updated_at': effectiveNow,
      ...?_entry('admin_notes', _resolve(adminNote)),
      ...?_entry('category_suggestion', _resolve(categorySuggestion)),
    };
  }

  // ── rejection / needs review ───────────────────────────────────────────────

  Future<void> rejectStagedProduct(String stagingId, String reason) async {
    _debugStagingApprovalLog('[Staging] reject id=$stagingId');
    await SupabaseService.client
        .from(_stagingTable)
        .update({
          'status': 'rejected',
          ...?_entry('admin_notes', _resolve(reason)),
        })
        .eq('id', stagingId);
  }

  Future<void> markStagedProductNeedsReview(
    String stagingId,
    String note,
  ) async {
    _debugStagingApprovalLog('[Staging] needs_review id=$stagingId');
    await SupabaseService.client
        .from(_stagingTable)
        .update({
          'status': 'needs_review',
          ...?_entry('admin_notes', _resolve(note)),
        })
        .eq('id', stagingId);
  }

  // ── helpers ────────────────────────────────────────────────────────────────

  static String? _resolve(String? value) {
    final v = value?.trim();
    return (v != null && v.isNotEmpty) ? v : null;
  }

  static Map<String, dynamic>? _entry(String key, String? value) =>
      value != null ? {key: value} : null;

  static Map<String, dynamic>? _entryList(String key, List<String>? value) =>
      (value != null && value.isNotEmpty) ? {key: value} : null;
}

void _debugStagingApprovalLog(String message) {
  if (!kDebugMode) return;
  debugPrint(message);
}
