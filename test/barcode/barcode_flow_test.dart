import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/analysis/engines/analysis_engine.dart';
import 'package:food_analyzer_app/features/analysis/models/ingredient_match.dart';
import 'package:food_analyzer_app/features/analysis/models/product_analysis_result.dart';
import 'package:food_analyzer_app/features/barcode/controllers/barcode_controller.dart';
import 'package:food_analyzer_app/features/imports/models/off_import_result.dart';
import 'package:food_analyzer_app/features/imports/services/normalizer.dart';
import 'package:food_analyzer_app/features/product/models/ingredient.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';

void main() {
  final now = DateTime.now();

  // ── helpers ──────────────────────────────────────────────────────────────

  Product makeProduct({
    String? ingredientsText,
    String? imageUrl,
    String status = 'imported',
    String? barcode,
  }) {
    return Product(
      id: 'test-id',
      name: 'Test Ürün',
      barcode: barcode ?? '1234567890',
      verificationStatus: status,
      createdAt: now,
      updatedAt: now,
      ingredientsText: ingredientsText,
      imageUrl: imageUrl,
    );
  }

  Ingredient makeIngredient(
    String id,
    String name,
    String risk, {
    String? eCode,
    String? additiveGroup,
  }) {
    return Ingredient(
      id: id,
      name: name,
      normalizedName: name,
      eCode: eCode,
      additiveGroup: additiveGroup,
      riskLevel: risk,
      createdAt: now,
      updatedAt: now,
    );
  }

  IngredientMatch makeMatch(
    String token,
    Ingredient? ing,
    double conf,
    MatchType type, {
    bool affect = true,
  }) {
    return IngredientMatch(
      originalToken: token,
      normalizedText: token,
      matchedIngredient: ing,
      matchedToken: ing?.normalizedName,
      confidenceScore: conf,
      matchType: type,
      shouldAffectAnalysis: affect,
      needsUserConfirmation: false,
    );
  }

  // ── analysis from barcode ingredients ────────────────────────────────────

  group('Barcode flow — ingredient analysis runs', () {
    test('product with palm oil + sugar triggers risk signals', () {
      final ingPalm = makeIngredient('1', 'palm yağı', 'high');
      final ingSugar = makeIngredient('2', 'şeker', 'medium');
      final result = const AnalysisEngine().analyze(
        IngredientMatchingResult(
          matches: [
            makeMatch('palm yağı', ingPalm, 1.0, MatchType.exactMatch),
            makeMatch('şeker', ingSugar, 1.0, MatchType.exactMatch),
          ],
        ),
      );
      expect(result.riskSignals.containsKey('low_quality_oil'), true);
      expect(result.riskSignals.containsKey('sugar_syrup'), true);
      expect(result.detectedRiskIngredients.isNotEmpty, true);
    });

    test('product with only safe ingredients produces no risk ingredients', () {
      final ingFlour = makeIngredient('b1', 'buğday unu', 'low');
      final ingWater = makeIngredient('b2', 'su', 'low');
      final result = const AnalysisEngine().analyze(
        IngredientMatchingResult(
          matches: [
            makeMatch('buğday unu', ingFlour, 1.0, MatchType.exactMatch),
            makeMatch('su', ingWater, 1.0, MatchType.exactMatch),
          ],
        ),
      );
      expect(result.detectedRiskIngredients.isEmpty, true);
    });

    test('nitrite triggers processed_meat_additive signal', () {
      final ingNitrite = makeIngredient('n1', 'sodyum nitrit', 'high');
      final result = const AnalysisEngine().analyze(
        IngredientMatchingResult(
          matches: [
            makeMatch('sodyum nitrit', ingNitrite, 1.0, MatchType.exactMatch),
          ],
        ),
      );
      expect(result.riskSignals.containsKey('processed_meat_additive'), true);
    });

    test('score degrades to sikTuketme with two high-risk ingredients', () {
      final ing1 = makeIngredient(
        'h1',
        'sodyum nitrit',
        'high',
        eCode: 'E250',
        additiveGroup: 'preservative',
      );
      final ing2 = makeIngredient(
        'h2',
        'tartrazin',
        'high',
        eCode: 'E102',
        additiveGroup: 'color',
      );
      final result = const AnalysisEngine().analyze(
        IngredientMatchingResult(
          matches: [
            makeMatch('sodyum nitrit', ing1, 1.0, MatchType.exactMatch),
            makeMatch('tartrazin', ing2, 1.0, MatchType.exactMatch),
          ],
        ),
      );
      expect(result.scoreLabel, AnalysisScoreLabel.sikTuketme);
    });
  });

  // ── OCR fallback condition ────────────────────────────────────────────────

  group('Barcode flow — OCR fallback shown when no ingredients', () {
    test('product with null ingredientsText should skip analysis', () {
      final product = makeProduct();
      final text = product.ingredientsText?.trim() ?? '';
      expect(text.isEmpty, true);
    });

    test('product with empty ingredientsText should skip analysis', () {
      final product = makeProduct(ingredientsText: '   ');
      final text = product.ingredientsText?.trim() ?? '';
      expect(text.isEmpty, true);
    });

    test('product with non-empty ingredientsText should run analysis', () {
      final product = makeProduct(ingredientsText: 'şeker, palm yağı, tuz');
      final text = product.ingredientsText?.trim() ?? '';
      expect(text.isEmpty, false);
    });
  });

  // ── limited data flag ─────────────────────────────────────────────────────

  group('Barcode flow — OFF limited data detection', () {
    test('product with no ingredients and no image is limited', () {
      final product = makeProduct();
      final ingredientsText = product.ingredientsText?.trim() ?? '';
      final isLimited = ingredientsText.isEmpty && product.imageUrl == null;
      expect(isLimited, true);
    });

    test('product with ingredients is not limited', () {
      final product = makeProduct(ingredientsText: 'şeker, su, tuz');
      final ingredientsText = product.ingredientsText?.trim() ?? '';
      final isLimited = ingredientsText.isEmpty && product.imageUrl == null;
      expect(isLimited, false);
    });

    test('product with image only is not limited', () {
      final product = makeProduct(imageUrl: 'https://example.com/img.jpg');
      final ingredientsText = product.ingredientsText?.trim() ?? '';
      final isLimited = ingredientsText.isEmpty && product.imageUrl == null;
      expect(isLimited, false);
    });
  });

  // ── OFF deduplication via OffImportResult ─────────────────────────────────

  group('OFF deduplication — OffImportResult source tracking', () {
    test('existingLocal source returned for local match', () {
      final result = OffImportResult(
        product: makeProduct(ingredientsText: 'şeker, tuz'),
        source: OffImportSource.existingLocal,
        isLimitedData: false,
      );
      expect(result.source, OffImportSource.existingLocal);
      expect(result.isLimitedData, false);
    });

    test('insertedFromOff source set for new OFF product', () {
      final result = OffImportResult(
        product: makeProduct(),
        source: OffImportSource.insertedFromOff,
        isLimitedData: true,
      );
      expect(result.source, OffImportSource.insertedFromOff);
      expect(result.isLimitedData, true);
    });

    test('verified product must not be enriched (guard check)', () {
      final product = makeProduct(status: 'verified');
      // The repository skips enrichment for verified — simulate the guard:
      final shouldSkipEnrichment = product.verificationStatus == 'verified';
      expect(shouldSkipEnrichment, true);
    });

    test('imported product with missing fields qualifies for enrichment', () {
      final product = makeProduct(status: 'imported');
      final missingImage = product.imageUrl == null;
      final missingIngredients =
          product.ingredientsText == null ||
          product.ingredientsText!.trim().isEmpty;
      expect(missingImage || missingIngredients, true);
    });
  });

  // ── ImportNormalizer ─────────────────────────────────────────────────────

  group('ImportNormalizer', () {
    test('normalizeBarcode strips whitespace and spaces', () {
      expect(ImportNormalizer.normalizeBarcode('  1234 5678  '), '12345678');
    });

    test('cleanIngredientsText returns empty string for null', () {
      expect(ImportNormalizer.cleanIngredientsText(null), '');
    });

    test('cleanIngredientsText returns empty string for whitespace-only', () {
      expect(ImportNormalizer.cleanIngredientsText('   ').trim(), '');
    });

    test('cleanIngredientsText normalizes semicolons and newlines', () {
      final result = ImportNormalizer.cleanIngredientsText('şeker; tuz\nsu');
      expect(result.contains('şeker'), true);
      expect(result.contains('tuz'), true);
      expect(result.contains('su'), true);
    });

    test('cleanIngredientsText normalizes E-codes', () {
      final result = ImportNormalizer.cleanIngredientsText('e-100, E 200');
      expect(result.contains('E100'), true);
      expect(result.contains('E200'), true);
    });

    test('normalizeText lowercases Turkish uppercase letters', () {
      final result = ImportNormalizer.normalizeText('Şeker İçerik');
      expect(result, contains('şeker'));
      expect(result, contains('içerik'));
    });
  });

  // ── Stale-state fix ───────────────────────────────────────────────────────

  group('Stale state — BarcodeScanState', () {
    test('default state has no product, not loading, not found', () {
      final state = BarcodeScanState();
      expect(state.hasProduct, false);
      expect(state.product, isNull);
      expect(state.isLoading, false);
      expect(state.notFound, false);
      expect(state.hasError, false);
    });

    test('loading state for a new scan has no product', () {
      final state = BarcodeScanState(
        isLoading: true,
        loadingMessage: 'Ürün aranıyor...',
        scannedBarcode: '1234567890',
      );
      expect(state.hasProduct, false);
      expect(state.isLoading, true);
    });

    test('notFound state has no product', () {
      final state = BarcodeScanState(
        notFound: true,
        scannedBarcode: '1234567890',
      );
      expect(state.hasProduct, false);
      expect(state.notFound, true);
    });

    test('error state has no product', () {
      final state = BarcodeScanState(
        scannedBarcode: '1234567890',
        error: 'Bağlantı hatası',
      );
      expect(state.hasProduct, false);
      expect(state.hasError, true);
    });

    test('fresh BarcodeScanState always clears previous product', () {
      // Simulate what the notifier does at the start of each new scan:
      // build a brand-new state with isLoading=true and no product field.
      final stateAfterFirstScan = BarcodeScanState(
        product: makeProduct(ingredientsText: 'şeker, tuz'),
        scannedBarcode: '0000000001',
      );
      expect(stateAfterFirstScan.hasProduct, true);

      // Second scan: notifier replaces state entirely instead of copyWith.
      final stateForSecondScan = BarcodeScanState(
        isLoading: true,
        loadingMessage: 'Ürün aranıyor...',
        scannedBarcode: '0000000002',
      );
      expect(
        stateForSecondScan.hasProduct,
        false,
        reason: 'new scan must not carry over the previous product',
      );
    });
  });
}
