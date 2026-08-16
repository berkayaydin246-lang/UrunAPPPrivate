import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/product/models/ingredient.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/scoring/application/legacy_scoring_evidence_recovery.dart';
import 'package:food_analyzer_app/features/scoring/application/product_scoring_lifecycle.dart';
import 'package:food_analyzer_app/features/scoring/data/score_audit_snapshot_repository.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_score_audit_snapshot.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_evidence_snapshot.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/etiketly_public_score_audit_gate.dart';

import 'scoring_test_fixtures.dart';
import 'support/score_audit_test_support.dart';

void main() {
  late _MemoryLifecycleDataSource dataSource;
  late ProductScoringLifecycleService lifecycle;

  setUp(() {
    dataSource = _MemoryLifecycleDataSource(
      product: _withoutEvidence(
        auditProductFromInput(
          completeInput(),
          id: 'a101-ready-product',
          ingredientsText: 'Su',
        ),
      ),
      catalogue: [auditOrdinaryIngredient()],
    );
    lifecycle = ProductScoringLifecycleService(dataSource: dataSource);
  });

  test('A. ready A101-like ingestion persists evidence and v2 audit', () async {
    dataSource.product = _legacyA101Product();

    final result = await lifecycle.processCurrent(
      dataSource.product.id,
      triggerSource: ScoreAuditTriggerSource.stagingApproval,
      evidenceResolver: (product, catalogue) async {
        final recovered = await const LegacyScoringEvidenceRecoveryService()
            .recoverEvidence(
              product: product,
              stagingMatches: [_legacyA101Staging(product)],
              ingredientCatalogue: catalogue,
            );
        return ProductScoringEvidenceResolution(
          evidence: recovered.evidence,
          blockerReasons: recovered.blockerReasons,
        );
      },
    );

    expect(result.evidenceStatus, ProductScoringEvidenceStatus.persisted);
    expect(result.finalScoreReady, isTrue);
    expect(result.auditStatus, ProductScoringAuditStatus.inserted);
    expect(result.calculatedScore, isNotNull);
    expect(dataSource.product.scoringEvidence, isNotNull);
    expect(dataSource.audits.single.scoreVersion, 'etiketly_score_v2');
    expect(
      dataSource.audits.single.nutritionTransformVersion,
      'nutrition_quality_transform_v2',
    );
  });

  test(
    'B. unchanged rerun and metadata-only update reuse current audit',
    () async {
      dataSource.product = auditProductFromInput(
        completeInput(),
        id: dataSource.product.id,
        ingredientsText: 'Su',
      );
      final first = await lifecycle.processCurrent(
        dataSource.product.id,
        triggerSource: ScoreAuditTriggerSource.stagingApproval,
      );
      dataSource.product = _copyProduct(
        dataSource.product,
        name: 'A101 Görsel Adı Güncellendi',
        updatedAt: DateTime.utc(2026, 8, 15),
      );

      final second = await lifecycle.processCurrent(
        dataSource.product.id,
        triggerSource: ScoreAuditTriggerSource.catalogueChange,
      );

      expect(first.auditStatus, ProductScoringAuditStatus.inserted);
      expect(second.auditStatus, ProductScoringAuditStatus.current);
      expect(second.inputFingerprint, first.inputFingerprint);
      expect(dataSource.audits, hasLength(1));
    },
  );

  test('C. changed formula field creates a new immutable audit', () async {
    dataSource.product = auditProductFromInput(
      completeInput(),
      id: dataSource.product.id,
      ingredientsText: 'Su',
    );
    final first = await lifecycle.processCurrent(
      dataSource.product.id,
      triggerSource: ScoreAuditTriggerSource.stagingApproval,
    );
    final changedInput = completeInput(
      nutrition: completeNutrition(sugars: verifiedValue(18)),
    );
    final changedProduct = auditProductFromInput(
      changedInput,
      id: dataSource.product.id,
      ingredientsText: 'Su, şeker',
      updatedAt: DateTime.utc(2026, 8, 16),
    );
    final rebuiltEvidence = changedProduct.scoringEvidence!;
    dataSource.product = _copyProduct(
      dataSource.product,
      ingredientsText: changedProduct.ingredientsText,
      nutritionText: changedProduct.nutritionText,
      updatedAt: changedProduct.updatedAt,
    );
    dataSource.catalogue.add(auditOrdinaryIngredient(name: 'Şeker'));

    final changed = await lifecycle.processCurrent(
      dataSource.product.id,
      triggerSource: ScoreAuditTriggerSource.verifiedCorrection,
      evidenceResolver: (_, _) async =>
          ProductScoringEvidenceResolution(evidence: rebuiltEvidence),
    );

    expect(changed.evidenceStatus, ProductScoringEvidenceStatus.updated);
    expect(changed.auditStatus, ProductScoringAuditStatus.inserted);
    expect(changed.inputFingerprint, isNot(first.inputFingerprint));
    expect(dataSource.audits, hasLength(2));
    expect(dataSource.audits.first.inputFingerprint, first.inputFingerprint);
    final current = (await lifecycle.evaluator.evaluate(
      dataSource.product,
      dataSource.catalogue,
    )).snapshot!;
    const gate = EtiketlyPublicScoreAuditGate();
    expect(
      gate.evaluate(current: current, trusted: dataSource.audits.first).status,
      PublicScoreAuditStatus.stale,
    );
    expect(
      gate.evaluate(current: current, trusted: dataSource.audits.last).status,
      PublicScoreAuditStatus.matching,
    );
  });

  test('D. missing fiber preserves blocker and creates no audit', () async {
    dataSource.product = auditProductFromInput(
      completeInput(nutrition: completeNutrition(includeFiber: false)),
      id: dataSource.product.id,
      ingredientsText: 'Su',
    );

    final result = await lifecycle.processCurrent(
      dataSource.product.id,
      triggerSource: ScoreAuditTriggerSource.stagingApproval,
    );

    expect(result.finalScoreReady, isFalse);
    expect(result.auditStatus, ProductScoringAuditStatus.notReady);
    expect(result.blockerReasons, contains('nutrition:missingFiber'));
    expect(dataSource.audits, isEmpty);
  });

  test('E. unknown basis remains not ready and creates no audit', () async {
    dataSource.product = auditProductFromInput(
      completeInput(basis: NutritionBasis.unknown),
      id: dataSource.product.id,
      ingredientsText: 'Su',
    );

    final result = await lifecycle.processCurrent(
      dataSource.product.id,
      triggerSource: ScoreAuditTriggerSource.stagingApproval,
    );

    expect(result.finalScoreReady, isFalse);
    expect(result.blockerReasons, contains('nutrition:unknownNutritionBasis'));
    expect(dataSource.audits, isEmpty);
  });

  test(
    'F. unspecified flavouring remains out of scope and does not block',
    () async {
      dataSource.product = auditProductFromInput(
        completeInput(),
        id: dataSource.product.id,
        ingredientsText: 'Su, aroma vericiler',
      );

      final result = await lifecycle.processCurrent(
        dataSource.product.id,
        triggerSource: ScoreAuditTriggerSource.stagingApproval,
      );

      expect(result.finalScoreReady, isTrue);
      expect(result.auditStatus, ProductScoringAuditStatus.inserted);
      expect(
        dataSource.audits.single.canonicalAdditives.any(
          (item) => item.canonicalName == 'aroma vericiler',
        ),
        isFalse,
      );
    },
  );

  test('G. known reviewed E202 remains ready and audited as low', () async {
    dataSource.product = auditProductFromInput(
      completeInput(),
      id: dataSource.product.id,
      ingredientsText: 'Su, potasyum sorbat',
    );
    dataSource.catalogue.add(_e202());

    final result = await lifecycle.processCurrent(
      dataSource.product.id,
      triggerSource: ScoreAuditTriggerSource.stagingApproval,
    );

    expect(result.finalScoreReady, isTrue);
    final additive = dataSource.audits.single.canonicalAdditives.singleWhere(
      (item) => item.eCode == 'E202',
    );
    expect(additive.riskLevelAtCalculationTime, 'low');
  });

  test(
    'scoring failure is structured and does not mutate product data',
    () async {
      dataSource.product = auditProductFromInput(
        completeInput(),
        id: dataSource.product.id,
        ingredientsText: 'Su',
      );
      final before = dataSource.product.toJson();
      dataSource.failAuditWrites = true;

      final result = await lifecycle.processCurrent(
        dataSource.product.id,
        triggerSource: ScoreAuditTriggerSource.stagingApproval,
      );

      expect(result.auditStatus, ProductScoringAuditStatus.failed);
      expect(result.failureType, 'StateError');
      expect(dataSource.product.toJson(), before);
      expect(dataSource.audits, isEmpty);
    },
  );

  test(
    'missing current trusted evidence cannot audit stale evidence',
    () async {
      dataSource.product = auditProductFromInput(
        completeInput(),
        id: dataSource.product.id,
        ingredientsText: 'Su',
      );

      final result = await lifecycle.processCurrent(
        dataSource.product.id,
        triggerSource: ScoreAuditTriggerSource.catalogueChange,
        evidenceResolver: (_, _) async =>
            const ProductScoringEvidenceResolution(
              evidence: null,
              blockerReasons: ['missing_staging_match'],
            ),
      );

      expect(result.finalScoreReady, isFalse);
      expect(result.auditStatus, ProductScoringAuditStatus.notReady);
      expect(result.blockerReasons, contains('missing_staging_match'));
      expect(
        result.blockerReasons,
        contains('current_ingestion_evidence_unavailable'),
      );
      expect(dataSource.audits, isEmpty);
    },
  );
}

