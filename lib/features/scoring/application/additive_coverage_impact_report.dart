import 'package:food_analyzer_app/features/product/models/ingredient.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/scoring/application/legacy_scoring_evidence_recovery.dart';
import 'package:food_analyzer_app/features/scoring/application/product_score_audit_evaluator.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_score_audit_snapshot.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_evidence_snapshot.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/etiketly_public_score_audit_gate.dart';

const additiveCoverageAffectedIngredientTerms = <String>[
  'e202',
  'potasyum sorbat',
  'potassium sorbate',
  'e471',
  'mono ve digliserit',
  'mono- ve digliserit',
  'mono and diglycerides',
  'e282',
  'kalsiyum propiyonat',
  'calcium propionate',
  'aroma verici',
  'aromalar',
  'flavouring',
  'flavoring',
];

String additiveCoveragePostgrestOrFilter() {
  final clauses = additiveCoverageAffectedIngredientTerms
      .map((term) => 'ingredients_text.ilike.*$term*')
      .join(',');
  return '($clauses)';
}

abstract interface class AdditiveCoverageImpactDataSource {
  Future<List<Ingredient>> fetchIngredientCatalogue();

  Future<List<Product>> fetchCandidateProductsAfter({
    required String? afterProductId,
    required int limit,
  });

  Future<Map<String, List<LegacyStagingScoringEvidence>>> fetchStagingMatches(
    Set<String> sourceUrls,
  );

  Future<EtiketlyScoreAuditSnapshot?> fetchMatchingSnapshot(
    EtiketlyScoreAuditSnapshot current,
  );
}

class AdditiveCoverageImpactOptions {
  const AdditiveCoverageImpactOptions({
    this.batchSize = 100,
    this.sampleLimit = 20,
  }) : assert(batchSize > 0 && batchSize <= 500),
       assert(sampleLimit >= 0);

  final int batchSize;
  final int sampleLimit;
}

class AdditiveCoverageImpactSample {
  const AdditiveCoverageImpactSample({
    required this.productId,
    required this.name,
    required this.brand,
    required this.finalScoreReady,
    required this.calculatedScore,
    required this.blockers,
  });

  final String productId;
  final String name;
  final String? brand;
  final bool finalScoreReady;
  final double? calculatedScore;
  final List<String> blockers;
}

class AdditiveCoverageImpactSummary {
  int candidateProducts = 0;
  int alreadyHasScoringEvidence = 0;
  int currentlyFinalScoreReady = 0;
  int needsScoringEvidenceWrite = 0;
  int alreadyCurrentV2Audit = 0;
  int needsV2Audit = 0;
  int stillNotReady = 0;
  int errors = 0;
  final Map<String, int> blockerReasons = {};
  final List<String> errorProductIds = [];
  final List<AdditiveCoverageImpactSample> samples = [];

  List<MapEntry<String, int>> topBlockerReasons([int limit = 15]) {
    final entries = blockerReasons.entries.toList()
      ..sort((left, right) {
        final byCount = right.value.compareTo(left.value);
        return byCount != 0 ? byCount : left.key.compareTo(right.key);
      });
    return entries.take(limit).toList(growable: false);
  }
}

class AdditiveCoverageCandidateEvaluation {
  const AdditiveCoverageCandidateEvaluation({
    required this.effectiveProduct,
    required this.finalScoreReady,
    required this.blockers,
    this.recoveredEvidence,
    this.currentSnapshot,
  });

  final Product effectiveProduct;
  final ScoringEvidenceSnapshot? recoveredEvidence;
  final bool finalScoreReady;
  final List<String> blockers;
  final EtiketlyScoreAuditSnapshot? currentSnapshot;

  bool get needsScoringEvidenceWrite => recoveredEvidence != null;
}

/// Shared targeted evaluator used by both the impact report and rollout.
class AdditiveCoverageCandidateEvaluator {
  const AdditiveCoverageCandidateEvaluator({
    this.recovery = const LegacyScoringEvidenceRecoveryService(),
    this.auditEvaluator = const ProductScoreAuditEvaluator(),
  });

  final LegacyScoringEvidenceRecoveryService recovery;
  final ProductScoreAuditEvaluator auditEvaluator;

