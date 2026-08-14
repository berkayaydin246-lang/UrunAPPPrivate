import 'dart:math' as math;

import 'package:food_analyzer_app/features/product/models/ingredient.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/scoring/application/legacy_scoring_evidence_recovery.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_evidence_snapshot.dart';

abstract interface class LegacyScoringEvidenceBackfillDataSource {
  Future<List<Ingredient>> fetchIngredientCatalogue();

  Future<List<Product>> fetchProductsAfter({
    required String? afterProductId,
    required int limit,
  });

  Future<Product?> fetchProductById(String productId);

  Future<Map<String, List<LegacyStagingScoringEvidence>>> fetchStagingMatches(
    Set<String> sourceUrls,
  );

  /// Returns true only when this call changed NULL evidence to [evidence].
  Future<bool> writeScoringEvidence(
    String productId,
    ScoringEvidenceSnapshot evidence,
  );
}

class LegacyScoringEvidenceBackfillOptions {
  const LegacyScoringEvidenceBackfillOptions({
    required this.dryRun,
    this.onlyFinalScoreReady = false,
    this.batchSize = 50,
    this.startAfterProductId,
    this.maxProducts,
  }) : assert(batchSize > 0 && batchSize <= 100),
       assert(maxProducts == null || maxProducts > 0);

  final bool dryRun;
  final bool onlyFinalScoreReady;
  final int batchSize;
  final String? startAfterProductId;
  final int? maxProducts;
}

class LegacyScoringEvidenceBackfillSummary {
  LegacyScoringEvidenceBackfillSummary({
    required this.dryRun,
    required this.onlyFinalScoreReady,
    required this.safeResumeCursor,
  });

  final bool dryRun;
  final bool onlyFinalScoreReady;
  int totalProductsExamined = 0;
  int stagingMatch = 0;
  int explicitPer100 = 0;
  int basisReady = 0;
  int nutritionComplete = 0;
  int classificationReady = 0;
  int fvlReady = 0;
  int nnsReady = 0;
  int additiveReady = 0;
  int finalScoreReady = 0;
  int existingScoringEvidence = 0;
  int wouldWrite = 0;
  int written = 0;
  int existingAtWrite = 0;
  int notReady = 0;
  int errors = 0;
  int batchErrors = 0;
  int batchesFetched = 0;
  bool completed = false;
  bool reachedLimit = false;
  bool halted = false;
  String? lastExaminedCursor;
  String? safeResumeCursor;
  final Map<String, int> blockerReasons = {};
  final List<String> failedProductIds = [];

  List<MapEntry<String, int>> topBlockerReasons([int limit = 15]) {
    final entries = blockerReasons.entries.toList()
      ..sort((left, right) {
        final byCount = right.value.compareTo(left.value);
        return byCount != 0 ? byCount : left.key.compareTo(right.key);
      });
    return entries.take(limit).toList(growable: false);
  }
}

typedef LegacyScoringEvidenceBackfillProgress =
    void Function(LegacyScoringEvidenceBackfillSummary summary);

class LegacyScoringEvidenceBackfillRunner {
  const LegacyScoringEvidenceBackfillRunner({
    required this.dataSource,
    this.recovery = const LegacyScoringEvidenceRecoveryService(),
  });

  final LegacyScoringEvidenceBackfillDataSource dataSource;
  final LegacyScoringEvidenceRecoveryService recovery;

  Future<LegacyScoringEvidenceBackfillSummary> run(
    LegacyScoringEvidenceBackfillOptions options, {
    LegacyScoringEvidenceBackfillProgress? onBatchComplete,
  }) async {
    final summary = LegacyScoringEvidenceBackfillSummary(
      dryRun: options.dryRun,
      onlyFinalScoreReady: options.onlyFinalScoreReady,
      safeResumeCursor: options.startAfterProductId,
    );
    late final List<Ingredient> catalogue;
    try {
      catalogue = await dataSource.fetchIngredientCatalogue();
    } catch (_) {
      summary.errors++;
      summary.batchErrors++;
      summary.halted = true;
      return summary;
    }

    var cursor = options.startAfterProductId;
    var hasUnresolvedError = false;
    while (true) {
      final remaining = options.maxProducts == null
          ? options.batchSize
          : options.maxProducts! - summary.totalProductsExamined;
      if (remaining <= 0) {
        summary.reachedLimit = true;
        break;
      }
      final pageLimit = math.min(options.batchSize, remaining);
      late final List<Product> products;
      late final Map<String, List<LegacyStagingScoringEvidence>> staging;
      try {
        products = await dataSource.fetchProductsAfter(
          afterProductId: cursor,
          limit: pageLimit,
        );
        summary.batchesFetched++;
        if (products.isEmpty) {
          summary.completed = true;
          break;
        }
        staging = await dataSource.fetchStagingMatches(
          products
              .map((product) => product.sourceUrl?.trim())
              .whereType<String>()
              .where((sourceUrl) => sourceUrl.isNotEmpty)
              .toSet(),
        );
      } catch (_) {
        summary.errors++;
        summary.batchErrors++;
        summary.halted = true;
        break;
      }

      for (final product in products) {
        summary.totalProductsExamined++;
        summary.lastExaminedCursor = product.id;
        final succeeded = await _processProduct(
          product,
          staging[product.sourceUrl?.trim()] ?? const [],
          catalogue,
          options,
          summary,
        );
        if (!succeeded) hasUnresolvedError = true;
        if (!hasUnresolvedError) summary.safeResumeCursor = product.id;
        cursor = product.id;
      }
      onBatchComplete?.call(summary);
    }
    return summary;
  }