class _MemoryLifecycleDataSource implements ProductScoringLifecycleDataSource {
  _MemoryLifecycleDataSource({
    required this.product,
    required List<Ingredient> catalogue,
  }) : catalogue = [...catalogue];

  Product product;
  final List<Ingredient> catalogue;
  final List<EtiketlyScoreAuditSnapshot> audits = [];
  bool failAuditWrites = false;

  @override
  Future<Product?> fetchProduct(String productId) async {
    return product.id == productId ? product : null;
  }

  @override
  Future<List<Ingredient>> fetchIngredientCatalogue() async => catalogue;

  @override
  Future<bool> writeScoringEvidence(
    String productId,
    ScoringEvidenceSnapshot evidence, {
    required ScoringEvidenceSnapshot? expectedCurrent,
  }) async {
    if (product.id != productId) return false;
    final current = product.scoringEvidence;
    if ((current == null) != (expectedCurrent == null) ||
        (current != null &&
            jsonEncode(current.toJson()) !=
                jsonEncode(expectedCurrent!.toJson()))) {
      return false;
    }
    product = _copyProduct(
      product,
      scoringEvidence: evidence,
      updatedAt: product.updatedAt.add(const Duration(seconds: 1)),
    );
    return true;
  }

  @override
  Future<EtiketlyScoreAuditSnapshot?> fetchMatchingSnapshot(
    EtiketlyScoreAuditSnapshot current,
  ) async {
    return audits
        .where(
          (snapshot) =>
              snapshot.productId == current.productId &&
              snapshot.inputFingerprint == current.inputFingerprint &&
              snapshot.scoreVersion == current.scoreVersion &&
              snapshot.nutritionMethodologyVersion ==
                  current.nutritionMethodologyVersion &&
              snapshot.nutritionTransformVersion ==
                  current.nutritionTransformVersion &&
              snapshot.additiveTransformVersion ==
                  current.additiveTransformVersion,
        )
        .lastOrNull;
  }

