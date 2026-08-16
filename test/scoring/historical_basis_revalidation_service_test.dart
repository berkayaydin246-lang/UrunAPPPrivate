import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/product/models/nutrition_data.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/scoring/adapters/product_scoring_input_adapter.dart';
import 'package:food_analyzer_app/features/scoring/application/basis_source_fetcher.dart';
import 'package:food_analyzer_app/features/scoring/application/historical_basis_revalidation_service.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/basis_revalidation_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_category_evidence.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_evidence_snapshot.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';

/// Section P test matrix — REVALIDATION. Uses a fake [BasisSourceFetcher]
/// throughout: this suite proves the deterministic identity/consistency/
/// classification LOGIC, never performs real network I/O — matching how
/// every other data source in this codebase's test suite is faked.
void main() {
  final now = DateTime.utc(2026, 8, 16, 12);
  const adapter = ProductScoringInputAdapter();

  const defaultNutritionMap = {
    'energy_kj': 840,
    'energy_kcal': 200,
    'fat': 3,
    'saturated_fat': 1,
    'sugars': 5,
    'fiber': 2,
    'proteins': 4,
    'salt': 0.5,
  };

  // Real basis-revalidation candidates always carry a resolved scoring
  // branch: they are either already-current products or products blocked
  // ONLY on basis (see basis_revalidation_candidate_planner.dart), both of
  // which require a persisted [ScoringEvidenceSnapshot]. Building one here
  // — rather than leaving [Product.scoringEvidence] null and hoping
  // category tags resolve — is what makes the STORED side of the
  // dependency-aware consistency gate deterministic in tests, exactly
  // mirroring how [HistoricalBasisRevalidationService] resolves it via
  // [ProductScoringInputAdapter.fromProduct] in production.
  Product product({
    String id = 'p1',
    String? barcode = '8690000000123',
    String source = 'web_scraper:migros',
    String sourceUrl = 'https://www.migros.com.tr/some-product-p-abc123',
    Map<String, dynamic>? nutrition,
    ScoringCategory category = ScoringCategory.generalFood,
  }) {
    final nutritionMap = nutrition ?? defaultNutritionMap;
    return Product(
      id: id,
      barcode: barcode,
      name: 'Test Product',
      source: source,
      sourceUrl: sourceUrl,
      verificationStatus: 'imported',
      nutritionText: jsonEncode(nutritionMap),
      scoringEvidence: ScoringEvidenceSnapshot(
        categoryEvidence: ScoringCategoryEvidence(
          resolvedCategory: category,
          source: CategoryEvidenceSource.manualAdminVerification,
          evidenceValues: [category.name],
          reasons: const [
            CategoryResolutionReason.resolvedFromExplicitMetadata,
          ],
        ),
        nutrition: adapter.fromLegacyNutrition(
          NutritionData.fromMap(nutritionMap),
        ),
      ),
      createdAt: now,
      updatedAt: now,
    );
  }

  BasisSourceFetchResult fetchResult({
    String? barcode = '8690000000123',
    String? canonicalUrlIdentifier = 'abc123',
    String normalizedBasis = 'per_100g',
    String? rawBasisText = '100 g',
    NutritionData? nutrition,
  }) {
    return BasisSourceFetchResult(
      adapterVersion: 'migros_v1',
      fetchedAt: now,
      barcode: barcode,
      canonicalUrlIdentifier: canonicalUrlIdentifier,
      rawBasisText: rawBasisText,
      normalizedBasis: normalizedBasis,
      nutrition:
          nutrition ??
          const NutritionData(
            energyKj: 840,
            energyKcal: 200,
            fat: 3,
            saturatedFat: 1,
            sugars: 5,
            fiber: 2,
            proteins: 4,
            salt: 0.5,
          ),
    );
  }

  group('exact identity + equal nutrition + exact source basis', () {
    test('barcode identity, matching nutrition, per_100g -> revalidated', () async {
      final fetcher = _FakeFetcher(result: fetchResult());
      final service = HistoricalBasisRevalidationService(fetcher: fetcher);

      final result = await service.revalidate(product());

      expect(result.outcome, BasisRevalidationOutcome.exactBasisRevalidated);
      expect(result.revalidatedBasis, NutritionBasis.per100g);
      expect(result.identityVerificationMethod, 'barcode');
      expect(result.adapterVersion, 'migros_v1');
      expect(result.rawBasisText, '100 g');
    });

    test('per_100ml resolves to NutritionBasis.per100ml', () async {
      final fetcher = _FakeFetcher(
        result: fetchResult(normalizedBasis: 'per_100ml', rawBasisText: '100 ml'),
      );
      final service = HistoricalBasisRevalidationService(fetcher: fetcher);

      final result = await service.revalidate(product());

      expect(result.outcome, BasisRevalidationOutcome.exactBasisRevalidated);
      expect(result.revalidatedBasis, NutritionBasis.per100ml);
    });

    test(
      'canonical URL identifier tier succeeds when no barcode exists on '
      'either side, given a supplied extractor',
      () async {
        final fetcher = _FakeFetcher(
          result: fetchResult(barcode: null, canonicalUrlIdentifier: 'abc123'),
        );
        final service = HistoricalBasisRevalidationService(
          fetcher: fetcher,
          extractCanonicalIdentifier: (url) =>
              RegExp(r'-p-([a-z0-9]+)').firstMatch(url)?.group(1),
        );

        final result = await service.revalidate(product(barcode: null));

        expect(result.outcome, BasisRevalidationOutcome.exactBasisRevalidated);
        expect(result.identityVerificationMethod, 'canonical_url_identifier');
      },
    );
  });

  group('barcode mismatch -> fail', () {
    test('differing barcodes never fall through to URL identifier tier', () async {
      final fetcher = _FakeFetcher(
        result: fetchResult(barcode: '8690000000999'),
      );
      final service = HistoricalBasisRevalidationService(
        fetcher: fetcher,
        extractCanonicalIdentifier: (url) =>
            RegExp(r'-p-([a-z0-9]+)').firstMatch(url)?.group(1),
      );

      final result = await service.revalidate(product());

      expect(result.outcome, BasisRevalidationOutcome.identityUnverified);
    });
  });

  group('retailer canonical identifier mismatch -> fail', () {
    test('differing URL identifiers fail closed', () async {
      final fetcher = _FakeFetcher(
        result: fetchResult(barcode: null, canonicalUrlIdentifier: 'zzz999'),
      );
      final service = HistoricalBasisRevalidationService(
        fetcher: fetcher,
        extractCanonicalIdentifier: (url) =>
            RegExp(r'-p-([a-z0-9]+)').firstMatch(url)?.group(1),
      );

      final result = await service.revalidate(product(barcode: null));

      expect(result.outcome, BasisRevalidationOutcome.identityUnverified);
    });

    test(
      'no extractor supplied and no barcode on either side -> identity '
      'unverified, never guessed from name/brand',
      () async {
        final fetcher = _FakeFetcher(result: fetchResult(barcode: null));
        final service = HistoricalBasisRevalidationService(fetcher: fetcher);

        final result = await service.revalidate(product(barcode: null));

        expect(result.outcome, BasisRevalidationOutcome.identityUnverified);
      },
    );
  });

  group('nutrition changed -> requires reingest', () {
    test('a single differing scoring-relevant field blocks basis attach', () async {
      final fetcher = _FakeFetcher(
        result: fetchResult(
          nutrition: const NutritionData(
            energyKj: 840,
            energyKcal: 200,
            fat: 3,
            saturatedFat: 1,
            sugars: 12, // changed from 5
            fiber: 2,
            proteins: 4,
            salt: 0.5,
          ),
        ),
      );
      final service = HistoricalBasisRevalidationService(fetcher: fetcher);

      final result = await service.revalidate(product());

      expect(
        result.outcome,
        BasisRevalidationOutcome.sourceChangedRequiresReingest,
      );
      expect(result.nutritionMismatchFields, contains('sugars'));
      expect(
        result.revalidatedBasis,
        isNull,
        reason: 'the exact basis must never attach to nutrition that no '
            'longer matches',
      );
    });

    test(
      'a branch-required field absent from the fresh source is fail-closed, '
      'never treated as agreement (generalFood requires fiber)',
      () async {
        final fetcher = _FakeFetcher(
          result: fetchResult(
            nutrition: const NutritionData(
              energyKj: 840,
              energyKcal: 200,
              fat: 3,
              saturatedFat: 1,
              sugars: 5,
              // fiber intentionally absent from the fresh fetch — generalFood
              // requires it (see ScoringReadinessEvaluator._categoryRequirements).
              proteins: 4,
              salt: 0.5,
            ),
          ),
        );
        final service = HistoricalBasisRevalidationService(fetcher: fetcher);

        final result = await service.revalidate(product());

        expect(
          result.outcome,
          BasisRevalidationOutcome.nutritionConsistencyUnverified,
        );
        expect(result.nutritionMissingRequiredFields, contains('fiber'));
        expect(
          result.revalidatedBasis,
          isNull,
          reason: 'a live source silent on a branch-required field proves '
              'nothing about whether the stored value is still correct',
        );
      },
    );
  });

  group('dependency-aware: only branch-relevant fields gate consistency', () {
    test(
      'fatsOilsNutsSeeds: fresh totalFat differing from stored -> '
      'sourceChangedRequiresReingest',
      () async {
        final fetcher = _FakeFetcher(
          result: fetchResult(
            nutrition: const NutritionData(
              energyKj: 840,
              energyKcal: 200,
              fat: 30, // changed from 3
              saturatedFat: 1,
              sugars: 5,
              fiber: 2,
              proteins: 4,
              salt: 0.5,
            ),
          ),
        );
        final service = HistoricalBasisRevalidationService(fetcher: fetcher);

        final result = await service.revalidate(
          product(category: ScoringCategory.fatsOilsNutsSeeds),
        );

        expect(
          result.outcome,
          BasisRevalidationOutcome.sourceChangedRequiresReingest,
        );
        expect(result.nutritionMismatchFields, contains('total_fat'));
      },
    );

    test(
      'fatsOilsNutsSeeds: fresh totalFat missing entirely -> '
      'nutritionConsistencyUnverified',
      () async {
        final fetcher = _FakeFetcher(
          result: fetchResult(
            nutrition: const NutritionData(
              energyKj: 840,
              energyKcal: 200,
              // fat intentionally absent — fatsOilsNutsSeeds requires it.
              saturatedFat: 1,
              sugars: 5,
              fiber: 2,
              proteins: 4,
              salt: 0.5,
            ),
          ),
        );
        final service = HistoricalBasisRevalidationService(fetcher: fetcher);

        final result = await service.revalidate(
          product(category: ScoringCategory.fatsOilsNutsSeeds),
        );

        expect(
          result.outcome,
          BasisRevalidationOutcome.nutritionConsistencyUnverified,
        );
        expect(result.nutritionMissingRequiredFields, contains('total_fat'));
      },
    );

    test(
      'fatsOilsNutsSeeds: energy_kj is not in this branch\'s dependency set, '
      'so its absence from the fresh source never blocks',
      () async {
        final fetcher = _FakeFetcher(
          result: fetchResult(
            nutrition: const NutritionData(
              // energyKj/energyKcal intentionally absent — fatsOilsNutsSeeds
              // depends on totalFat instead, never energy, for this branch.
              fat: 3,
              saturatedFat: 1,
              sugars: 5,
              fiber: 2,
              proteins: 4,
              salt: 0.5,
            ),
          ),
        );
        final service = HistoricalBasisRevalidationService(fetcher: fetcher);

        final result = await service.revalidate(
          product(category: ScoringCategory.fatsOilsNutsSeeds),
        );

        expect(result.outcome, BasisRevalidationOutcome.exactBasisRevalidated);
        expect(result.nutritionConsistencyChecked, isNot(contains('energy_kj')));
      },
    );

    test(
      'cheese: fresh source missing protein (always required for cheese) '
      '-> nutritionConsistencyUnverified',
      () async {
        final fetcher = _FakeFetcher(
          result: fetchResult(
            nutrition: const NutritionData(
              energyKj: 840,
              energyKcal: 200,
              fat: 3,
              saturatedFat: 1,
              sugars: 5,
              fiber: 2,
              // proteins intentionally absent — cheese always requires it.
              salt: 0.5,
            ),
          ),
        );
        final service = HistoricalBasisRevalidationService(fetcher: fetcher);

        final result = await service.revalidate(
          product(category: ScoringCategory.cheese),
        );

        expect(
          result.outcome,
          BasisRevalidationOutcome.nutritionConsistencyUnverified,
        );
        expect(result.nutritionMissingRequiredFields, contains('protein'));
      },
    );

    test(
      'redMeat: fresh source missing fibre (always required for redMeat) '
      '-> nutritionConsistencyUnverified',
      () async {
        final fetcher = _FakeFetcher(
          result: fetchResult(
            nutrition: const NutritionData(
              energyKj: 840,
              energyKcal: 200,
              fat: 3,
              saturatedFat: 1,
              sugars: 5,
              // fiber intentionally absent — redMeat always requires it.
              proteins: 4,
              salt: 0.5,
            ),
          ),
        );
        final service = HistoricalBasisRevalidationService(fetcher: fetcher);

        final result = await service.revalidate(
          product(category: ScoringCategory.redMeat),
        );

        expect(
          result.outcome,
          BasisRevalidationOutcome.nutritionConsistencyUnverified,
        );
        expect(result.nutritionMissingRequiredFields, contains('fiber'));
      },
    );

    test(
      'beverage: fresh source missing protein (always required for '
      'beverage) -> nutritionConsistencyUnverified',
      () async {
        final fetcher = _FakeFetcher(
          result: fetchResult(
            nutrition: const NutritionData(
              energyKj: 840,
              energyKcal: 200,
              fat: 3,
              saturatedFat: 1,
              sugars: 5,
              fiber: 2,
              // proteins intentionally absent — beverage always requires it.
              salt: 0.5,
            ),
          ),
        );
        final service = HistoricalBasisRevalidationService(fetcher: fetcher);

        final result = await service.revalidate(
          product(category: ScoringCategory.beverage),
        );

        expect(
          result.outcome,
          BasisRevalidationOutcome.nutritionConsistencyUnverified,
        );
        expect(result.nutritionMissingRequiredFields, contains('protein'));
      },
    );
  });

  group('generic current source header -> still ambiguous', () {
    test('per_100_generic never becomes a success', () async {
      final fetcher = _FakeFetcher(
        result: fetchResult(
          normalizedBasis: 'per_100_generic',
          rawBasisText: '100 g / ml',
        ),
      );
      final service = HistoricalBasisRevalidationService(fetcher: fetcher);

      final result = await service.revalidate(product());

      expect(
        result.outcome,
        BasisRevalidationOutcome.genericBasisStillAmbiguous,
      );
      expect(result.revalidatedBasis, isNull);
    });

    test('the historical bare per_100 string is also still ambiguous', () async {
      final fetcher = _FakeFetcher(
        result: fetchResult(normalizedBasis: 'per_100'),
      );
      final service = HistoricalBasisRevalidationService(fetcher: fetcher);

      final result = await service.revalidate(product());

      expect(
        result.outcome,
        BasisRevalidationOutcome.genericBasisStillAmbiguous,
      );
    });
  });

  group('source unavailable -> fail closed', () {
    test('a null fetch result is reported as sourceUnavailable, never a throw', () async {
      final fetcher = _FakeFetcher(result: null);
      final service = HistoricalBasisRevalidationService(fetcher: fetcher);

      final result = await service.revalidate(product());

      expect(result.outcome, BasisRevalidationOutcome.sourceUnavailable);
    });

    test('a product missing source/sourceUrl never attempts a fetch', () async {
      final fetcher = _FakeFetcher(result: fetchResult());
      final service = HistoricalBasisRevalidationService(fetcher: fetcher);
      final orphan = Product(
        id: 'orphan',
        name: 'No source',
        verificationStatus: 'imported',
        createdAt: now,
        updatedAt: now,
      );

      final result = await service.revalidate(orphan);

      expect(result.outcome, BasisRevalidationOutcome.sourceUnavailable);
      expect(fetcher.fetchCallCount, 0);
    });

    test('a fetcher exception is classified as unexpectedError, never crashes', () async {
      final fetcher = _FakeFetcher(throwOnFetch: true);
      final service = HistoricalBasisRevalidationService(fetcher: fetcher);

      final result = await service.revalidate(product());

      expect(result.outcome, BasisRevalidationOutcome.unexpectedError);
    });
  });

  group('basis not present', () {
    test('an unknown normalized basis is reported distinctly from generic', () async {
      final fetcher = _FakeFetcher(
        result: fetchResult(normalizedBasis: 'unknown', rawBasisText: null),
      );
      final service = HistoricalBasisRevalidationService(fetcher: fetcher);

      final result = await service.revalidate(product());

      expect(result.outcome, BasisRevalidationOutcome.basisNotPresent);
    });

    test('per_serving is also reported as basis not present, never accepted', () async {
      final fetcher = _FakeFetcher(
        result: fetchResult(normalizedBasis: 'per_serving'),
      );
      final service = HistoricalBasisRevalidationService(fetcher: fetcher);

      final result = await service.revalidate(product());

      expect(result.outcome, BasisRevalidationOutcome.basisNotPresent);
    });
  });

  group('repeated successful revalidation -> idempotent', () {
    test('the same fetch result revalidated twice produces identical outcomes', () async {
      final fetcher = _FakeFetcher(result: fetchResult());
      final service = HistoricalBasisRevalidationService(fetcher: fetcher);
      final target = product();

      final first = await service.revalidate(target);
      final second = await service.revalidate(target);

      expect(first.outcome, second.outcome);
      expect(first.revalidatedBasis, second.revalidatedBasis);
      expect(fetcher.fetchCallCount, 2, reason: 'the service itself is pure — '
          'idempotency here means stable output, not caching/skipping calls');
    });
  });
}

class _FakeFetcher implements BasisSourceFetcher {
  _FakeFetcher({this.result, this.throwOnFetch = false});

  final BasisSourceFetchResult? result;
  final bool throwOnFetch;
  int fetchCallCount = 0;

  @override
  Future<BasisSourceFetchResult?> fetch({
    required String source,
    required String sourceUrl,
  }) async {
    fetchCallCount++;
    if (throwOnFetch) {
      throw StateError('simulated fetch failure');
    }
    return result;
  }
}