  Future<AdditiveCoverageCandidateEvaluation> evaluate({
    required Product product,
    required List<LegacyStagingScoringEvidence> stagingMatches,
    required List<Ingredient> ingredientCatalogue,
  }) async {
    final blockers = <String>{};
    var effectiveProduct = product;
    ScoringEvidenceSnapshot? recoveredEvidence;
    if (product.scoringEvidence == null) {
      final recovered = await recovery.recover(
        product: product,
        stagingMatches: stagingMatches,
        ingredientCatalogue: ingredientCatalogue,
      );
      blockers.addAll(recovered.blockerReasons);
      recoveredEvidence = recovered.evidence;
      if (recoveredEvidence == null || !recovered.finalScoreReady) {
        return AdditiveCoverageCandidateEvaluation(
          effectiveProduct: product,
          recoveredEvidence: recoveredEvidence,
          finalScoreReady: false,
          blockers: List.unmodifiable(blockers.toList()..sort()),
        );
      }
      effectiveProduct = _withEvidence(product, recoveredEvidence);
    }

    final audit = await auditEvaluator.evaluate(
      effectiveProduct,
      ingredientCatalogue,
    );
    blockers.addAll(audit.blockerReasons);
    final current = audit.snapshot;
    final finalScoreReady = audit.finalScoreReady && current != null;
    return AdditiveCoverageCandidateEvaluation(
      effectiveProduct: effectiveProduct,
      recoveredEvidence: recoveredEvidence,
      finalScoreReady: finalScoreReady,
      blockers: List.unmodifiable(blockers.toList()..sort()),
      currentSnapshot: current,
    );
  }

  Product _withEvidence(Product product, ScoringEvidenceSnapshot evidence) {
    return Product(
      id: product.id,
      barcode: product.barcode,
      name: product.name,
      normalizedName: product.normalizedName,
      brand: product.brand,
      categoryId: product.categoryId,
      imageUrl: product.imageUrl,
      ingredientsText: product.ingredientsText,
      nutritionText: product.nutritionText,
      source: product.source,
      sourceUrl: product.sourceUrl,
      verificationStatus: product.verificationStatus,
      searchKeywords: product.searchKeywords,
      categoryTags: product.categoryTags,
      canonicalCategory: product.canonicalCategory,
      canonicalSubcategory: product.canonicalSubcategory,
      scoringEvidence: evidence,
      createdAt: product.createdAt,
      updatedAt: product.updatedAt,
    );
  }
}

class AdditiveCoverageImpactRunner {
  const AdditiveCoverageImpactRunner({
    required this.dataSource,
    this.candidateEvaluator = const AdditiveCoverageCandidateEvaluator(),
    this.auditGate = const EtiketlyPublicScoreAuditGate(),
  });

  final AdditiveCoverageImpactDataSource dataSource;
  final AdditiveCoverageCandidateEvaluator candidateEvaluator;
  final EtiketlyPublicScoreAuditGate auditGate;

  Future<AdditiveCoverageImpactSummary> run(
    AdditiveCoverageImpactOptions options,
  ) async {
    final summary = AdditiveCoverageImpactSummary();
    final catalogue = await dataSource.fetchIngredientCatalogue();
    final seenProductIds = <String>{};
    String? cursor;

    while (true) {
      final products = await dataSource.fetchCandidateProductsAfter(
        afterProductId: cursor,
        limit: options.batchSize,
      );
      if (products.isEmpty) break;
      cursor = products.last.id;

      final page = products
          .where((product) => seenProductIds.add(product.id))
          .toList(growable: false);
      final sourceUrls = page
          .where((product) => product.scoringEvidence == null)
          .map((product) => product.sourceUrl?.trim())
          .whereType<String>()
          .where((sourceUrl) => sourceUrl.isNotEmpty)
          .toSet();
      Map<String, List<LegacyStagingScoringEvidence>> staging = const {};
      Object? stagingError;
      if (sourceUrls.isNotEmpty) {
        try {
          staging = await dataSource.fetchStagingMatches(sourceUrls);
        } on Object catch (error) {
          stagingError = error;
        }
      }

      final productsToInspect = <Product>[];
      for (final product in page) {
        summary.candidateProducts++;
        if (product.scoringEvidence != null) {
          summary.alreadyHasScoringEvidence++;
        }
        if (product.scoringEvidence == null && stagingError != null) {
          _recordError(summary, product, options.sampleLimit);
          continue;
        }
        productsToInspect.add(product);
      }
      for (var offset = 0; offset < productsToInspect.length; offset += 8) {
        final end = (offset + 8).clamp(0, productsToInspect.length);
        await Future.wait(
          productsToInspect.sublist(offset, end).map((product) {
            return _inspectProduct(
              product: product,
              stagingMatches: staging[product.sourceUrl?.trim()] ?? const [],
              catalogue: catalogue,
              options: options,
              summary: summary,
            );
          }),
        );
      }
    }
    return summary;
  }