  @override
  Future<ScoreAuditSnapshotWriteResult> insertSnapshot(
    EtiketlyScoreAuditSnapshot snapshot, {
    required ScoreAuditTriggerSource triggerSource,
  }) async {
    if (failAuditWrites) throw StateError('audit write failed');
    final existing = await fetchMatchingSnapshot(snapshot);
    if (existing != null) {
      return const ScoreAuditSnapshotWriteResult(
        snapshotId: 'existing',
        inserted: false,
      );
    }
    audits.add(snapshot);
    return ScoreAuditSnapshotWriteResult(
      snapshotId: 'snapshot-${audits.length}',
      inserted: true,
    );
  }
}

Product _withoutEvidence(Product product) =>
    _copyProduct(product, clearScoringEvidence: true);

Product _copyProduct(
  Product product, {
  String? name,
  String? ingredientsText,
  String? nutritionText,
  DateTime? updatedAt,
  ScoringEvidenceSnapshot? scoringEvidence,
  bool clearScoringEvidence = false,
}) {
  return Product(
    id: product.id,
    barcode: product.barcode,
    name: name ?? product.name,
    normalizedName: product.normalizedName,
    brand: product.brand,
    categoryId: product.categoryId,
    imageUrl: product.imageUrl,
    ingredientsText: ingredientsText ?? product.ingredientsText,
    nutritionText: nutritionText ?? product.nutritionText,
    source: product.source,
    sourceUrl: product.sourceUrl,
    verificationStatus: product.verificationStatus,
    searchKeywords: product.searchKeywords,
    categoryTags: product.categoryTags,
    canonicalCategory: product.canonicalCategory,
    canonicalSubcategory: product.canonicalSubcategory,
    scoringEvidence: clearScoringEvidence
        ? null
        : scoringEvidence ?? product.scoringEvidence,
    createdAt: product.createdAt,
    updatedAt: updatedAt ?? product.updatedAt,
  );
}

