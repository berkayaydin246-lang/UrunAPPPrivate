import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/product/models/ingredient.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/scoring/application/additive_coverage_impact_report.dart';
import 'package:food_analyzer_app/features/scoring/application/additive_coverage_rollout.dart';
import 'package:food_analyzer_app/features/scoring/application/legacy_scoring_evidence_recovery.dart';
import 'package:food_analyzer_app/features/scoring/application/product_score_audit_backfill.dart';
import 'package:food_analyzer_app/features/scoring/application/product_score_audit_evaluator.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_score_audit_snapshot.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_evidence_snapshot.dart';

import '../../tool/additive_coverage_rollout.dart' as rollout_cli;
import 'scoring_test_fixtures.dart';
import 'support/score_audit_test_support.dart';

void main() {
  test(
    'dry run considers only affected deduplicated candidates and writes nothing',
    () async {
      final ready = _legacyProduct(
        id: '0001',
        ingredientsText: 'un, aroma vericiler',
      );
      final blocked = _legacyProduct(
        id: '0002',
        ingredientsText: 'un, E202, E9999',
      );
      final unrelated = _legacyProduct(
        id: '0003',
        ingredientsText: 'un, şeker, tuz',
      );
      final source = _MemoryRolloutDataSource(
        products: [ready, ready, blocked, unrelated],
      );

      final summary = await AdditiveCoverageRolloutRunner(
        dataSource: source,
      ).run(const AdditiveCoverageRolloutOptions(dryRun: true));

      expect(summary.candidateProductsExamined, 2);
      expect(summary.finalScoreReady, 1);
      expect(summary.evidenceWouldWrite, 1);
      expect(summary.evidenceWritten, 0);
      expect(summary.auditWouldInsert, 1);
      expect(summary.auditInserted, 0);
      expect(summary.notReady, 1);
      expect(source.evidenceWriteAttempts, 0);
      expect(source.auditInsertAttempts, 0);
      expect(source.candidateRequests, isNotEmpty);
    },
  );

  test(
    'apply writes ready null evidence and inserts its missing audit',
    () async {
      final product = _legacyProduct(
        id: '0010',
        ingredientsText: 'un, aroma vericiler',
      );
      final source = _MemoryRolloutDataSource(products: [product]);
      final expectedRecovery =
          await const LegacyScoringEvidenceRecoveryService().recover(
            product: product,
            stagingMatches: [_staging(product)],
            ingredientCatalogue: const [],
          );

      final summary = await AdditiveCoverageRolloutRunner(dataSource: source)
          .run(
            const AdditiveCoverageRolloutOptions(dryRun: false, maxProducts: 1),
          );

      expect(summary.finalScoreReady, 1);
      expect(summary.evidenceWouldWrite, 1);
      expect(summary.evidenceWritten, 1);
      expect(summary.auditWouldInsert, 1);
      expect(summary.auditInserted, 1);
      expect(source.products.single.scoringEvidence, isNotNull);
      expect(
        source.lastPersistedEvidence?.toJson(),
        expectedRecovery.evidence?.toJson(),
      );
      expect(source.evidenceWriteAttempts, 1);
      expect(source.auditInsertAttempts, 1);
    },
  );

  test('non-ready products receive zero writes in apply mode', () async {
    final product = _legacyProduct(
      id: '0020',
      ingredientsText: 'un, E202, E9999',
    );
    final source = _MemoryRolloutDataSource(products: [product]);

    final summary = await AdditiveCoverageRolloutRunner(
      dataSource: source,
    ).run(const AdditiveCoverageRolloutOptions(dryRun: false, maxProducts: 1));

    expect(summary.finalScoreReady, 0);
    expect(summary.notReady, 1);
    expect(summary.evidenceWritten, 0);
    expect(summary.auditInserted, 0);
    expect(source.evidenceWriteAttempts, 0);
    expect(source.auditInsertAttempts, 0);
  });

  test('existing evidence and current audit are never duplicated', () async {
    final product = auditProductFromInput(
      completeInput(),
      id: '0030',
      ingredientsText: 'aroma vericiler',
    );
    final current = (await const ProductScoreAuditEvaluator().evaluate(
      product,
      const [],
    )).snapshot!;
    final source = _MemoryRolloutDataSource(
      products: [product],
      audits: {product.id: current},
    );

    final summary = await AdditiveCoverageRolloutRunner(
      dataSource: source,
    ).run(const AdditiveCoverageRolloutOptions(dryRun: false, maxProducts: 1));

    expect(summary.existingScoringEvidence, 1);
    expect(summary.alreadyCurrentV2Audit, 1);
    expect(summary.evidenceWouldWrite, 0);
    expect(summary.auditWouldInsert, 0);
    expect(source.evidenceWriteAttempts, 0);
    expect(source.auditInsertAttempts, 0);
  });

  test('a second apply run is idempotent', () async {
    final product = _legacyProduct(
      id: '0040',
      ingredientsText: 'un, aroma vericiler',
    );
    final source = _MemoryRolloutDataSource(products: [product]);
    const options = AdditiveCoverageRolloutOptions(
      dryRun: false,
      maxProducts: 1,
    );
    final runner = AdditiveCoverageRolloutRunner(dataSource: source);

    final first = await runner.run(options);
    final second = await runner.run(options);

    expect(first.evidenceWritten, 1);
    expect(first.auditInserted, 1);
    expect(second.existingScoringEvidence, 1);
    expect(second.evidenceWouldWrite, 0);
    expect(second.evidenceWritten, 0);
    expect(second.alreadyCurrentV2Audit, 1);
    expect(second.auditWouldInsert, 0);
    expect(second.auditInserted, 0);
    expect(source.evidenceWriteAttempts, 1);
    expect(source.auditInsertAttempts, 1);
  });

  test(
    'known validation failures remain errors and receive no writes',
    () async {
      final products = [
        _legacyProduct(
          id: '91da5b3d-681d-4f3e-b240-e83b6bafc26e',
          ingredientsText: 'aroma vericiler',
        ),
        _legacyProduct(
          id: 'eb29a242-1ad1-4d2c-b4b2-2d7bdbd1000d',
          ingredientsText: 'aroma vericiler',
        ),
      ];
      final source = _MemoryRolloutDataSource(products: products);

      final summary =
          await AdditiveCoverageRolloutRunner(
            dataSource: source,
            candidateEvaluator: const _KnownValidationErrorEvaluator(),
          ).run(
            const AdditiveCoverageRolloutOptions(dryRun: false, maxProducts: 2),
          );

      expect(summary.errors, 2);
      expect(
        summary.failedProductIds,
        containsAll(products.map((item) => item.id)),
      );
      expect(source.evidenceWriteAttempts, 0);
      expect(source.auditInsertAttempts, 0);
    },
  );

  test('apply safety flags and max-products are mandatory', () {
    expect(
      () => rollout_cli.AdditiveCoverageRolloutCliOptions.parse(const []),
      throwsFormatException,
    );
    expect(
      () => rollout_cli.AdditiveCoverageRolloutCliOptions.parse(const [
        '--apply',
      ]),
      throwsFormatException,
    );
    expect(
      () => rollout_cli.AdditiveCoverageRolloutCliOptions.parse(const [
        '--apply',
        '--confirm-targeted-rollout',
      ]),
      throwsFormatException,
    );
    final apply = rollout_cli.AdditiveCoverageRolloutCliOptions.parse(const [
      '--apply',
      '--confirm-targeted-rollout',
      '--max-products',
      '25',
    ]);
    final dryRun = rollout_cli.AdditiveCoverageRolloutCliOptions.parse(const [
      '--dry-run',
    ]);

    expect(apply.dryRun, isFalse);
    expect(apply.maxProducts, 25);
    expect(dryRun.dryRun, isTrue);
    expect(dryRun.maxProducts, isNull);
  });

  test('CLI uses the shared server filter and conditional evidence write', () {
    final source = File(
      'tool/additive_coverage_rollout.dart',
    ).readAsStringSync();

    expect(source, contains("'or': additiveCoveragePostgrestOrFilter()"));
    expect(source, contains("'scoring_evidence': 'is.null'"));
    expect(source, contains("'record_product_score_audit_snapshot'"));
  });
}