  Future<bool> _processProduct(
    Product product,
    List<LegacyStagingScoringEvidence> stagingMatches,
    List<Ingredient> catalogue,
    LegacyScoringEvidenceBackfillOptions options,
    LegacyScoringEvidenceBackfillSummary summary,
  ) async {
    if (product.scoringEvidence != null) {
      summary.existingScoringEvidence++;
      _countBlocker(summary, 'existing_scoring_evidence');
      return true;
    }

    late final LegacyScoringEvidenceRecoveryResult result;
    try {
      result = await recovery.recover(
        product: product,
        stagingMatches: stagingMatches,
        ingredientCatalogue: catalogue,
      );
    } catch (_) {
      _recordError(summary, product.id);
      return false;
    }

    if (result.stagingMatch) summary.stagingMatch++;
    if (result.explicitPer100) summary.explicitPer100++;
    if (result.basisReady) summary.basisReady++;
    if (result.nutritionComplete) summary.nutritionComplete++;
    if (result.classificationReady) summary.classificationReady++;
    if (result.fvlReady) summary.fvlReady++;
    if (result.nnsReady) summary.nnsReady++;
    if (result.additiveReady) summary.additiveReady++;
    if (result.finalScoreReady) {
      summary.finalScoreReady++;
    } else {
      summary.notReady++;
    }
    for (final blocker in result.blockerReasons) {
      _countBlocker(summary, blocker);
    }

    final evidence = result.evidence;
    if (evidence == null) return true;
    if (options.onlyFinalScoreReady && !result.finalScoreReady) return true;
    summary.wouldWrite++;
    if (options.dryRun) return true;
    try {
      final changed = await dataSource.writeScoringEvidence(
        product.id,
        evidence,
      );
      if (changed) {
        summary.written++;
      } else {
        summary.existingAtWrite++;
      }
      return true;
    } catch (_) {
      _recordError(summary, product.id);
      return false;
    }
  }

  void _countBlocker(
    LegacyScoringEvidenceBackfillSummary summary,
    String blocker,
  ) {
    summary.blockerReasons.update(
      blocker,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
  }

  void _recordError(
    LegacyScoringEvidenceBackfillSummary summary,
    String productId,
  ) {
    summary.errors++;
    summary.failedProductIds.add(productId);
  }
}

class LegacyScoringEvidenceSampleInspection {
  const LegacyScoringEvidenceSampleInspection({
    required this.productId,
    required this.barcode,
    required this.hasExistingEvidence,
    required this.stagingMatch,
    required this.explicitPer100,
    required this.basisReady,
    required this.finalScoreReady,
    required this.wouldWrite,
    required this.blockerReasons,
    this.error,
  });

  final String productId;
  final String? barcode;
  final bool hasExistingEvidence;
  final bool stagingMatch;
  final bool explicitPer100;
  final bool basisReady;
  final bool finalScoreReady;
  final bool wouldWrite;
  final List<String> blockerReasons;
  final String? error;
}

class LegacyScoringEvidenceSampleInspector {
  const LegacyScoringEvidenceSampleInspector({
    required this.dataSource,
    this.recovery = const LegacyScoringEvidenceRecoveryService(),
  });

  final LegacyScoringEvidenceBackfillDataSource dataSource;
  final LegacyScoringEvidenceRecoveryService recovery;

