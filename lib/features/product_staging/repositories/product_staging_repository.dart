import 'package:food_analyzer_app/core/services/supabase_service.dart';
import 'package:food_analyzer_app/features/product_staging/models/product_candidate.dart';
import 'package:food_analyzer_app/features/product_staging/services/product_candidate_quality_evaluator.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/scoring_evidence_merger.dart';

/// Repository for the `product_staging` table.
///
/// All writes recompute quality_score / missing_fields / status via
/// [ProductCandidateQualityEvaluator] before hitting the database. This
/// repository ONLY touches `product_staging` — it never writes to `products`.
class ProductStagingRepository {
  final ProductCandidateQualityEvaluator _evaluator;

  ProductStagingRepository({ProductCandidateQualityEvaluator? evaluator})
    : _evaluator = evaluator ?? const ProductCandidateQualityEvaluator();

  static const String _table = 'product_staging';

  /// Insert a brand-new staging candidate (no dedupe check).
  ///
  /// Quality fields are computed before insert. Returns the inserted row as a
  /// [ProductCandidate].
  Future<ProductCandidate> insertCandidate(ProductCandidate candidate) async {
    final scored = _withQuality(candidate);
    final inserted = await SupabaseService.client
        .from(_table)
        .insert(scored.toStagingInsertMap())
        .select()
        .single();
    return ProductCandidate.fromJson(inserted);
  }

  /// Insert or merge a candidate, deduped on (barcode, source).
  ///
  /// If a row with the same barcode + source already exists, only currently
  /// null/empty fields are filled from [candidate] (existing non-null fields are
  /// never overwritten). raw_source_payload and updated_at are always refreshed,
  /// and quality is recomputed after the merge.
  ///
  /// When [candidate.barcode] is null/empty, dedupe is impossible, so a plain
  /// insert is performed.
  Future<ProductCandidate> upsertCandidate(ProductCandidate candidate) async {
    final barcode = candidate.barcode?.trim();
    if (barcode == null || barcode.isEmpty) {
      return insertCandidate(candidate);
    }

    final existingRow = await SupabaseService.client
        .from(_table)
        .select()
        .eq('barcode', barcode)
        .eq('source', candidate.source)
        .limit(1)
        .maybeSingle();

    if (existingRow == null) {
      return insertCandidate(candidate);
    }

    final existing = ProductCandidate.fromJson(existingRow);
    final merged = _withQuality(mergeFillMissing(existing, candidate));

    final updateMap = merged.toStagingInsertMap()
      // Always refresh raw payload even if existing already had one.
      ..['raw_source_payload'] =
          candidate.rawSourcePayload ?? existing.rawSourcePayload;

    final updated = await SupabaseService.client
        .from(_table)
        .update(updateMap)
        .eq('id', existing.id as String)
        .select()
        .single();

    return ProductCandidate.fromJson(updated);
  }