class _KnownValidationErrorEvaluator
    extends AdditiveCoverageCandidateEvaluator {
  const _KnownValidationErrorEvaluator();

  @override
  Future<AdditiveCoverageCandidateEvaluation> evaluate({
    required Product product,
    required List<LegacyStagingScoringEvidence> stagingMatches,
    required List<Ingredient> ingredientCatalogue,
  }) {
    throw StateError('simulated production validation error');
  }
}

Product _legacyProduct({required String id, required String ingredientsText}) {
  final timestamp = DateTime.utc(2026, 8, 14);
  return Product(
    id: id,
    name: 'Targeted Product $id',
    brand: 'Test Brand',
    ingredientsText: ingredientsText,
    nutritionText: jsonEncode(_nutrition()),
    source: 'web_scraper:migros',
    sourceUrl: 'https://www.migros.com.tr/product-$id',
    verificationStatus: 'imported',
    categoryTags: const ['cips_kraker'],
    canonicalCategory: 'Atıştırmalık',
    canonicalSubcategory: 'Cips & Kraker',
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

Map<String, dynamic> _nutrition() => {
  'energy_kj': 840,
  'energy_kcal': 200,
  'fat': 3,
  'saturated_fat': 1,
  'carbohydrates': 15,
  'sugars': 5,
  'fiber': 2,
  'proteins': 4,
  'salt': 0.5,
};

LegacyStagingScoringEvidence _staging(Product product) {
  return LegacyStagingScoringEvidence(
    id: 'staging-${product.id}',
    sourceUrl: product.sourceUrl!,
    nutritionBasis: 'per_100',
    source: 'web_scraper:migros',
    ingredientsSource: 'web_scraper:migros',
    ingredientsRaw: 'İçindekiler: ${product.ingredientsText}',
    ingredientsText: product.ingredientsText,
    ingredientsQuality: 'ingredients_ok',
    nutritionSource: 'web_scraper:migros',
    nutritionStrategy: 'dom',
    nutritionJson: product.nutrition?.toMap(),
  );
}

class _MemoryRolloutDataSource implements AdditiveCoverageRolloutDataSource {
  _MemoryRolloutDataSource({
    required List<Product> products,
    Map<String, EtiketlyScoreAuditSnapshot>? audits,
  }) : products = [...products]
         ..sort((left, right) => left.id.compareTo(right.id)),
       audits = {...?audits};

  final List<Product> products;
  final Map<String, EtiketlyScoreAuditSnapshot> audits;
  final List<String?> candidateRequests = [];
  int evidenceWriteAttempts = 0;
  int auditInsertAttempts = 0;
  ScoringEvidenceSnapshot? lastPersistedEvidence;

  @override
  Future<List<Ingredient>> fetchIngredientCatalogue() async => const [];

  @override
  Future<List<Product>> fetchCandidateProductsAfter({
    required String? afterProductId,
    required int limit,
  }) async {
    candidateRequests.add(afterProductId);
    return products
        .where((product) {
          final ingredients = product.ingredientsText?.toLowerCase() ?? '';
          final affected = additiveCoverageAffectedIngredientTerms.any(
            ingredients.contains,
          );
          return affected &&
              (afterProductId == null ||
                  product.id.compareTo(afterProductId) > 0);
        })
        .take(limit)
        .toList(growable: false);
  }

  @override
  Future<Product?> fetchProductById(String productId) async {
    return products.where((product) => product.id == productId).firstOrNull;
  }

  @override
  Future<Map<String, List<LegacyStagingScoringEvidence>>> fetchStagingMatches(
    Set<String> sourceUrls,
  ) async {
    return {
      for (final sourceUrl in sourceUrls)
        sourceUrl: [
          _staging(
            products.firstWhere((product) => product.sourceUrl == sourceUrl),
          ),
        ],
    };
  }

  @override
  Future<EtiketlyScoreAuditSnapshot?> fetchMatchingSnapshot(
    EtiketlyScoreAuditSnapshot current,
  ) async {
    return audits[current.productId];
  }

  @override
  Future<AdditiveCoverageEvidencePersistenceResult>
  persistScoringEvidenceIfNull(
    String productId,
    ScoringEvidenceSnapshot evidence,
  ) async {
    evidenceWriteAttempts++;
    lastPersistedEvidence = evidence;
    final index = products.indexWhere((product) => product.id == productId);
    if (index < 0) throw StateError('product not found');
    final current = products[index];
    if (current.scoringEvidence != null) {
      return AdditiveCoverageEvidencePersistenceResult(
        product: current,
        written: false,
      );
    }
    final persisted = _withEvidence(current, evidence);
    for (var offset = 0; offset < products.length; offset++) {
      if (products[offset].id == productId) products[offset] = persisted;
    }
    return AdditiveCoverageEvidencePersistenceResult(
      product: persisted,
      written: true,
    );
  }

  @override
  Future<ScoreAuditBackfillWriteResult> insertSnapshot(
    EtiketlyScoreAuditSnapshot snapshot,
  ) async {
    auditInsertAttempts++;
    final existing = audits[snapshot.productId];
    if (existing?.inputFingerprint == snapshot.inputFingerprint) {
      return const ScoreAuditBackfillWriteResult(
        snapshotId: 'existing',
        inserted: false,
      );
    }
    audits[snapshot.productId] = snapshot;
    return ScoreAuditBackfillWriteResult(
      snapshotId: 'snapshot-${snapshot.productId}',
      inserted: true,
    );
  }
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