  Future<void> _inspectProduct({
    required Product product,
    required List<LegacyStagingScoringEvidence> stagingMatches,
    required List<Ingredient> catalogue,
    required AdditiveCoverageImpactOptions options,
    required AdditiveCoverageImpactSummary summary,
  }) async {
    try {
      final evaluation = await candidateEvaluator.evaluate(
        product: product,
        stagingMatches: stagingMatches,
        ingredientCatalogue: catalogue,
      );
      final current = evaluation.currentSnapshot;
      if (!evaluation.finalScoreReady || current == null) {
        _recordNotReady(
          summary,
          product,
          evaluation.blockers.toSet(),
          options.sampleLimit,
        );
        return;
      }

      summary.currentlyFinalScoreReady++;
      if (evaluation.needsScoringEvidenceWrite) {
        summary.needsScoringEvidenceWrite++;
      }

      late final EtiketlyScoreAuditSnapshot? trusted;
      try {
        trusted = await dataSource.fetchMatchingSnapshot(current);
      } on Object {
        summary.errors++;
        summary.errorProductIds.add(product.id);
        _addSample(
          summary,
          product,
          finalScoreReady: true,
          calculatedScore: current.finalScore,
          blockers: const ['audit_lookup_error'],
          limit: options.sampleLimit,
        );
        return;
      }
      final decision = auditGate.evaluate(current: current, trusted: trusted);
      if (decision.status == PublicScoreAuditStatus.matching) {
        summary.alreadyCurrentV2Audit++;
      } else {
        summary.needsV2Audit++;
      }
      _addSample(
        summary,
        product,
        finalScoreReady: true,
        calculatedScore: current.finalScore,
        blockers: const [],
        limit: options.sampleLimit,
      );
    } on Object {
      _recordError(summary, product, options.sampleLimit);
    }
  }

  void _recordNotReady(
    AdditiveCoverageImpactSummary summary,
    Product product,
    Set<String> blockers,
    int sampleLimit,
  ) {
    summary.stillNotReady++;
    final ordered = blockers.toList()..sort();
    for (final blocker in ordered) {
      summary.blockerReasons.update(
        blocker,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    _addSample(
      summary,
      product,
      finalScoreReady: false,
      calculatedScore: null,
      blockers: ordered,
      limit: sampleLimit,
    );
  }

  void _recordError(
    AdditiveCoverageImpactSummary summary,
    Product product,
    int sampleLimit,
  ) {
    summary.errors++;
    summary.errorProductIds.add(product.id);
    _addSample(
      summary,
      product,
      finalScoreReady: false,
      calculatedScore: null,
      blockers: const ['inspection_error'],
      limit: sampleLimit,
    );
  }

  void _addSample(
    AdditiveCoverageImpactSummary summary,
    Product product, {
    required bool finalScoreReady,
    required double? calculatedScore,
    required List<String> blockers,
    required int limit,
  }) {
    if (summary.samples.length >= limit) return;
    summary.samples.add(
      AdditiveCoverageImpactSample(
        productId: product.id,
        name: product.name,
        brand: product.brand,
        finalScoreReady: finalScoreReady,
        calculatedScore: calculatedScore,
        blockers: List.unmodifiable(blockers),
      ),
    );
  }
}

class AdditiveCoverageImpactFormatter {
  const AdditiveCoverageImpactFormatter();

  String format(AdditiveCoverageImpactSummary summary) {
    final lines = <String>[
      '[SUMMARY]',
      'candidate_products=${summary.candidateProducts}',
      'already_has_scoring_evidence=${summary.alreadyHasScoringEvidence}',
      'currently_final_score_ready=${summary.currentlyFinalScoreReady}',
      'needs_scoring_evidence_write=${summary.needsScoringEvidenceWrite}',
      'already_current_v2_audit=${summary.alreadyCurrentV2Audit}',
      'needs_v2_audit=${summary.needsV2Audit}',
      'still_not_ready=${summary.stillNotReady}',
      'errors=${summary.errors}',
      'error_product_ids=${summary.errorProductIds.isEmpty ? 'none' : summary.errorProductIds.join(',')}',
      '',
      '[TOP REMAINING BLOCKERS]',
    ];
    final blockers = summary.topBlockerReasons();
    if (blockers.isEmpty) {
      lines.add('none');
    } else {
      for (final blocker in blockers) {
        lines.add('${blocker.key}=${blocker.value}');
      }
    }
    lines
      ..add('')
      ..add('[SAMPLES]')
      ..add(
        'product_id | name | brand | final_score_ready | calculated_score | blockers',
      );
    for (final sample in summary.samples) {
      lines.add(
        '${_safe(sample.productId)} | ${_safe(sample.name)} | '
        '${_safe(sample.brand ?? '-')} | ${sample.finalScoreReady} | '
        '${_score(sample.calculatedScore)} | '
        '${sample.blockers.isEmpty ? 'none' : sample.blockers.join(',')}',
      );
    }
    return lines.join('\n');
  }

  String _safe(String value) =>
      value.trim().replaceAll(RegExp(r'[\r\n\t]+'), ' ').replaceAll('|', '/');

  String _score(double? value) {
    if (value == null) return '-';
    return value
        .toStringAsFixed(6)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }
}
