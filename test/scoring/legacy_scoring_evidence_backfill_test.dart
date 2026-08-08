import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/product/models/ingredient.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/scoring/application/legacy_scoring_evidence_backfill.dart';
import 'package:food_analyzer_app/features/scoring/application/legacy_scoring_evidence_recovery.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_evidence_snapshot.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';

void main() {
  const recovery = LegacyScoringEvidenceRecoveryService();

  group('legacy evidence recovery', () {
    test('accepts explicit per_100 with conservative provenance', () async {
      final result = await recovery.recover(
        product: _product(),
        stagingMatches: [_staging()],
        ingredientCatalogue: const [],
      );

      expect(result.explicitPer100, isTrue);
      expect(result.basisReady, isTrue);
      expect(result.canWrite, isTrue);
      expect(result.evidence!.nutritionBasis, NutritionBasis.per100ml);
      expect(
        result.evidence!.nutritionBasisEvidence!.provenance,
        EvidenceProvenance.databaseImport,
      );
      expect(
        result.evidence!.nutritionBasisEvidence!.verification,
        EvidenceVerification.verified,
      );
      expect(
        result.evidence!.nutrition.energyKj.provenance,
        EvidenceProvenance.databaseImport,
      );
      expect(
        result.evidence!.nutrition.energyKj.verification,
        EvidenceVerification.unverified,
      );
      expect(result.evidence!.adminVerification, isNull);
    });

    test('rejects unknown nutrition basis', () async {
      final result = await _recover(staging: _staging(basis: 'unknown'));

      expect(result.canWrite, isFalse);
      expect(result.blockerReasons, contains('basis_unknown'));
    });

    test('rejects historical assumed-per-100 warning', () async {
      final result = await _recover(
        staging: _staging(
          warnings: const ['nutrition_basis_unknown_assumed_per_100'],
        ),
      );

      expect(result.canWrite, isFalse);
      expect(result.blockerReasons, contains('basis_unknown_assumed_per100'));
    });

    test('rejects per-serving nutrition', () async {
      final result = await _recover(staging: _staging(basis: 'per_serving'));

      expect(result.canWrite, isFalse);
      expect(result.blockerReasons, contains('basis_per_serving'));
    });

    test('missing fiber stays unknown and blocks readiness', () async {
      final result = await _recover(
        product: _product(nutrition: _nutrition()..remove('fiber')),
      );

      expect(result.nutritionComplete, isFalse);
      expect(result.blockerReasons, contains('missing_fiber'));
      expect(result.evidence!.nutrition.fiber.value, isNull);
    });

    test('missing category keeps generic per_100 unit ambiguous', () async {
      final result = await _recover(product: _product(categoryTags: const []));

      expect(result.classificationReady, isFalse);
      expect(result.basisReady, isFalse);
      expect(result.evidence!.nutritionBasis, NutritionBasis.unknown);
      expect(result.blockerReasons, contains('missing_classification'));
      expect(result.blockerReasons, contains('basis_unit_ambiguous'));
    });

    test('FVL stays unknown without qualifying percentage evidence', () async {
      final result = await _recover();

      expect(result.fvlReady, isFalse);
      expect(
        result.evidence!.fvlEvidence.state,
        CompositionPercentageState.unknown,
      );
      expect(result.blockerReasons, contains('fvl_unknown'));
    });

    test(
      'beverage NNS presence is retained but absence is not inferred',
      () async {
        final present = await _recover(
          product: _product(ingredientsText: 'su, aspartam, aroma'),
        );
        final unknown = await _recover(
          product: _product(ingredientsText: 'su, şeker, aroma'),
        );

        expect(present.nnsReady, isTrue);
        expect(
          present.evidence!.nnsEvidence.state,
          PresenceEvidenceState.present,
        );
        expect(
          present.evidence!.nnsEvidence.provenance,
          EvidenceProvenance.databaseImport,
        );
        expect(unknown.nnsReady, isFalse);
        expect(
          unknown.evidence!.nnsEvidence.state,
          PresenceEvidenceState.unknown,
        );
        expect(unknown.blockerReasons, contains('nns_unknown'));
      },
    );

    test('identical duplicate staging evidence is deterministic', () async {
      final result = await recovery.recover(
        product: _product(),
        stagingMatches: [
          _staging(id: 'staging-b'),
          _staging(id: 'staging-a'),
        ],
        ingredientCatalogue: const [],
      );

      expect(result.canWrite, isTrue);
      expect(result.selectedStagingId, 'staging-a');
    });

    test('conflicting duplicate staging evidence is blocked', () async {
      final result = await recovery.recover(
        product: _product(),
        stagingMatches: [
          _staging(id: 'staging-a'),
          _staging(id: 'staging-b', basis: 'unknown'),
        ],
        ingredientCatalogue: const [],
      );

      expect(result.canWrite, isFalse);
      expect(result.blockerReasons, contains('ambiguous_staging_match'));
    });
  });

  group('legacy evidence backfill runner', () {
    test('dry-run performs zero writes', () async {
      final source = _FakeDataSource(products: [_product()]);
      final summary = await _run(source, dryRun: true);

      expect(summary.wouldWrite, 1);
      expect(summary.written, 0);
      expect(source.writeCalls, 0);
      expect(source.products.single.scoringEvidence, isNull);
    });

    test('apply is bounded by max-products', () async {
      final source = _FakeDataSource(
        products: [
          _product(id: '0001'),
          _product(id: '0002'),
          _product(id: '0003'),
        ],
      );
      final summary = await _run(source, dryRun: false, maxProducts: 2);

      expect(summary.totalProductsExamined, 2);
      expect(summary.written, 2);
      expect(summary.reachedLimit, isTrue);
      expect(source.writeCalls, 2);
    });

    test('resume cursor starts strictly after the supplied product', () async {
      final source = _FakeDataSource(
        products: [
          _product(id: '0001'),
          _product(id: '0002'),
          _product(id: '0003'),
        ],
      );
      final summary = await _run(
        source,
        dryRun: true,
        startAfterProductId: '0001',
      );

      expect(summary.totalProductsExamined, 2);
      expect(summary.lastExaminedCursor, '0003');
      expect(summary.safeResumeCursor, '0003');
    });

    test('existing evidence is never overwritten', () async {
      final existing = ScoringEvidenceSnapshot();
      final source = _FakeDataSource(
        products: [_product(scoringEvidence: existing)],
      );
      final summary = await _run(source, dryRun: false, maxProducts: 1);

      expect(summary.existingScoringEvidence, 1);
      expect(summary.wouldWrite, 0);
      expect(source.writeCalls, 0);
      expect(source.products.single.scoringEvidence, same(existing));
    });

    test('conditional writes make repeated apply idempotent', () async {
      final source = _FakeDataSource(products: [_product()]);
      final first = await _run(source, dryRun: false, maxProducts: 1);
      final second = await _run(source, dryRun: false, maxProducts: 1);

      expect(first.written, 1);
      expect(second.written, 0);
      expect(second.existingScoringEvidence, 1);
      expect(source.writeCalls, 1);
    });

    test('a per-product write error does not stop later products', () async {
      final source = _FakeDataSource(
        products: [
          _product(id: '0001'),
          _product(id: '0002'),
          _product(id: '0003'),
        ],
        failingWriteIds: const {'0002'},
      );
      final summary = await _run(source, dryRun: false, maxProducts: 3);

      expect(summary.errors, 1);
      expect(summary.written, 2);
      expect(summary.failedProductIds, ['0002']);
      expect(summary.lastExaminedCursor, '0003');
      expect(summary.safeResumeCursor, '0001');
      expect(summary.halted, isFalse);
    });

    test(
      'formatter cannot leak credential text from swallowed failures',
      () async {
        const secret = 'service-role-secret-must-not-appear';
        final source = _FakeDataSource(
          products: [_product()],
          catalogueError: StateError(secret),
        );
        final summary = await _run(source, dryRun: true);
        const formatter = LegacyScoringEvidenceBackfillFormatter();

        expect(summary.halted, isTrue);
        expect(formatter.formatSummary(summary), isNot(contains(secret)));
      },
    );
  });
}