  /// Fetch staging candidates, newest first.
  Future<List<ProductCandidate>> fetchPending({
    String? status,
    String? source,
    int limit = 50,
  }) async {
    var query = SupabaseService.client.from(_table).select();
    if (status != null) query = query.eq('status', status);
    if (source != null) query = query.eq('source', source);

    final rows = await query.order('created_at', ascending: false).limit(limit);

    return (rows as List)
        .map((r) => ProductCandidate.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Update only the review status (and optional admin notes) of a candidate.
  Future<void> updateStatus(
    String id,
    String status, {
    String? adminNotes,
  }) async {
    final patch = <String, dynamic>{'status': status};
    if (adminNotes != null && adminNotes.trim().isNotEmpty) {
      patch['admin_notes'] = adminNotes.trim();
    }
    await SupabaseService.client.from(_table).update(patch).eq('id', id);
  }

  /// Fetch a single candidate by id, or null when not found.
  Future<ProductCandidate?> fetchById(String id) async {
    final row = await SupabaseService.client
        .from(_table)
        .select()
        .eq('id', id)
        .maybeSingle();
    if (row == null) return null;
    return ProductCandidate.fromJson(row);
  }

  /// Recompute and attach quality_score / missing_fields / status.
  ///
  /// Products with neither ingredients nor nutrition have no analyzable data
  /// and are inserted directly with status='rejected' so they never appear
  /// in the admin review queue.
  ProductCandidate _withQuality(ProductCandidate candidate) {
    final result = _evaluator.evaluate(candidate);
    final status = candidate.hasNoAnalysisData
        ? 'rejected'
        : result.suggestedStatus;
    return candidate.copyWith(
      qualityScore: result.qualityScore,
      missingFields: result.missingFields,
      status: status,
    );
  }

  /// Merge rule: fill only fields that are null/empty in [existing] using
  /// values from [incoming]. Existing non-null/non-empty fields are preserved.
  ///
  /// Pure and DB-free so it can be unit-tested directly. Status/quality are not
  /// set here — the caller recomputes them via [_withQuality].
  static ProductCandidate mergeFillMissing(
    ProductCandidate existing,
    ProductCandidate incoming,
  ) {
    final evidenceMerge = const ScoringEvidenceMerger().merge(
      existing.scoringEvidence,
      incoming.scoringEvidence,
    );
    return existing.copyWith(
      barcode: _fillString(existing.barcode, incoming.barcode),
      name: _fillString(existing.name, incoming.name),
      brand: _fillString(existing.brand, incoming.brand),
      categorySuggestion: _fillString(
        existing.categorySuggestion,
        incoming.categorySuggestion,
      ),
      categoryTags: _fillList(existing.categoryTags, incoming.categoryTags),
      searchKeywords: _fillList(
        existing.searchKeywords,
        incoming.searchKeywords,
      ),
      imageFrontUrl: _fillString(
        existing.imageFrontUrl,
        incoming.imageFrontUrl,
      ),
      imageFrontStoragePath: _fillString(
        existing.imageFrontStoragePath,
        incoming.imageFrontStoragePath,
      ),
      imageIngredientsUrl: _fillString(
        existing.imageIngredientsUrl,
        incoming.imageIngredientsUrl,
      ),
      imageNutritionUrl: _fillString(
        existing.imageNutritionUrl,
        incoming.imageNutritionUrl,
      ),
      ingredientsText: _fillString(
        existing.ingredientsText,
        incoming.ingredientsText,
      ),
      nutritionJson: _fillMap(existing.nutritionJson, incoming.nutritionJson),
      scoringEvidence: evidenceMerge.evidence,
      sourceUrl: _fillString(existing.sourceUrl, incoming.sourceUrl),
      // raw_source_payload is always refreshed by the caller.
      rawSourcePayload: incoming.rawSourcePayload ?? existing.rawSourcePayload,
      nameSource: _fillString(existing.nameSource, incoming.nameSource),
      brandSource: _fillString(existing.brandSource, incoming.brandSource),
      imageSource: _fillString(existing.imageSource, incoming.imageSource),
      ingredientsSource: _fillString(
        existing.ingredientsSource,
        incoming.ingredientsSource,
      ),
      nutritionSource: _fillString(
        existing.nutritionSource,
        incoming.nutritionSource,
      ),
      categorySource: _fillString(
        existing.categorySource,
        incoming.categorySource,
      ),
      adminNotes: _fillString(existing.adminNotes, incoming.adminNotes),
    );
  }

  static String? _fillString(String? existing, String? incoming) {
    if (existing != null && existing.trim().isNotEmpty) return existing;
    return incoming;
  }

  static List<String>? _fillList(
    List<String>? existing,
    List<String>? incoming,
  ) {
    if (existing != null && existing.isNotEmpty) return existing;
    return incoming;
  }

  static Map<String, dynamic>? _fillMap(
    Map<String, dynamic>? existing,
    Map<String, dynamic>? incoming,
  ) {
    if (existing != null && existing.isNotEmpty) return existing;
    return incoming;
  }
}
