import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/scoring/application/legacy_scoring_evidence_recovery.dart'
    show LegacyStagingScoringEvidence;
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_evidence_snapshot.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';

import '../../tool/final_retained_label_basis_ocr_dry_run.dart';
import 'scoring_test_fixtures.dart';

/// Focused tests for tool/final_retained_label_basis_ocr_dry_run.dart —
/// strict basis-text classification, image selection, identity-ambiguity
/// fail-closed behavior, and the dependency-aware nutrition-consistency
/// gate. Uses a fake [OcrProductLabelClient] throughout: no real network,
/// no database, matching how every other network-touching dry-run in this
/// codebase's test suite is faked.
void main() {
  final now = DateTime.utc(2026, 8, 16);

  Product buildProduct({
    String id = 'p1',
    String? barcode = '8690000000000',
    String? sourceUrl = 'https://www.migros.com.tr/some-product-p-abc123',
    ScoringEvidenceSnapshot? scoringEvidence,
  }) {
    return Product(
      id: id,
      barcode: barcode,
      name: 'Test Product',
      source: 'web_scraper:migros',
      sourceUrl: sourceUrl,
      verificationStatus: 'imported',
      scoringEvidence: scoringEvidence,
      createdAt: now,
      updatedAt: now,
    );
  }

  ScoringEvidenceSnapshot trustedEvidence({
    ScoringCategory category = ScoringCategory.generalFood,
  }) {
    final input = completeInput(category: category);
    return ScoringEvidenceSnapshot(
      nutritionBasis: NutritionBasis.unknown,
      nutritionProductState: input.productState,
      nutrition: input.nutrition,
      fvlEvidence: input.fvlEvidence,
      nnsEvidence: input.nnsEvidence,
      ingredientEvidenceCompleteness: input.ingredientEvidenceCompleteness,
      categoryEvidence: input.categoryEvidence,
      classificationFacts: input.classificationFacts,
    );
  }

  LegacyStagingScoringEvidence stagingEvidence({
    String id = 's1',
    String sourceUrl = 'https://www.migros.com.tr/some-product-p-abc123',
  }) {
    return LegacyStagingScoringEvidence(
      id: id,
      sourceUrl: sourceUrl,
      nutritionBasis: null,
    );
  }

  BasisEnrichmentInventoryCandidate candidate({
    String productId = 'p1',
    String group = 'legacy_untrusted_basis',
  }) {
    return BasisEnrichmentInventoryCandidate(
      productId: productId,
      productName: 'Test Product',
      originalBasisBlockerGroup: group,
      inventoryBucket: 'retainedLabelImageAvailable',
    );
  }

  group(
    'classifyOcrEvidenceBasis: consumes the backend\'s structured '
    'evidence_candidates.nutrition_basis, never raw OCR text',
    () {
      test('backend "per100g" is accepted as exact per100g', () {
        final result = classifyOcrEvidenceBasis('per100g');
        expect(result.classification, OcrBasisClassification.per100g);
        expect(result.bothPresent, isFalse);
      });

      test('backend "per100ml" is accepted as exact per100ml', () {
        final result = classifyOcrEvidenceBasis('per100ml');
        expect(result.classification, OcrBasisClassification.per100ml);
      });

      test(
        'backend "both100gAnd100ml" (two separate explicit declarations, '
        'per backend/ocr_service/main.py) -> per100g, bothPresent=true '
        '(official project rule owned by THIS layer, not the backend)',
        () {
          final result = classifyOcrEvidenceBasis('both100gAnd100ml');
          expect(result.classification, OcrBasisClassification.per100g);
          expect(result.bothPresent, isTrue);
        },
      );

      test(
        'backend "unknown" (covers a single combined "100 g / ml" '
        'declaration, among other generic/ambiguous forms) is never exact',
        () {
          final result = classifyOcrEvidenceBasis('unknown');
          expect(result.classification, OcrBasisClassification.generic);
        },
      );

      test('backend "perServing" is never exact', () {
        final result = classifyOcrEvidenceBasis('perServing');
        expect(result.classification, OcrBasisClassification.generic);
      });

      test('absent evidence_candidates (null) is none', () {
        expect(
          classifyOcrEvidenceBasis(null).classification,
          OcrBasisClassification.none,
        );
      });
    },
  );

  group('selectLabelImageCandidates: only the label-image bucket', () {
    test(
      'a retainedProductImageOnly row is never selected — only '
      'retainedLabelImageAvailable rows are processed',
      () {
        const tsv =
            'product_id\tproduct_name\toriginal_basis_blocker_group\tinventory_bucket\n'
            'p1\tA\tbasis_unknown\tretainedLabelImageAvailable\n'
            'p2\tB\tbasis_unknown\tretainedProductImageOnly\n'
            'p3\tC\tlegacy_untrusted_basis\tretainedLabelImageAvailable\n'
            'p4\tD\tbasis_unknown\tsourceUrlAvailable\n';

        final all = parseBasisEnrichmentInventoryTsv(tsv);
        final selected = selectLabelImageCandidates(all);

        expect(all, hasLength(4));
        expect(selected.map((c) => c.productId), ['p1', 'p3']);
        expect(
          selected.any((c) => c.productId == 'p2'),
          isFalse,
          reason: 'a product-image-only candidate must never be selected',
        );
      },
    );
  });

  group(
    'classifyOcrDryRunCandidate: identity, image, OCR, and consistency '
    'gating',
    () {
      test(
        'ambiguous staging identity (disagreeing evidence signatures) is '
        'NOT recoverable — identityUnusable, OCR never even called',
        () async {
          final product = buildProduct(scoringEvidence: trustedEvidence());
          var ocrCallCount = 0;
          final client = _CountingOcrClient(
            () async {
              ocrCallCount++;
              return const OcrProductLabelCallResult(success: true);
            },
          );

          final row = await classifyOcrDryRunCandidate(
            candidate: candidate(),
            product: product,
            stagingMatches: [
              OcrCandidateStagingRow(
                evidence: stagingEvidence(id: 's1'),
                imageNutritionUrl: 'https://cdn.example/n1.jpg',
              ),
              OcrCandidateStagingRow(
                evidence: LegacyStagingScoringEvidence(
                  id: 's2',
                  sourceUrl: 'https://www.migros.com.tr/some-product-p-abc123',
                  nutritionBasis: 'per_100ml', // disagrees -> ambiguous
                ),
                imageNutritionUrl: 'https://cdn.example/n2.jpg',
              ),
            ],
            ocrClient: client,
          );

          expect(row.outcome, OcrDryRunOutcome.identityUnusable);
          expect(row.futureRecoverable, isFalse);
          expect(row.sourceIdentityValid, isFalse);
          expect(ocrCallCount, 0);
        },
      );

      test(
        'no usable nutrition-label image (no image_nutrition_url, no '
        'nutrition_label-role candidate) is NOT recoverable — OCR never '
        'called, image_ingredients_url alone never assumed usable',
        () async {
          final product = buildProduct(scoringEvidence: trustedEvidence());
          var ocrCallCount = 0;
          final client = _CountingOcrClient(() async {
            ocrCallCount++;
            return const OcrProductLabelCallResult(success: true);
          });

          final row = await classifyOcrDryRunCandidate(
            candidate: candidate(),
            product: product,
            stagingMatches: [
              OcrCandidateStagingRow(evidence: stagingEvidence()),
            ],
            ocrClient: client,
          );

          expect(row.outcome, OcrDryRunOutcome.noUsableNutritionImage);
          expect(row.futureRecoverable, isFalse);
          expect(row.sourceIdentityValid, isTrue);
          expect(ocrCallCount, 0);
        },
      );

      test('an OCR request failure is NOT recoverable', () async {
        final product = buildProduct(scoringEvidence: trustedEvidence());
        final client = _CountingOcrClient(
          () async => const OcrProductLabelCallResult(
            success: false,
            errorType: 'http_502',
          ),
        );

        final row = await classifyOcrDryRunCandidate(
          candidate: candidate(),
          product: product,
          stagingMatches: [
            OcrCandidateStagingRow(
              evidence: stagingEvidence(),
              imageNutritionUrl: 'https://cdn.example/n.jpg',
            ),
          ],
          ocrClient: client,
        );

        expect(row.outcome, OcrDryRunOutcome.ocrRequestFailed);
        expect(row.futureRecoverable, isFalse);
        expect(row.diagnosticCode, 'http_502');
      });

      test('an unreadable label (extraction_status=failed) is NOT recoverable', () async {
        final product = buildProduct(scoringEvidence: trustedEvidence());
        final client = _CountingOcrClient(
          () async => const OcrProductLabelCallResult(
            success: true,
            extractionStatus: 'failed',
          ),
        );

        final row = await classifyOcrDryRunCandidate(
          candidate: candidate(),
          product: product,
          stagingMatches: [
            OcrCandidateStagingRow(
              evidence: stagingEvidence(),
              imageNutritionUrl: 'https://cdn.example/n.jpg',
            ),
          ],
          ocrClient: client,
        );

        expect(row.outcome, OcrDryRunOutcome.nutritionLabelUnreadable);
        expect(row.futureRecoverable, isFalse);
      });

      test('a generic/combined basis is NOT recoverable', () async {
        final product = buildProduct(scoringEvidence: trustedEvidence());
        final client = _CountingOcrClient(
          () async => const OcrProductLabelCallResult(
            success: true,
            extractionStatus: 'success',
            evidenceNutritionBasis: 'unknown',
            evidenceNutritionBasisText: '100 g / ml',
          ),
        );

        final row = await classifyOcrDryRunCandidate(
          candidate: candidate(),
          product: product,
          stagingMatches: [
            OcrCandidateStagingRow(
              evidence: stagingEvidence(),
              imageNutritionUrl: 'https://cdn.example/n.jpg',
            ),
          ],
          ocrClient: client,
        );

        expect(row.outcome, OcrDryRunOutcome.genericOrAmbiguousBasis);
        expect(row.futureRecoverable, isFalse);
        expect(row.resolvedExactBasis, isEmpty);
      });

      test(
        'exact basis but OCR provides no usable nutrition values -> '
        'insufficient to verify, NOT recoverable',
        () async {
          final product = buildProduct(scoringEvidence: trustedEvidence());
          final client = _CountingOcrClient(
            () async => const OcrProductLabelCallResult(
              success: true,
              extractionStatus: 'success',
              evidenceNutritionBasis: 'per100g',
              nutrition: {},
            ),
          );

          final row = await classifyOcrDryRunCandidate(
            candidate: candidate(),
            product: product,
            stagingMatches: [
              OcrCandidateStagingRow(
                evidence: stagingEvidence(),
                imageNutritionUrl: 'https://cdn.example/n.jpg',
              ),
            ],
            ocrClient: client,
          );

          expect(
            row.outcome,
            OcrDryRunOutcome.exactBasisButNutritionInsufficientToVerify,
          );
          expect(row.futureRecoverable, isFalse);
          expect(row.resolvedExactBasis, 'per_100g');
        },
      );

      test(
        'exact basis but OCR nutrition values disagree with the persisted '
        'evidence -> mismatch, NOT recoverable',
        () async {
          final product = buildProduct(scoringEvidence: trustedEvidence());
          final client = _CountingOcrClient(
            () async => const OcrProductLabelCallResult(
              success: true,
              extractionStatus: 'success',
              evidenceNutritionBasis: 'per100g',
              nutrition: {
                'energy_kj': 420,
                'saturated_fat': 2,
                'sugars': 40, // stored is 4 — genuine mismatch
                'salt': 0.4,
                'proteins': 6,
                'fiber': 3,
              },
            ),
          );

          final row = await classifyOcrDryRunCandidate(
            candidate: candidate(),
            product: product,
            stagingMatches: [
              OcrCandidateStagingRow(
                evidence: stagingEvidence(),
                imageNutritionUrl: 'https://cdn.example/n.jpg',
              ),
            ],
            ocrClient: client,
          );

          expect(row.outcome, OcrDryRunOutcome.exactBasisButNutritionMismatch);
          expect(row.futureRecoverable, isFalse);
        },
      );

      test(
        'exact basis AND fully consistent nutrition -> recoverable',
        () async {
          final product = buildProduct(scoringEvidence: trustedEvidence());
          final client = _CountingOcrClient(
            () async => const OcrProductLabelCallResult(
              success: true,
              extractionStatus: 'success',
              evidenceNutritionBasis: 'per100g',
              nutrition: {
                'energy_kj': 420,
                'saturated_fat': 2,
                'sugars': 4,
                'salt': 0.4,
                'proteins': 6,
                'fiber': 3,
              },
            ),
          );

          final row = await classifyOcrDryRunCandidate(
            candidate: candidate(),
            product: product,
            stagingMatches: [
              OcrCandidateStagingRow(
                evidence: stagingEvidence(),
                imageNutritionUrl: 'https://cdn.example/n.jpg',
              ),
            ],
            ocrClient: client,
          );

          expect(
            row.outcome,
            OcrDryRunOutcome.exactBasisAndNutritionConsistent,
          );
          expect(row.futureRecoverable, isTrue);
          expect(row.sourceIdentityValid, isTrue);
        },
      );

      test(
        'a nutrition_label-role candidate is used only when the dedicated '
        'image_nutrition_url column is empty, never image_ingredients_url',
        () async {
          final product = buildProduct(scoringEvidence: trustedEvidence());
          final client = _CountingOcrClient(
            () async => const OcrProductLabelCallResult(
              success: true,
              extractionStatus: 'success',
              evidenceNutritionBasis: 'per100g',
            ),
          );

          final row = await classifyOcrDryRunCandidate(
            candidate: candidate(),
            product: product,
            stagingMatches: [
              OcrCandidateStagingRow(
                evidence: stagingEvidence(),
                nutritionLabelRoleCandidateUrl: 'https://cdn.example/role.jpg',
              ),
            ],
            ocrClient: client,
          );

          expect(row.imageKind, ImageKind.nutritionLabelRoleCandidate);
        },
      );

      test('a missing product (not found) is an unexpected error, never crashes', () async {
        final client = _CountingOcrClient(
          () async => const OcrProductLabelCallResult(success: true),
        );

        final row = await classifyOcrDryRunCandidate(
          candidate: candidate(),
          product: null,
          stagingMatches: const [],
          ocrClient: client,
        );

        expect(row.outcome, OcrDryRunOutcome.unexpectedError);
        expect(row.futureRecoverable, isFalse);
      });
    },
  );

  test(
    'no database write path exists: the tool only ever issues GET requests '
    'against Supabase REST tables — the sole POST goes to the OCR Edge '
    'Function, never a table write',
    () {
      final source = File(
        'tool/final_retained_label_basis_ocr_dry_run.dart',
      ).readAsStringSync();

      expect(
        source.contains("'PATCH'"),
        isFalse,
        reason: 'no write HTTP method literal anywhere in this tool',
      );
      expect(
        source.contains("'POST', _uri("),
        isFalse,
        reason: 'no POST is ever issued against a Supabase REST table URI',
      );
      expect(
        source.contains('_client.postUrl(edgeFunctionUri)'),
        isTrue,
        reason:
            'the only POST in the file goes to the OCR Edge Function, not '
            'a database table',
      );
      expect(source.contains("_request('GET'"), isTrue);
    },
  );

  test(
    'OCR basis-evidence contract fix: the tool never reads or classifies '
    "ingredients.raw_text — nutrition basis comes ONLY from the backend's "
    'structured evidence_candidates',
    () {
      final source = File(
        'tool/final_retained_label_basis_ocr_dry_run.dart',
      ).readAsStringSync();

      expect(
        source.contains("ingredients['raw_text']"),
        isFalse,
        reason: 'the CLI must never read the ingredient-side raw_text field',
      );
      expect(
        source.contains("decoded['evidence_candidates']"),
        isTrue,
        reason:
            'basis evidence must be parsed from the structured '
            'evidence_candidates field',
      );
      expect(
        source.contains('classifyOcrEvidenceBasis'),
        isTrue,
        reason:
            'classification must consume the backend structured value, '
            'never re-derive basis from raw OCR text',
      );
    },
  );
}

class _CountingOcrClient implements OcrProductLabelClient {
  _CountingOcrClient(this._respond);
  final Future<OcrProductLabelCallResult> Function() _respond;

  @override
  Future<OcrProductLabelCallResult> extractProductLabel(String imageUrl) {
    return _respond();
  }
}
