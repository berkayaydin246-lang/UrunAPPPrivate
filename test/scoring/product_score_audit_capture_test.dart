import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/product/models/ingredient.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/product/repositories/product_repository.dart';
import 'package:food_analyzer_app/features/scoring/application/product_score_audit_capture_service.dart';
import 'package:food_analyzer_app/features/scoring/data/score_audit_snapshot_repository.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_score_audit_snapshot.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/etiketly_public_score_audit_gate.dart';

import 'scoring_test_fixtures.dart';
import 'support/score_audit_test_support.dart';

void main() {
  late _MutableProductRepository products;
  late _MemoryAuditRepository audits;
  late ProductScoreAuditCaptureService capture;

  setUp(() {
    products = _MutableProductRepository(
      product: auditProductFromInput(completeInput(), ingredientsText: 'Su'),
      catalogue: [auditOrdinaryIngredient()],
    );
    audits = _MemoryAuditRepository();
    capture = ProductScoreAuditCaptureService(
      productRepository: products,
      auditRepository: audits,
    );
  });

  test(
    '28. approved scoring-ready flows create matching trusted snapshots',
    () async {
      final result = await capture.captureCurrent(
        products.product.id,
        triggerSource: ScoreAuditTriggerSource.submissionApproval,
      );

      expect(result.status, ProductScoreAuditCaptureStatus.inserted);
      expect(audits.rows, hasLength(1));
      expect(
        const EtiketlyPublicScoreAuditGate()
            .evaluate(current: audits.rows.single, trusted: audits.rows.single)
            .mayDisplayNumericScore,
        isTrue,
      );
      expect(audits.triggers, [ScoreAuditTriggerSource.submissionApproval]);

      final submissionSource = File(
        'lib/features/admin/repositories/product_submission_approval_repository.dart',
      ).readAsStringSync();
      final stagingSource = File(
        'lib/features/admin/repositories/product_staging_approval_repository.dart',
      ).readAsStringSync();
      expect(
        submissionSource,
        contains('ScoreAuditTriggerSource.submissionApproval'),
      );
      expect(
        stagingSource,
        contains('ScoreAuditTriggerSource.stagingApproval'),
      );
    },
  );

  test('29. verified correction creates a new snapshot', () async {
    await capture.captureCurrent(
      products.product.id,
      triggerSource: ScoreAuditTriggerSource.submissionApproval,
    );
    products.product = auditProductFromInput(
      completeInput(),
      ingredientsText: 'Su, su',
      updatedAt: DateTime.utc(2026, 8, 9),
    );

    final result = await capture.captureCurrent(
      products.product.id,
      triggerSource: ScoreAuditTriggerSource.verifiedCorrection,
    );

    expect(result.status, ProductScoreAuditCaptureStatus.inserted);
    expect(audits.rows, hasLength(2));
    expect(
      audits.rows.first.inputFingerprint,
      isNot(audits.rows.last.inputFingerprint),
    );
  });

  test('30. correction leaves the historical snapshot unchanged', () async {
    await capture.captureCurrent(
      products.product.id,
      triggerSource: ScoreAuditTriggerSource.submissionApproval,
    );
    final historicalJson = audits.rows.single.toJson();
    products.product = auditProductFromInput(
      completeInput(),
      ingredientsText: 'Su, su',
      updatedAt: DateTime.utc(2026, 8, 9),
    );
    await capture.captureCurrent(
      products.product.id,
      triggerSource: ScoreAuditTriggerSource.verifiedCorrection,
    );

    expect(audits.rows.first.toJson(), historicalJson);
    expect(audits.rows, hasLength(2));
  });

  test('31. duplicate fingerprint does not create a duplicate row', () async {
    final first = await capture.captureCurrent(
      products.product.id,
      triggerSource: ScoreAuditTriggerSource.submissionApproval,
    );
    final duplicate = await capture.captureCurrent(
      products.product.id,
      triggerSource: ScoreAuditTriggerSource.submissionApproval,
    );

    expect(first.status, ProductScoreAuditCaptureStatus.inserted);
    expect(duplicate.status, ProductScoreAuditCaptureStatus.duplicate);
    expect(audits.rows, hasLength(1));
  });

  test(
    '32. failed write cannot produce publicly auditable score state',
    () async {
      audits.failWrites = true;
      await expectLater(
        capture.captureCurrent(
          products.product.id,
          triggerSource: ScoreAuditTriggerSource.stagingApproval,
        ),
        throwsStateError,
      );
      expect(audits.rows, isEmpty);

      final current = buildAuditSnapshot(
        product: products.product,
        assessment: auditOrdinaryAssessment(),
      );
      final decision = const EtiketlyPublicScoreAuditGate().evaluate(
        current: current,
        trusted: null,
      );
      expect(decision.mayDisplayNumericScore, isFalse);
    },
  );
}

class _MutableProductRepository extends ProductRepository {
  _MutableProductRepository({required this.product, required this.catalogue});

  Product product;
  final List<Ingredient> catalogue;

  @override
  Future<Product?> getProductById(String id) async =>
      id == product.id ? product : null;

  @override
  Future<List<Ingredient>> getAllIngredients() async => catalogue;
}

class _MemoryAuditRepository implements ScoreAuditSnapshotRepository {
  final List<EtiketlyScoreAuditSnapshot> rows = [];
  final List<ScoreAuditTriggerSource> triggers = [];
  bool failWrites = false;

  @override
  Future<EtiketlyScoreAuditSnapshot?> fetchMatching(
    EtiketlyScoreAuditSnapshot current,
  ) async {
    return rows
        .where(
          (row) =>
              row.productId == current.productId &&
              row.inputFingerprint == current.inputFingerprint,
        )
        .lastOrNull;
  }

  @override
  Future<ScoreAuditSnapshotWriteResult> insertTrusted(
    EtiketlyScoreAuditSnapshot snapshot, {
    required ScoreAuditTriggerSource triggerSource,
  }) async {
    if (failWrites) throw StateError('trusted write failed');
    final existingIndex = rows.indexWhere(
      (row) =>
          row.productId == snapshot.productId &&
          row.inputFingerprint == snapshot.inputFingerprint &&
          row.scoreVersion == snapshot.scoreVersion &&
          row.nutritionMethodologyVersion ==
              snapshot.nutritionMethodologyVersion &&
          row.nutritionTransformVersion == snapshot.nutritionTransformVersion &&
          row.additiveTransformVersion == snapshot.additiveTransformVersion,
    );
    triggers.add(triggerSource);
    if (existingIndex >= 0) {
      return ScoreAuditSnapshotWriteResult(
        snapshotId: 'snapshot-$existingIndex',
        inserted: false,
      );
    }
    rows.add(snapshot);
    return ScoreAuditSnapshotWriteResult(
      snapshotId: 'snapshot-${rows.length - 1}',
      inserted: true,
    );
  }
}