Ingredient _e202() {
  final now = DateTime.utc(2026, 8, 14);
  return Ingredient(
    id: 'canonical-e202',
    name: 'Potasyum Sorbat',
    normalizedName: 'potasyum sorbat',
    aliases: const ['potassium sorbate', 'e202'],
    eCode: 'E202',
    additiveGroup: 'preservative',
    riskLevel: 'low',
    createdAt: now,
    updatedAt: now,
  );
}

Product _legacyA101Product() {
  final now = DateTime.utc(2026, 8, 14);
  return Product(
    id: 'a101-ready-product',
    barcode: '8690000000100',
    name: 'A101 Hazır Atıştırmalık',
    ingredientsText: 'mısır unu, bitkisel yağ, tuz',
    nutritionText: jsonEncode(_legacyNutrition()),
    source: 'web_scraper:a101',
    sourceUrl: 'https://www.a101.com.tr/urun/a101-hazir-atistirmalik',
    verificationStatus: 'pending',
    categoryTags: const ['cips_kraker'],
    createdAt: now,
    updatedAt: now,
  );
}

LegacyStagingScoringEvidence _legacyA101Staging(Product product) {
  return LegacyStagingScoringEvidence(
    id: 'a101-staging-row',
    sourceUrl: product.sourceUrl!,
    // Basis independence correction: a generic 'per_100' never
    // distinguishes g/ml and resolves to NutritionBasis.unknown. This
    // fixture models a source that DOES retain the distinct unit — exactly
    // the forward-compatible case the fix explicitly supports.
    nutritionBasis: 'per_100g',
    source: 'web_scraper:a101',
    ingredientsSource: 'web_scraper:a101',
    ingredientsRaw: 'İçindekiler: ${product.ingredientsText}',
    ingredientsText: product.ingredientsText,
    ingredientsQuality: 'ingredients_ok',
    nutritionSource: 'web_scraper:a101',
    nutritionStrategy: 'dom',
    nutritionJson: _legacyNutrition(),
  );
}

Map<String, dynamic> _legacyNutrition() => const {
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