Future<LegacyScoringEvidenceRecoveryResult> _recover({
  Product? product,
  LegacyStagingScoringEvidence? staging,
}) {
  return const LegacyScoringEvidenceRecoveryService().recover(
    product: product ?? _product(),
    stagingMatches: [staging ?? _staging()],
    ingredientCatalogue: const [],
  );
}

Future<LegacyScoringEvidenceBackfillSummary> _run(
  _FakeDataSource source, {
  required bool dryRun,
  int? maxProducts,
  String? startAfterProductId,
}) {
  return LegacyScoringEvidenceBackfillRunner(dataSource: source).run(
    LegacyScoringEvidenceBackfillOptions(
      dryRun: dryRun,
      batchSize: 2,
      maxProducts: maxProducts,
      startAfterProductId: startAfterProductId,
    ),
  );
}

Product _product({
  String id = '0001',
  Map<String, dynamic>? nutrition,
  List<String>? categoryTags = const ['gazli_icecek'],
  String ingredientsText = 'su, şeker, aroma',
  ScoringEvidenceSnapshot? scoringEvidence,
}) {
  final now = DateTime.utc(2026, 8, 8);
  return Product(
    id: id,
    barcode: '8690000000000',
    name: 'Legacy product',
    ingredientsText: ingredientsText,
    nutritionText: jsonEncode(nutrition ?? _nutrition()),
    source: 'web_scraper:migros',
    sourceUrl: 'https://www.migros.com.tr/product-$id',
    verificationStatus: 'imported',
    categoryTags: categoryTags,
    scoringEvidence: scoringEvidence,
    createdAt: now,
    updatedAt: now,
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

LegacyStagingScoringEvidence _staging({
  String id = 'staging-1',
  String? basis = 'per_100',
  List<String> warnings = const [],
}) {
  return LegacyStagingScoringEvidence(
    id: id,
    sourceUrl: 'https://www.migros.com.tr/product-0001',
    nutritionBasis: basis,
    nutritionWarnings: warnings,
    nutritionProductState: 'as_sold',
  );
}

class _FakeDataSource implements LegacyScoringEvidenceBackfillDataSource {
  _FakeDataSource({
    required List<Product> products,
    this.catalogueError,
    this.failingWriteIds = const {},
  }) : products = [...products]
         ..sort((left, right) => left.id.compareTo(right.id));

  final List<Product> products;
  final Object? catalogueError;
  final Set<String> failingWriteIds;
  int writeCalls = 0;

  @override
  Future<List<Ingredient>> fetchIngredientCatalogue() async {
    if (catalogueError != null) throw catalogueError!;
    return const [];
  }

  @override
  Future<Product?> fetchProductById(String productId) async {
    return products.where((product) => product.id == productId).firstOrNull;
  }

  @override
  Future<List<Product>> fetchProductsAfter({
    required String? afterProductId,
    required int limit,
  }) async {
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
  Future<Map<String, List<LegacyStagingScoringEvidence>>> fetchStagingMatches(
    Set<String> sourceUrls,
  ) async {
    return {
      for (final sourceUrl in sourceUrls)
        sourceUrl: [
          LegacyStagingScoringEvidence(
            id: 'staging-$sourceUrl',
            sourceUrl: sourceUrl,
            nutritionBasis: 'per_100',
            nutritionProductState: 'as_sold',
          ),
        ],
    };
  }

  @override
  Future<bool> writeScoringEvidence(
    String productId,
    ScoringEvidenceSnapshot evidence,
  ) async {
    if (failingWriteIds.contains(productId)) {
      throw StateError('simulated write failure');
    }
    final index = products.indexWhere((product) => product.id == productId);
    if (index < 0 || products[index].scoringEvidence != null) return false;
    writeCalls++;
    products[index] = _copyWithEvidence(products[index], evidence);
    return true;
  }
}

Product _copyWithEvidence(Product product, ScoringEvidenceSnapshot evidence) {
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
