import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/product/models/ingredient.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/scoring/application/product_score_audit_backfill.dart';
import 'package:food_analyzer_app/features/scoring/application/product_score_audit_evaluator.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_score_audit_snapshot.dart';

import 'scoring_test_fixtures.dart';
import 'support/score_audit_test_support.dart';

void main() {
  const evaluator = ProductScoreAuditEvaluator();
  final catalogue = [auditOrdinaryIngredient()];

  Product readyProduct(int sequence, {String ingredientsText = 'Su'}) {
    return auditProductFromInput(
      completeInput(),
      id: _id(sequence),
      ingredientsText: ingredientsText,
      updatedAt: DateTime.utc(2026, 8, 8, 0, sequence),
    );
  }

  Future<EtiketlyScoreAuditSnapshot> snapshot(Product product) async {
    final result = await evaluator.evaluate(product, catalogue);
    return result.snapshot!;
  }

  test('dry run writes nothing and plans a missing current audit', () async {
    final source = _MemoryBackfillDataSource(
      products: [readyProduct(1)],
      catalogue: catalogue,
    );

    final summary = await ScoreAuditBackfillRunner(
      dataSource: source,
    ).run(const ScoreAuditBackfillOptions(dryRun: true));

    expect(summary.totalProductsExamined, 1);
    expect(summary.nutritionReady, 1);
    expect(summary.additiveReady, 1);
    expect(summary.finalScoreReady, 1);
    expect(summary.missingAudit, 1);
    expect(summary.wouldInsert, 1);
    expect(summary.inserted, 0);
    expect(source.writeAttempts, 0);
  });

  test('matching fingerprint is idempotently skipped', () async {
    final product = readyProduct(1);
    final current = await snapshot(product);
    final source = _MemoryBackfillDataSource(
      products: [product],
      catalogue: catalogue,
      audits: {product.id: current},
    );

    final summary = await ScoreAuditBackfillRunner(
      dataSource: source,
    ).run(const ScoreAuditBackfillOptions(dryRun: false));

    expect(summary.alreadyCurrentAudit, 1);
    expect(summary.wouldInsert, 0);
    expect(source.writeAttempts, 0);
  });

  test('stale and missing snapshots are both planned for insert', () async {
    final staleProduct = readyProduct(1);
    final missingProduct = readyProduct(2);
    final oldProduct = auditProductFromInput(
      completeInput(),
      id: staleProduct.id,
      ingredientsText: 'Su, su',
      updatedAt: DateTime.utc(2026, 8, 7),
    );
    final source = _MemoryBackfillDataSource(
      products: [staleProduct, missingProduct],
      catalogue: catalogue,
      audits: {staleProduct.id: await snapshot(oldProduct)},
    );

    final summary = await ScoreAuditBackfillRunner(
      dataSource: source,
    ).run(const ScoreAuditBackfillOptions(dryRun: true));

    expect(summary.staleAudit, 1);
    expect(summary.missingAudit, 1);
    expect(summary.wouldInsert, 2);
    expect(source.writeAttempts, 0);
  });

  test('unscorable products are skipped with blocker counts', () async {
    final source = _MemoryBackfillDataSource(
      products: [readyProduct(1, ingredientsText: '')],
      catalogue: catalogue,
    );

    final summary = await ScoreAuditBackfillRunner(
      dataSource: source,
    ).run(const ScoreAuditBackfillOptions(dryRun: true));

    expect(summary.notScorable, 1);
    expect(summary.finalScoreReady, 0);
    expect(summary.blockerReasons, {'missing_ingredients_text': 1});
    expect(summary.wouldInsert, 0);
  });

  test('cursor pagination respects page size and max-products', () async {
    final source = _MemoryBackfillDataSource(
      products: [for (var i = 1; i <= 5; i++) readyProduct(i)],
      catalogue: catalogue,
    );

    final summary = await ScoreAuditBackfillRunner(dataSource: source).run(
      const ScoreAuditBackfillOptions(
        dryRun: true,
        batchSize: 2,
        maxProducts: 4,
      ),
    );

    expect(source.pageRequests, [null, _id(2)]);
    expect(summary.totalProductsExamined, 4);
    expect(summary.reachedLimit, isTrue);
    expect(summary.lastExaminedCursor, _id(4));
    expect(summary.safeResumeCursor, _id(4));
  });

  test(
    'one write error is isolated and preserves a safe retry cursor',
    () async {
      final source = _MemoryBackfillDataSource(
        products: [readyProduct(1), readyProduct(2), readyProduct(3)],
        catalogue: catalogue,
        failWritesFor: {_id(2)},
      );

      final summary = await ScoreAuditBackfillRunner(
        dataSource: source,
      ).run(const ScoreAuditBackfillOptions(dryRun: false));

      expect(summary.totalProductsExamined, 3);
      expect(summary.wouldInsert, 3);
      expect(summary.inserted, 2);
      expect(summary.errors, 1);
      expect(summary.failedProductIds, [_id(2)]);
      expect(summary.lastExaminedCursor, _id(3));
      expect(summary.safeResumeCursor, _id(1));
      expect(source.audits.keys, containsAll([_id(1), _id(3)]));
    },
  );

  test('invalid row on the exact unique key requires manual review', () async {
    final product = readyProduct(1);
    final current = await snapshot(product);
    final invalidJson = current.toJson();
    invalidJson['final_score'] = current.finalScore + 1;
    final invalid = EtiketlyScoreAuditSnapshot.tryFromJson(invalidJson)!;
    final source = _MemoryBackfillDataSource(
      products: [product],
      catalogue: catalogue,
      audits: {product.id: invalid},
    );

    final summary = await ScoreAuditBackfillRunner(
      dataSource: source,
    ).run(const ScoreAuditBackfillOptions(dryRun: false));

    expect(summary.invalidAudit, 1);
    expect(summary.existingAuditRequiresReview, 1);
    expect(summary.wouldInsert, 0);
    expect(summary.errors, 1);
    expect(summary.blockerReasons, {'existing_current_key_requires_review': 1});
    expect(source.writeAttempts, 0);
  });

  test(
    'sample inspection reports score, fingerprint, versions and validity',
    () async {
      final product = readyProduct(1);
      final current = await snapshot(product);
      final source = _MemoryBackfillDataSource(
        products: [product],
        catalogue: catalogue,
        audits: {product.id: current},
      );

      final result = (await ScoreAuditSampleInspector(
        dataSource: source,
      ).inspect([product.id])).single;

      expect(result.productId, product.id);
      expect(result.barcode, product.barcode);
      expect(result.currentCalculatedScore, current.finalScore);
      expect(result.snapshotScore, current.finalScore);
      expect(result.fingerprintMatch, isTrue);
      expect(result.currentVersions, contains('score=etiketly_score_v1'));
      expect(result.validationStatus, 'valid');
      expect(result.gateStatus, 'matching');
    },
  );
}

