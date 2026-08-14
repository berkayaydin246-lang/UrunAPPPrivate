import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/product/models/ingredient.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/scoring/application/additive_coverage_impact_report.dart';
import 'package:food_analyzer_app/features/scoring/application/legacy_scoring_evidence_recovery.dart';
import 'package:food_analyzer_app/features/scoring/application/product_score_audit_evaluator.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_score_audit_snapshot.dart';

import 'scoring_test_fixtures.dart';
import 'support/score_audit_test_support.dart';

void main() {
  test(
    'affected terms cover only the accepted targeted ingredient families',
    () {
      expect(additiveCoverageAffectedIngredientTerms.toSet(), hasLength(14));
      for (final term in const [
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
      ]) {
        expect(additiveCoverageAffectedIngredientTerms, contains(term));
      }
      final filter = additiveCoveragePostgrestOrFilter();
      expect(filter, startsWith('('));
      expect(filter, endsWith(')'));
      expect(filter, contains('ingredients_text.ilike.*e202*'));
      expect(filter, contains('ingredients_text.ilike.*aroma verici*'));
    },
  );

  test(
    'runner recovers null evidence in memory and reports current v2 coverage',
    () async {
      final recoveredCandidate = _legacyProduct(
        id: '0001',
        name: 'Recovered flavouring product',
        ingredientsText: 'un, aroma vericiler',
      );
      final currentAuditCandidate = auditProductFromInput(
        completeInput(),
        id: '0002',
        name: 'Current audit product',
        brand: 'Current Brand',
        ingredientsText: 'aroma vericiler',
      );
      final blockedCandidate = auditProductFromInput(
        completeInput(),
        id: '0003',
        name: 'Unresolved additive product',
        brand: 'Blocked Brand',
        ingredientsText: 'E202, E9999',
      );
      final currentAudit = (await const ProductScoreAuditEvaluator().evaluate(
        currentAuditCandidate,
        const [],
      )).snapshot!;
      final source = _MemoryDataSource(
        products: [
          recoveredCandidate,
          recoveredCandidate,
          currentAuditCandidate,
          blockedCandidate,
        ],
        audits: {currentAuditCandidate.id: currentAudit},
      );

      final summary = await AdditiveCoverageImpactRunner(
        dataSource: source,
      ).run(const AdditiveCoverageImpactOptions(batchSize: 2));

      expect(summary.candidateProducts, 3);
      expect(summary.alreadyHasScoringEvidence, 2);
      expect(summary.currentlyFinalScoreReady, 2);
      expect(summary.needsScoringEvidenceWrite, 1);
      expect(summary.alreadyCurrentV2Audit, 1);
      expect(summary.needsV2Audit, 1);
      expect(summary.stillNotReady, 1);
      expect(summary.errors, 0);
      expect(
        summary.blockerReasons,
        containsPair('additive:unresolvedIngredientEvidence', 1),
      );
      expect(source.stagingRequests, [
        {recoveredCandidate.sourceUrl},
      ]);
      expect(source.auditRequests, hasLength(2));

      final output = const AdditiveCoverageImpactFormatter().format(summary);
      for (final line in const [
        'candidate_products=3',
        'already_has_scoring_evidence=2',
        'currently_final_score_ready=2',
        'needs_scoring_evidence_write=1',
        'already_current_v2_audit=1',
        'needs_v2_audit=1',
        'still_not_ready=1',
        'errors=0',
        'Recovered flavouring product',
        'Current audit product',
        'Unresolved additive product',
      ]) {
        expect(output, contains(line), reason: line);
      }
    },
  );

  test('CLI transport exposes no production write operation', () {
    final source = File(
      'tool/additive_coverage_impact_report.dart',
    ).readAsStringSync();

    expect(source, contains("'or': additiveCoveragePostgrestOrFilter()"));
    expect(source, contains("'get_current_product_score_audit_snapshot'"));
    expect(source, isNot(contains("'PATCH'")));
    expect(source, isNot(contains("'DELETE'")));
    expect(source, isNot(contains('record_product_score_audit_snapshot')));
    expect(source, isNot(contains('writeScoringEvidence')));
  });
}

Product _legacyProduct({
  required String id,
  required String name,
  required String ingredientsText,
}) {
  final timestamp = DateTime.utc(2026, 8, 14);
  return Product(
    id: id,
    name: name,
    brand: 'Legacy Brand',
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

class _MemoryDataSource implements AdditiveCoverageImpactDataSource {
  _MemoryDataSource({
    required List<Product> products,
    Map<String, EtiketlyScoreAuditSnapshot>? audits,
  }) : products = [...products]
         ..sort((left, right) => left.id.compareTo(right.id)),
       audits = {...?audits};

  final List<Product> products;
  final Map<String, EtiketlyScoreAuditSnapshot> audits;
  final List<Set<String>> stagingRequests = [];
  final List<String> auditRequests = [];

  @override
  Future<List<Ingredient>> fetchIngredientCatalogue() async => const [];

  @override
  Future<List<Product>> fetchCandidateProductsAfter({
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
    stagingRequests.add({...sourceUrls});
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
    auditRequests.add(current.productId);
    return audits[current.productId];
  }
}