  Future<List<LegacyScoringEvidenceSampleInspection>> inspect(
    Iterable<String> productIds,
  ) async {
    final catalogue = await dataSource.fetchIngredientCatalogue();
    final results = <LegacyScoringEvidenceSampleInspection>[];
    for (final productId in productIds) {
      try {
        final product = await dataSource.fetchProductById(productId);
        if (product == null) {
          results.add(_error(productId, 'product_not_found'));
          continue;
        }
        if (product.scoringEvidence != null) {
          results.add(
            LegacyScoringEvidenceSampleInspection(
              productId: product.id,
              barcode: product.barcode,
              hasExistingEvidence: true,
              stagingMatch: false,
              explicitPer100: false,
              basisReady: false,
              finalScoreReady: false,
              wouldWrite: false,
              blockerReasons: const ['existing_scoring_evidence'],
            ),
          );
          continue;
        }
        final sourceUrl = product.sourceUrl?.trim();
        final staging = await dataSource.fetchStagingMatches({
          if (sourceUrl != null && sourceUrl.isNotEmpty) sourceUrl,
        });
        final result = await recovery.recover(
          product: product,
          stagingMatches: staging[sourceUrl] ?? const [],
          ingredientCatalogue: catalogue,
        );
        results.add(
          LegacyScoringEvidenceSampleInspection(
            productId: product.id,
            barcode: product.barcode,
            hasExistingEvidence: false,
            stagingMatch: result.stagingMatch,
            explicitPer100: result.explicitPer100,
            basisReady: result.basisReady,
            finalScoreReady: result.finalScoreReady,
            wouldWrite: result.canWrite,
            blockerReasons: result.blockerReasons,
          ),
        );
      } catch (_) {
        results.add(_error(productId, 'inspection_error'));
      }
    }
    return results;
  }

  LegacyScoringEvidenceSampleInspection _error(
    String productId,
    String reason,
  ) {
    return LegacyScoringEvidenceSampleInspection(
      productId: productId,
      barcode: null,
      hasExistingEvidence: false,
      stagingMatch: false,
      explicitPer100: false,
      basisReady: false,
      finalScoreReady: false,
      wouldWrite: false,
      blockerReasons: const [],
      error: reason,
    );
  }
}

class LegacyScoringEvidenceBackfillFormatter {
  const LegacyScoringEvidenceBackfillFormatter();

  String formatSummary(LegacyScoringEvidenceBackfillSummary summary) {
    final lines = <String>[
      '[summary]',
      'mode=${summary.dryRun ? 'dry_run' : 'apply'}',
      'only_final_score_ready=${summary.onlyFinalScoreReady}',
      'total_products_examined=${summary.totalProductsExamined}',
      'staging_match=${summary.stagingMatch}',
      'explicit_per100=${summary.explicitPer100}',
      'basis_ready=${summary.basisReady}',
      'nutrition_complete=${summary.nutritionComplete}',
      'classification_ready=${summary.classificationReady}',
      'fvl_ready=${summary.fvlReady}',
      'nns_ready=${summary.nnsReady}',
      'additive_ready=${summary.additiveReady}',
      'final_score_ready=${summary.finalScoreReady}',
      'existing_scoring_evidence=${summary.existingScoringEvidence}',
      'would_write=${summary.wouldWrite}',
      'written=${summary.written}',
      'existing_at_write=${summary.existingAtWrite}',
      'not_ready=${summary.notReady}',
      'errors=${summary.errors}',
      'batch_errors=${summary.batchErrors}',
      'completed=${summary.completed}',
      'reached_limit=${summary.reachedLimit}',
      'halted=${summary.halted}',
      'last_examined_cursor=${summary.lastExaminedCursor ?? '-'}',
      'safe_resume_cursor=${summary.safeResumeCursor ?? '-'}',
      '[top_blocker_reasons]',
      ...summary.topBlockerReasons().map(
        (entry) => '${entry.key}=${entry.value}',
      ),
    ];
    if (summary.failedProductIds.isNotEmpty) {
      lines.add('[failed_product_ids]');
      lines.addAll(summary.failedProductIds);
    }
    return lines.join('\n');
  }

  String formatSample(LegacyScoringEvidenceSampleInspection result) {
    return [
      '[sample]',
      'product_id=${result.productId}',
      'barcode=${result.barcode ?? '-'}',
      'has_existing_evidence=${result.hasExistingEvidence}',
      'staging_match=${result.stagingMatch}',
      'explicit_per100=${result.explicitPer100}',
      'basis_ready=${result.basisReady}',
      'final_score_ready=${result.finalScoreReady}',
      'would_write=${result.wouldWrite}',
      'blockers=${result.blockerReasons.join(',')}',
      if (result.error != null) 'error=${result.error}',
    ].join('\n');
  }
}
