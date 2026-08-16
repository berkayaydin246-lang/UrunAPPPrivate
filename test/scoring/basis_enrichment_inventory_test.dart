import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/scoring/application/legacy_scoring_evidence_recovery.dart'
    show LegacyStagingScoringEvidence;

import '../../tool/final_basis_enrichment_inventory.dart';

/// Focused tests for the read-only classification logic in
/// tool/final_basis_enrichment_inventory.dart — strict exact-unit rules,
/// bucket precedence, and identity-ambiguity fail-closed behavior. Never
/// exercises the REST plumbing (no network, no database).
void main() {
  LegacyStagingScoringEvidenceStub stagingEvidence({
    String id = 's1',
    String sourceUrl = 'https://www.migros.com.tr/product-p-abc123',
    String? nutritionBasis,
  }) {
    return LegacyStagingScoringEvidenceStub(
      id: id,
      sourceUrl: sourceUrl,
      nutritionBasis: nutritionBasis,
    );
  }

  group('classifyRawBasisText: strict exact-unit rule', () {
    test('"100 g" is exact grams', () {
      expect(
        classifyRawBasisText('Besin değerleri 100 g için'),
        RawBasisTextClassification.exactGrams,
      );
    });

    test('"100 ml" is exact ml', () {
      expect(
        classifyRawBasisText('Besin değerleri 100 ml için'),
        RawBasisTextClassification.exactMl,
      );
    });

    test('"100 g / ml" is NOT exact (combined/ambiguous)', () {
      expect(
        classifyRawBasisText('100 g / ml'),
        RawBasisTextClassification.combinedAmbiguous,
      );
    });

    test('"100g/ml" (no spaces) is also NOT exact', () {
      expect(
        classifyRawBasisText('100g/ml'),
        RawBasisTextClassification.combinedAmbiguous,
      );
    });

    test('empty/missing text is none, never exact', () {
      expect(classifyRawBasisText(null), RawBasisTextClassification.none);
      expect(classifyRawBasisText('  '), RawBasisTextClassification.none);
    });

    test('a bare "per 100" phrase with no unit is generic, never exact', () {
      expect(
        classifyRawBasisText('per 100'),
        RawBasisTextClassification.generic,
      );
    });
  });

  group('classifyOriginalBasisBlockerGroup: exact manifest mapping', () {
    test('maps all four known manifest blocker strings', () {
      expect(
        classifyOriginalBasisBlockerGroup('nutrition:unknownNutritionBasis'),
        'legacy_untrusted_basis',
      );
      expect(
        classifyOriginalBasisBlockerGroup('basis_unknown'),
        'basis_unknown',
      );
      expect(
        classifyOriginalBasisBlockerGroup(
          'basis_generic_ambiguous_exact_unit_unproven,basis_unit_ambiguous',
        ),
        'generic_per100_exact_unit_unproven',
      );
      expect(
        classifyOriginalBasisBlockerGroup('basis_unknown_assumed_per100'),
        'assumed_per100_untrusted',
      );
    });

    test('an unrecognized blocker string fails closed, never guessed', () {
      expect(
        classifyOriginalBasisBlockerGroup('something_new'),
        'unrecognized_blocker_group',
      );
    });
  });

  group('parseBasisEnrichmentManifest', () {
    test('parses tab-separated rows with CRLF line endings, skips header', () {
      final tsv =
          'product_id\tproduct_name\toutcome\tblockers\r\n'
          'p1\tName One\texistingEvidenceAuditUnavailable\t'
          'nutrition:unknownNutritionBasis\r\n'
          'p2\tName Two\tblocked\tbasis_unknown\r\n';

      final entries = parseBasisEnrichmentManifest(tsv);

      expect(entries, hasLength(2));
      expect(entries[0].productId, 'p1');
      expect(entries[0].originalBasisBlockerGroup, 'legacy_untrusted_basis');
      expect(entries[1].productId, 'p2');
      expect(entries[1].originalBasisBlockerGroup, 'basis_unknown');
    });

    test('empty content produces an empty list, never throws', () {
      expect(parseBasisEnrichmentManifest(''), isEmpty);
    });
  });

  group('classifyBasisEnrichmentCandidate: bucket A (exact retained basis)', () {
    test('staging nutritionBasis exactly per_100g -> RETAINED_EXACT_BASIS', () {
      final row = classifyBasisEnrichmentCandidate(
        productId: 'p1',
        productName: 'Product',
        originalBasisBlockerGroup: 'legacy_untrusted_basis',
        productBarcode: null,
        productSource: 'web_scraper:migros',
        productSourceUrl: 'https://www.migros.com.tr/x-p-abc123',
        productImageUrl: null,
        stagingMatches: [
          BasisEnrichmentStagingRow(
            evidence: stagingEvidence(nutritionBasis: 'per_100g').build(),
          ),
        ],
      );

      expect(row.bucket, BasisEnrichmentBucket.retainedExactBasis);
      expect(row.hasExactBasisEvidence, isTrue);
    });

    test('staging nutritionBasis exactly per_100ml -> RETAINED_EXACT_BASIS', () {
      final row = classifyBasisEnrichmentCandidate(
        productId: 'p1',
        productName: 'Product',
        originalBasisBlockerGroup: 'basis_unknown',
        productBarcode: null,
        productSource: null,
        productSourceUrl: null,
        productImageUrl: null,
        stagingMatches: [
          BasisEnrichmentStagingRow(
            evidence: stagingEvidence(nutritionBasis: 'per_100ml').build(),
          ),
        ],
      );

      expect(row.bucket, BasisEnrichmentBucket.retainedExactBasis);
    });

    test(
      'staging nutritionBasis == per_100_generic is NOT exact — generic '
      'forms never count',
      () {
        final row = classifyBasisEnrichmentCandidate(
          productId: 'p1',
          productName: 'Product',
          originalBasisBlockerGroup: 'generic_per100_exact_unit_unproven',
          productBarcode: null,
          productSource: null,
          productSourceUrl: 'https://www.migros.com.tr/x-p-abc123',
          productImageUrl: null,
          stagingMatches: [
            BasisEnrichmentStagingRow(
              evidence: stagingEvidence(
                nutritionBasis: 'per_100_generic',
              ).build(),
            ),
          ],
        );

        expect(row.hasExactBasisEvidence, isFalse);
        expect(row.bucket, isNot(BasisEnrichmentBucket.retainedExactBasis));
      },
    );

    test(
      'a product-level legacy per100g enum is structurally never evidence: '
      'this function has no parameter for it at all, so omitting a '
      'staging match never falls back to it',
      () {
        final row = classifyBasisEnrichmentCandidate(
          productId: 'p1',
          productName: 'Product',
          originalBasisBlockerGroup: 'legacy_untrusted_basis',
          productBarcode: null,
          productSource: 'web_scraper:migros',
          productSourceUrl: 'https://www.migros.com.tr/x-p-abc123',
          productImageUrl: null,
          stagingMatches: const [],
        );

        expect(row.hasExactBasisEvidence, isFalse);
        expect(row.bucket, isNot(BasisEnrichmentBucket.retainedExactBasis));
        expect(row.matchedStaging, isFalse);
      },
    );

    test(
      'databaseImport-style untrusted provenance is never a function '
      'input — only independently retained staging evidence can produce '
      'RETAINED_EXACT_BASIS',
      () {
        // No staging match at all models "the only basis this product has
        // is its own untrusted, category-derived scoring_evidence enum" —
        // proving the classifier cannot manufacture exactness from it.
        final row = classifyBasisEnrichmentCandidate(
          productId: 'p1',
          productName: 'Product',
          originalBasisBlockerGroup: 'legacy_untrusted_basis',
          productBarcode: '8690000000000',
          productSource: 'web_scraper:migros',
          productSourceUrl: null,
          productImageUrl: null,
          stagingMatches: const [],
        );

        expect(row.hasExactBasisEvidence, isFalse);
      },
    );
  });

  group('classifyBasisEnrichmentCandidate: bucket B (raw text exact)', () {
    test(
      'generic normalized basis but raw text explicitly says "100 g" -> '
      'RETAINED_RAW_BASIS_TEXT_EXACT',
      () {
        final row = classifyBasisEnrichmentCandidate(
          productId: 'p1',
          productName: 'Product',
          originalBasisBlockerGroup: 'generic_per100_exact_unit_unproven',
          productBarcode: null,
          productSource: null,
          productSourceUrl: null,
          productImageUrl: null,
          stagingMatches: [
            BasisEnrichmentStagingRow(
              evidence: stagingEvidence(
                nutritionBasis: 'per_100_generic',
              ).build(),
              rawBasisText: '100 g başına besin değerleri',
            ),
          ],
        );

        expect(row.bucket, BasisEnrichmentBucket.retainedRawBasisTextExact);
        expect(row.rawBasisNormalizedSummary, 'exactGrams');
      },
    );

    test(
      'raw text says "100 g / ml" -> generic stays generic, never '
      'upgraded to bucket B',
      () {
        final row = classifyBasisEnrichmentCandidate(
          productId: 'p1',
          productName: 'Product',
          originalBasisBlockerGroup: 'generic_per100_exact_unit_unproven',
          productBarcode: null,
          productSource: null,
          productSourceUrl: 'https://www.migros.com.tr/x-p-abc123',
          productImageUrl: null,
          stagingMatches: [
            BasisEnrichmentStagingRow(
              evidence: stagingEvidence(
                nutritionBasis: 'per_100_generic',
              ).build(),
              rawBasisText: '100 g / ml',
            ),
          ],
        );

        expect(
          row.bucket,
          isNot(BasisEnrichmentBucket.retainedRawBasisTextExact),
        );
        expect(row.rawBasisNormalizedSummary, 'combinedAmbiguous');
      },
    );

    test('exact retained text beats an available label image (A/B > C)', () {
      final row = classifyBasisEnrichmentCandidate(
        productId: 'p1',
        productName: 'Product',
        originalBasisBlockerGroup: 'basis_unknown',
        productBarcode: null,
        productSource: null,
        productSourceUrl: null,
        productImageUrl: null,
        stagingMatches: [
          BasisEnrichmentStagingRow(
            evidence: stagingEvidence(nutritionBasis: 'unknown').build(),
            rawBasisText: '100 ml için',
            imageIngredientsUrl: 'https://cdn.example/label.jpg',
          ),
        ],
      );

      expect(row.bucket, BasisEnrichmentBucket.retainedRawBasisTextExact);
      expect(row.hasLabelImage, isTrue, reason: 'capability flag preserved');
    });
  });

  group(
    'classifyBasisEnrichmentCandidate: buckets C-F (image / source-url / '
    'nothing)',
    () {
      test('label image beats a source-url-only bucket (C > E)', () {
        final row = classifyBasisEnrichmentCandidate(
          productId: 'p1',
          productName: 'Product',
          originalBasisBlockerGroup: 'basis_unknown',
          productBarcode: null,
          productSource: null,
          productSourceUrl: 'https://www.migros.com.tr/x-p-abc123',
          productImageUrl: null,
          stagingMatches: [
            BasisEnrichmentStagingRow(
              evidence: stagingEvidence(nutritionBasis: 'unknown').build(),
              imageNutritionUrl: 'https://cdn.example/nutrition.jpg',
            ),
          ],
        );

        expect(row.bucket, BasisEnrichmentBucket.retainedLabelImageAvailable);
      });

      test(
        'ordinary product image only (no label image) -> '
        'RETAINED_PRODUCT_IMAGE_ONLY, beats source-url-only',
        () {
          final row = classifyBasisEnrichmentCandidate(
            productId: 'p1',
            productName: 'Product',
            originalBasisBlockerGroup: 'basis_unknown',
            productBarcode: null,
            productSource: null,
            productSourceUrl: 'https://www.migros.com.tr/x-p-abc123',
            productImageUrl: 'https://cdn.example/front.jpg',
            stagingMatches: const [],
          );

          expect(row.bucket, BasisEnrichmentBucket.retainedProductImageOnly);
        },
      );

      test('only a source URL -> SOURCE_URL_AVAILABLE', () {
        final row = classifyBasisEnrichmentCandidate(
          productId: 'p1',
          productName: 'Product',
          originalBasisBlockerGroup: 'basis_unknown',
          productBarcode: null,
          productSource: 'web_scraper:migros',
          productSourceUrl: 'https://www.migros.com.tr/x-p-abc123',
          productImageUrl: null,
          stagingMatches: const [],
        );

        expect(row.bucket, BasisEnrichmentBucket.sourceUrlAvailable);
      });

      test('nothing retained at all -> NO_USEFUL_RETAINED_SOURCE', () {
        final row = classifyBasisEnrichmentCandidate(
          productId: 'p1',
          productName: 'Product',
          originalBasisBlockerGroup: 'basis_unknown',
          productBarcode: null,
          productSource: null,
          productSourceUrl: null,
          productImageUrl: null,
          stagingMatches: const [],
        );

        expect(row.bucket, BasisEnrichmentBucket.noUsefulRetainedSource);
        expect(row.hasSourceUrl, isFalse);
        expect(row.hasStrictSourceIdentity, isFalse);
      });
    },
  );

  group('classifyBasisEnrichmentCandidate: identity ambiguity fail-closed', () {
    test(
      'two staging rows sharing a source_url but disagreeing on basis '
      'never upgrades evidence — falls back to whatever product-level '
      'signal remains, evidence marked ambiguous',
      () {
        final row = classifyBasisEnrichmentCandidate(
          productId: 'p1',
          productName: 'Product',
          originalBasisBlockerGroup: 'basis_unknown',
          productBarcode: null,
          productSource: null,
          productSourceUrl: 'https://www.migros.com.tr/x-p-abc123',
          productImageUrl: null,
          stagingMatches: [
            BasisEnrichmentStagingRow(
              evidence: stagingEvidence(
                id: 's1',
                nutritionBasis: 'per_100g',
              ).build(),
              rawBasisText: '100 g',
              imageNutritionUrl: 'https://cdn.example/n.jpg',
            ),
            BasisEnrichmentStagingRow(
              evidence: stagingEvidence(
                id: 's2',
                nutritionBasis: 'per_100ml',
              ).build(),
              rawBasisText: '100 ml',
            ),
          ],
        );

        expect(row.identityAmbiguousOrUnusable, isTrue);
        expect(row.hasExactBasisEvidence, isFalse);
        expect(row.hasRawBasisText, isFalse);
        expect(row.hasLabelImage, isFalse);
        expect(row.bucket, BasisEnrichmentBucket.sourceUrlAvailable);
        expect(row.matchedStaging, isTrue);
      },
    );

    test(
      'two staging rows with the SAME evidence signature are not '
      'ambiguous — agreement is fine, evidence still usable',
      () {
        final row = classifyBasisEnrichmentCandidate(
          productId: 'p1',
          productName: 'Product',
          originalBasisBlockerGroup: 'basis_unknown',
          productBarcode: null,
          productSource: null,
          productSourceUrl: 'https://www.migros.com.tr/x-p-abc123',
          productImageUrl: null,
          stagingMatches: [
            BasisEnrichmentStagingRow(
              evidence: stagingEvidence(
                id: 's1',
                nutritionBasis: 'per_100g',
              ).build(),
            ),
            BasisEnrichmentStagingRow(
              evidence: stagingEvidence(
                id: 's2',
                nutritionBasis: 'per_100g',
              ).build(),
            ),
          ],
        );

        expect(row.identityAmbiguousOrUnusable, isFalse);
        expect(row.hasExactBasisEvidence, isTrue);
        expect(row.bucket, BasisEnrichmentBucket.retainedExactBasis);
      },
    );
  });

  group('has_strict_source_identity', () {
    test('a barcode alone grants strict identity', () {
      final row = classifyBasisEnrichmentCandidate(
        productId: 'p1',
        productName: 'Product',
        originalBasisBlockerGroup: 'basis_unknown',
        productBarcode: '8690000000000',
        productSource: null,
        productSourceUrl: null,
        productImageUrl: null,
        stagingMatches: const [],
      );
      expect(row.hasStrictSourceIdentity, isTrue);
    });

    test('an extractable canonical Migros URL identifier grants strict identity', () {
      final row = classifyBasisEnrichmentCandidate(
        productId: 'p1',
        productName: 'Product',
        originalBasisBlockerGroup: 'basis_unknown',
        productBarcode: null,
        productSource: null,
        productSourceUrl: 'https://www.migros.com.tr/some-product-p-xyz789',
        productImageUrl: null,
        stagingMatches: const [],
      );
      expect(row.hasStrictSourceIdentity, isTrue);
    });

    test('a source URL with no extractable identifier and no barcode is not strict', () {
      final row = classifyBasisEnrichmentCandidate(
        productId: 'p1',
        productName: 'Product',
        originalBasisBlockerGroup: 'basis_unknown',
        productBarcode: null,
        productSource: null,
        productSourceUrl: 'https://www.migros.com.tr/some-product-without-id',
        productImageUrl: null,
        stagingMatches: const [],
      );
      expect(row.hasStrictSourceIdentity, isFalse);
      expect(row.hasSourceUrl, isTrue);
    });
  });

  test('toTsvFields produces exactly 14 tab-safe fields in the documented order', () {
    final row = classifyBasisEnrichmentCandidate(
      productId: 'p1',
      productName: 'Product',
      originalBasisBlockerGroup: 'basis_unknown',
      productBarcode: null,
      productSource: 'web_scraper:migros',
      productSourceUrl: 'https://www.migros.com.tr/x-p-abc123',
      productImageUrl: null,
      stagingMatches: const [],
    );

    final fields = row.toTsvFields();
    expect(fields, hasLength(14));
    expect(fields[0], 'p1');
    expect(fields[2], 'basis_unknown');
    expect(fields[3], 'sourceUrlAvailable');
  });
}

/// Tiny builder so tests can construct [LegacyStagingScoringEvidence]
/// without repeating every optional named parameter.
class LegacyStagingScoringEvidenceStub {
  const LegacyStagingScoringEvidenceStub({
    required this.id,
    required this.sourceUrl,
    this.nutritionBasis,
  });

  final String id;
  final String sourceUrl;
  final String? nutritionBasis;
}

extension on LegacyStagingScoringEvidenceStub {
  LegacyStagingScoringEvidence build() {
    return LegacyStagingScoringEvidence(
      id: id,
      sourceUrl: sourceUrl,
      nutritionBasis: nutritionBasis,
    );
  }
}