String _id(int sequence) =>
    '00000000-0000-0000-0000-${sequence.toString().padLeft(12, '0')}';

class _MemoryBackfillDataSource implements ScoreAuditBackfillDataSource {
  _MemoryBackfillDataSource({
    required List<Product> products,
    required this.catalogue,
    Map<String, EtiketlyScoreAuditSnapshot>? audits,
    Set<String>? failWritesFor,
  }) : products = [...products]..sort((a, b) => a.id.compareTo(b.id)),
       audits = {...?audits},
       failWritesFor = {...?failWritesFor};

  final List<Product> products;
  final List<Ingredient> catalogue;
  final Map<String, EtiketlyScoreAuditSnapshot> audits;
  final Set<String> failWritesFor;
  final List<String?> pageRequests = [];
  int writeAttempts = 0;

  @override
  Future<List<Ingredient>> fetchIngredientCatalogue() async => catalogue;

  @override
  Future<List<Product>> fetchProductsAfter({
    required String? afterProductId,
    required int limit,
  }) async {
    pageRequests.add(afterProductId);
    return products
        .where(
          (product) =>
              afterProductId == null ||
              product.id.compareTo(afterProductId) > 0,
        )
        .take(limit)
        .toList(growable: false);
  }

  @override
  Future<Product?> fetchProductById(String productId) async {
    return products.where((product) => product.id == productId).firstOrNull;
  }

  @override
  Future<EtiketlyScoreAuditSnapshot?> fetchMatchingSnapshot(
    EtiketlyScoreAuditSnapshot current,
  ) async => audits[current.productId];

  @override
  Future<ScoreAuditBackfillWriteResult> insertSnapshot(
    EtiketlyScoreAuditSnapshot snapshot,
  ) async {
    writeAttempts++;
    if (failWritesFor.contains(snapshot.productId)) {
      throw StateError('simulated write failure');
    }
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
