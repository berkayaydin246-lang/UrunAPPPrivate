import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/admin/repositories/product_staging_approval_repository.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/product_staging/models/product_candidate.dart';

void main() {
  final now = DateTime(2026, 1, 1);

  ProductCandidate stagedPopkek({
    String? barcode = '8690526069906',
    String? name = 'Popkek Bitter Çikolatalı',
    String? brand = 'Eti',
    String? imageFrontUrl = 'https://img/front.jpg',
    String? ingredientsText = 'buğday unu, şeker, kakao, bitkisel yağ, yumurta',
    Map<String, dynamic>? nutritionJson = const {
      'energy_kcal': 424.0,
      'fat': 20.0,
      'saturated_fat': 10.0,
      'sugars': 35.0,
      'proteins': 6.0,
      'salt': 0.8,
    },
    List<String>? categoryTags = const ['en:cakes'],
    List<String>? searchKeywords = const ['popkek', 'cikolata'],
  }) {
    return ProductCandidate(
      id: 'staging-1',
      barcode: barcode,
      name: name,
      brand: brand,
      imageFrontUrl: imageFrontUrl,
      ingredientsText: ingredientsText,
      nutritionJson: nutritionJson,
      categoryTags: categoryTags,
      searchKeywords: searchKeywords,
      source: 'open_food_facts',
      sourceUrl: 'https://tr.openfoodfacts.org/product/8690526069906',
      status: 'pending',
    );
  }

  Product existingProduct({
    String name = 'Existing',
    String? brand,
    String? imageUrl,
    String? ingredientsText,
    String? nutritionText,
    String? source,
    List<String>? categoryTags,
    List<String>? searchKeywords,
    String verificationStatus = 'verified',
  }) {
    return Product(
      id: 'p1',
      barcode: '8690526069906',
      name: name,
      brand: brand,
      imageUrl: imageUrl,
      ingredientsText: ingredientsText,
      nutritionText: nutritionText,
      source: source,
      categoryTags: categoryTags,
      searchKeywords: searchKeywords,
      verificationStatus: verificationStatus,
      createdAt: now,
      updatedAt: now,
    );
  }

  // ── insert map ─────────────────────────────────────────────────────────────

  group('buildProductInsertMap', () {
    test('maps all staged fields to products columns', () {
      final map = ProductStagingApprovalRepository.buildProductInsertMap(
        stagedPopkek(),
        const StagingApprovalEdits(),
      );
      expect(map['barcode'], '8690526069906');
      expect(map['name'], 'Popkek Bitter Çikolatalı');
      expect(map['brand'], 'Eti');
      expect(map['image_url'], 'https://img/front.jpg');
      expect(map['ingredients_text'], contains('buğday unu'));
      expect(map['source'], 'open_food_facts');
      expect(map['verification_status'], 'pending');
      expect(map['category_tags'], ['en:cakes']);
      expect(map['search_keywords'], ['popkek', 'cikolata']);
    });

    test('nutrition_json is encoded into nutrition_text JSON string', () {
      final map = ProductStagingApprovalRepository.buildProductInsertMap(
        stagedPopkek(),
        const StagingApprovalEdits(),
      );
      final nutritionText = map['nutrition_text'] as String;
      final decoded = jsonDecode(nutritionText) as Map<String, dynamic>;
      expect(decoded['energy_kcal'], 424.0);
      expect(decoded['salt'], 0.8);
    });

    test('nutrition survives into a Product → hasNutrition true', () {
      final map = ProductStagingApprovalRepository.buildProductInsertMap(
        stagedPopkek(),
        const StagingApprovalEdits(),
      );
      final product = Product(
        id: 'x',
        name: map['name'] as String,
        nutritionText: map['nutrition_text'] as String?,
        verificationStatus: 'pending',
        createdAt: now,
        updatedAt: now,
      );
      expect(product.hasNutrition, isTrue);
      expect(product.nutrition?.energyKcal, 424.0);
    });

    test('admin edits override staged values', () {
      final map = ProductStagingApprovalRepository.buildProductInsertMap(
        stagedPopkek(),
        const StagingApprovalEdits(
          name: 'Düzeltilmiş Ad',
          brand: 'Yeni Marka',
          ingredientsText: 'düzeltilmiş içerik metni uzun',
        ),
      );
      expect(map['name'], 'Düzeltilmiş Ad');
      expect(map['brand'], 'Yeni Marka');
      expect(map['ingredients_text'], 'düzeltilmiş içerik metni uzun');
    });

    test('falls back to İsimsiz Ürün when no name', () {
      final map = ProductStagingApprovalRepository.buildProductInsertMap(
        stagedPopkek(name: null),
        const StagingApprovalEdits(),
      );
      expect(map['name'], 'İsimsiz Ürün');
    });

    test('null/empty optional fields are dropped', () {
      final map = ProductStagingApprovalRepository.buildProductInsertMap(
        stagedPopkek(
          brand: null,
          imageFrontUrl: null,
          ingredientsText: null,
          nutritionJson: null,
          categoryTags: null,
          searchKeywords: null,
        ),
        const StagingApprovalEdits(),
      );
      expect(map.containsKey('brand'), isFalse);
      expect(map.containsKey('image_url'), isFalse);
      expect(map.containsKey('ingredients_text'), isFalse);
      expect(map.containsKey('nutrition_text'), isFalse);
      expect(map.containsKey('category_tags'), isFalse);
    });
  });

  // ── enrich patch ─────────────────────────────────────────────────────────

  group('buildProductEnrichPatch', () {
    test('fills missing fields on an empty existing product', () {
      final patch = ProductStagingApprovalRepository.buildProductEnrichPatch(
        existingProduct(name: 'Old', brand: null, imageUrl: null),
        stagedPopkek(),
        const StagingApprovalEdits(),
      );
      expect(patch['brand'], 'Eti');
      expect(patch['image_url'], 'https://img/front.jpg');
      expect(patch['ingredients_text'], contains('buğday unu'));
      expect(patch.containsKey('nutrition_text'), isTrue);
      expect(patch['category_tags'], ['en:cakes']);
    });

    test('does NOT overwrite existing non-null fields', () {
      final patch = ProductStagingApprovalRepository.buildProductEnrichPatch(
        existingProduct(
          name: 'Verified Name',
          brand: 'Verified Brand',
          imageUrl: 'https://verified/img.jpg',
          ingredientsText: 'verified ingredients',
          nutritionText: '{"energy_kcal":100.0}',
          source: 'manual',
          categoryTags: ['en:verified'],
          searchKeywords: ['verified'],
        ),
        stagedPopkek(),
        const StagingApprovalEdits(),
      );
      // Nothing should be overwritten → empty patch.
      expect(patch, isEmpty);
    });

    test('fills nutrition only when existing nutrition_text is null', () {
      final patch = ProductStagingApprovalRepository.buildProductEnrichPatch(
        existingProduct(
          name: 'Name',
          brand: 'Brand',
          imageUrl: 'img',
          ingredientsText: 'ing',
          nutritionText: null, // missing
          source: 'x',
          categoryTags: ['t'],
          searchKeywords: ['k'],
        ),
        stagedPopkek(),
        const StagingApprovalEdits(),
      );
      expect(patch.keys, ['nutrition_text']);
      final decoded =
          jsonDecode(patch['nutrition_text'] as String) as Map<String, dynamic>;
      expect(decoded['energy_kcal'], 424.0);
    });

    test('empty existing name is refilled', () {
      final patch = ProductStagingApprovalRepository.buildProductEnrichPatch(
        existingProduct(name: '   '),
        stagedPopkek(),
        const StagingApprovalEdits(),
      );
      expect(patch['name'], 'Popkek Bitter Çikolatalı');
    });
  });

  // ── result enum ────────────────────────────────────────────────────────────

  group('ApproveStagedResult', () {
    test('has all expected values', () {
      expect(ApproveStagedResult.values, hasLength(13));
      expect(
        ApproveStagedResult.values,
        containsAll([
          ApproveStagedResult.approved,
          ApproveStagedResult.updatedExisting,
          ApproveStagedResult.notFound,
          ApproveStagedResult.invalidBarcode,
          ApproveStagedResult.alreadyProcessed,
          ApproveStagedResult.productSavedStagingFailed,
          ApproveStagedResult.insufficientData,
          ApproveStagedResult.missingBrand,
          ApproveStagedResult.missingImage,
          ApproveStagedResult.missingIngredients,
          ApproveStagedResult.missingNutrition,
          ApproveStagedResult.missingSourceLink,
          ApproveStagedResult.autoRejectedNoAnalysisData,
        ]),
      );
    });
  });

  group('buildStagingApprovalUpdateMap', () {
    test('sets approved status and updated_at and keeps admin note', () {
      final now = DateTime.utc(2026, 6, 4, 10, 30, 0);
      final patch =
          ProductStagingApprovalRepository.buildStagingApprovalUpdateMap(
            adminNote: 'manual check ok',
            categorySuggestion: 'atistirmalik',
            now: now,
          );

      expect(patch['status'], 'approved');
      expect(patch['updated_at'], now.toIso8601String());
      expect(patch['admin_notes'], 'manual check ok');
      expect(patch['category_suggestion'], 'atistirmalik');
    });
  });

  // ── no-barcode approval eligibility ─────────────────────────────────────────

  ProductCandidate webScraped({
    String? barcode,
    String? name = 'Namet Macar Salam Kg',
    String? brand = 'Namet',
    String? imageFrontUrl = 'https://img/namet-front.jpg',
    String? ingredientsText = 'dana eti, baharat, tuz, su, nişasta',
    Map<String, dynamic>? nutritionJson = const {
      'energy_kcal': 248.0,
      'fat': 20.0,
      'proteins': 11.0,
      'salt': 2.0,
    },
    String? sourceUrl =
        'https://www.migros.com.tr/namet-macar-salam-kg-p-d749ff',
    int qualityScore = 100,
    String source = 'web_scraper:migros',
  }) {
    return ProductCandidate(
      id: 'staging-web-1',
      barcode: barcode,
      name: name,
      brand: brand,
      imageFrontUrl: imageFrontUrl,
      ingredientsText: ingredientsText,
      nutritionJson: nutritionJson,
      source: source,
      sourceUrl: sourceUrl,
      qualityScore: qualityScore,
      status: 'pending',
    );
  }

  group('approvalBlockReason', () {
    const noEdits = StagingApprovalEdits();

    test('barcode + complete data → approval allowed (null)', () {
      expect(
        ProductStagingApprovalRepository.approvalBlockReason(
          stagedPopkek(),
          noEdits,
        ),
        isNull,
      );
    });

    test(
      'web_scraper without barcode but complete → approval allowed (null)',
      () {
        expect(
          ProductStagingApprovalRepository.approvalBlockReason(
            webScraped(),
            noEdits,
          ),
          isNull,
        );
      },
    );

    test('web_scraper without barcode and without source_url → blocked', () {
      expect(
        ProductStagingApprovalRepository.approvalBlockReason(
          webScraped(sourceUrl: null),
          noEdits,
        ),
        ApproveStagedResult.missingSourceLink,
      );
    });

    // ── partial-data approval: missing optional fields must NOT block ─────────

    test(
      'T1: name + source_url + image + ingredients but no nutrition → allowed',
      () {
        expect(
          ProductStagingApprovalRepository.approvalBlockReason(
            webScraped(nutritionJson: null),
            noEdits,
          ),
          isNull,
          reason: 'missing nutrition must NOT block manual approval',
        );
      },
    );

    test(
      'T2: name + source_url + image but no ingredients and no nutrition → allowed',
      () {
        expect(
          ProductStagingApprovalRepository.approvalBlockReason(
            webScraped(ingredientsText: null, nutritionJson: null),
            noEdits,
          ),
          isNull,
          reason:
              'missing ingredients AND nutrition must NOT block manual approval',
        );
      },
    );

    test(
      'T2b: name + source_url only (no image, no ingredients, no nutrition) → allowed',
      () {
        expect(
          ProductStagingApprovalRepository.approvalBlockReason(
            webScraped(
              imageFrontUrl: null,
              ingredientsText: null,
              nutritionJson: null,
            ),
            noEdits,
          ),
          isNull,
          reason:
              'missing image + ingredients + nutrition must NOT block when name + source_url exist',
        );
      },
    );

    test('T11: missing ingredients alone does NOT block approval', () {
      expect(
        ProductStagingApprovalRepository.approvalBlockReason(
          webScraped(ingredientsText: null),
          noEdits,
        ),
        isNull,
      );
    });

    test('T11b: missing nutrition alone does NOT block approval', () {
      expect(
        ProductStagingApprovalRepository.approvalBlockReason(
          webScraped(nutritionJson: null),
          noEdits,
        ),
        isNull,
      );
    });

    test('T11c: missing image alone does NOT block approval', () {
      expect(
        ProductStagingApprovalRepository.approvalBlockReason(
          webScraped(imageFrontUrl: null),
          noEdits,
        ),
        isNull,
      );
    });

    test('T11d: missing brand alone does NOT block approval', () {
      expect(
        ProductStagingApprovalRepository.approvalBlockReason(
          webScraped(brand: null),
          noEdits,
        ),
        isNull,
      );
    });

    test('low quality_score alone does NOT block manual approval', () {
      expect(
        ProductStagingApprovalRepository.approvalBlockReason(
          webScraped(qualityScore: 63),
          noEdits,
        ),
        isNull,
      );
    });

    test('name missing → blocked with insufficientData', () {
      expect(
        ProductStagingApprovalRepository.approvalBlockReason(
          webScraped(name: null),
          noEdits,
        ),
        ApproveStagedResult.insufficientData,
      );
    });

    test('admin edits supply missing brand → approval still allowed', () {
      expect(
        ProductStagingApprovalRepository.approvalBlockReason(
          webScraped(brand: null, qualityScore: 63),
          const StagingApprovalEdits(brand: 'Gedik'),
        ),
        isNull,
      );
    });

    test('stale missing_fields do not block when value is now filled', () {
      final candidate = ProductCandidate(
        id: 'staging-stale',
        barcode: null,
        name: 'Gedik Piliç Baget 1 Kg',
        brand: 'Gedik',
        imageFrontUrl: 'https://img/gedik.jpg',
        ingredientsText: 'piliç eti, tuz, baharat, su',
        nutritionJson: const {'energy_kcal': 180.0, 'proteins': 19.0},
        source: 'web_scraper:migros',
        sourceUrl: 'https://www.migros.com.tr/gedik-pilic-baget-p-d70001',
        qualityScore: 63,
        missingFields: const ['brand'],
        status: 'pending',
      );
      expect(
        ProductStagingApprovalRepository.approvalBlockReason(
          candidate,
          noEdits,
        ),
        isNull,
      );
    });

    test('T12: existing complete product approval (barcode) still works', () {
      expect(
        ProductStagingApprovalRepository.approvalBlockReason(
          stagedPopkek(),
          noEdits,
        ),
        isNull,
        reason: 'existing full-data approval must be unaffected',
      );
    });

    test('barcode-based source without barcode still requires one', () {
      expect(
        ProductStagingApprovalRepository.approvalBlockReason(
          stagedPopkek(barcode: null),
          noEdits,
        ),
        ApproveStagedResult.invalidBarcode,
      );
    });

    test('sourceAllowsNoBarcode: web_scraper:* and manual_seed only', () {
      expect(
        ProductStagingApprovalRepository.sourceAllowsNoBarcode(
          'web_scraper:migros',
        ),
        isTrue,
      );
      expect(
        ProductStagingApprovalRepository.sourceAllowsNoBarcode('manual_seed'),
        isTrue,
      );
      expect(
        ProductStagingApprovalRepository.sourceAllowsNoBarcode(
          'open_food_facts',
        ),
        isFalse,
      );
    });
  });

  // ── approvalWarnings ────────────────────────────────────────────────────────

  group('approvalWarnings', () {
    const noEdits = StagingApprovalEdits();

    test('complete product → no warnings', () {
      expect(
        ProductStagingApprovalRepository.approvalWarnings(
          webScraped(),
          noEdits,
        ),
        isEmpty,
      );
    });

    test('missing nutrition → missingNutrition warning (not a block)', () {
      final warnings = ProductStagingApprovalRepository.approvalWarnings(
        webScraped(nutritionJson: null),
        noEdits,
      );
      expect(warnings, contains(ApproveStagedResult.missingNutrition));
      // Approval is still allowed
      expect(
        ProductStagingApprovalRepository.approvalBlockReason(
          webScraped(nutritionJson: null),
          noEdits,
        ),
        isNull,
      );
    });

    test('missing ingredients → missingIngredients warning (not a block)', () {
      final warnings = ProductStagingApprovalRepository.approvalWarnings(
        webScraped(ingredientsText: null),
        noEdits,
      );
      expect(warnings, contains(ApproveStagedResult.missingIngredients));
    });

    test('missing image → missingImage warning (not a block)', () {
      final warnings = ProductStagingApprovalRepository.approvalWarnings(
        webScraped(imageFrontUrl: null),
        noEdits,
      );
      expect(warnings, contains(ApproveStagedResult.missingImage));
    });

    test('missing brand → missingBrand warning (not a block)', () {
      final warnings = ProductStagingApprovalRepository.approvalWarnings(
        webScraped(brand: null),
        noEdits,
      );
      expect(warnings, contains(ApproveStagedResult.missingBrand));
    });

    test(
      'all recommended fields missing → four warnings, approval still OK',
      () {
        final candidate = webScraped(
          brand: null,
          imageFrontUrl: null,
          ingredientsText: null,
          nutritionJson: null,
        );
        final warnings = ProductStagingApprovalRepository.approvalWarnings(
          candidate,
          noEdits,
        );
        expect(
          warnings,
          containsAll([
            ApproveStagedResult.missingBrand,
            ApproveStagedResult.missingImage,
            ApproveStagedResult.missingIngredients,
            ApproveStagedResult.missingNutrition,
          ]),
        );
        // Hard blocker is still null — admin can approve
        expect(
          ProductStagingApprovalRepository.approvalBlockReason(
            candidate,
            noEdits,
          ),
          isNull,
        );
      },
    );

    test(
      'admin edits filling ingredients clears missingIngredients warning',
      () {
        final warnings = ProductStagingApprovalRepository.approvalWarnings(
          webScraped(ingredientsText: null),
          const StagingApprovalEdits(
            ingredientsText: 'buğday unu, şeker, kakao',
          ),
        );
        expect(
          warnings,
          isNot(contains(ApproveStagedResult.missingIngredients)),
        );
      },
    );
  });

  group('buildProductInsertMap (no-barcode web product)', () {
    test('barcode stays null and source_url is set for dedupe', () {
      final map = ProductStagingApprovalRepository.buildProductInsertMap(
        webScraped(),
        const StagingApprovalEdits(),
      );
      expect(map['barcode'], isNull);
      expect(
        map['source_url'],
        'https://www.migros.com.tr/namet-macar-salam-kg-p-d749ff',
      );
      expect(map['name'], 'Namet Macar Salam Kg');
      expect(map['source'], 'web_scraper:migros');
    });
  });

  group('isSuspiciousIngredients', () {
    test('real ingredient list passes', () {
      expect(
        ProductStagingApprovalRepository.isSuspiciousIngredients(
          'Dana eti, baharat karışımı, tuz, su, patates nişastası',
        ),
        isFalse,
      );
    });

    test('short / empty / net-amount / nutrition-mixed are suspicious', () {
      expect(
        ProductStagingApprovalRepository.isSuspiciousIngredients('Hindi eti'),
        isTrue,
      );
      expect(
        ProductStagingApprovalRepository.isSuspiciousIngredients(null),
        isTrue,
      );
      expect(
        ProductStagingApprovalRepository.isSuspiciousIngredients(
          'Net Miktar 300 g paket',
        ),
        isTrue,
      );
      expect(
        ProductStagingApprovalRepository.isSuspiciousIngredients(
          'Besin Değerleri Enerji 248 kcal Yağ 20 g',
        ),
        isTrue,
      );
    });

    test('suspicious ingredients do NOT block manual approval', () {
      // Warning only — admin reviews/corrects and approval stays possible.
      expect(
        ProductStagingApprovalRepository.approvalBlockReason(
          webScraped(
            ingredientsText: 'Piliç eti baharat tuz su nişasta sebze',
            qualityScore: 63,
          ),
          const StagingApprovalEdits(),
        ),
        isNull,
      );
    });
  });

  // ── partial-product insert map ──────────────────────────────────────────────

  group('partial product data (T3, T4, T8, T9)', () {
    test(
      'T3: missing nutrition → nutrition_text is absent from insert map (no zeros)',
      () {
        final map = ProductStagingApprovalRepository.buildProductInsertMap(
          webScraped(nutritionJson: null),
          const StagingApprovalEdits(),
        );
        expect(
          map.containsKey('nutrition_text'),
          isFalse,
          reason:
              'null nutrition must be absent from insert map, not encoded as zeros',
        );
      },
    );

    test('T3b: nutrition_text is never a zero-filled JSON', () {
      final map = ProductStagingApprovalRepository.buildProductInsertMap(
        webScraped(nutritionJson: null),
        const StagingApprovalEdits(),
      );
      // If somehow present, it must not contain zero placeholders
      if (map.containsKey('nutrition_text')) {
        final text = map['nutrition_text'] as String;
        expect(text, isNot(contains('"energy_kcal":0')));
        expect(text, isNot(contains('"fat":0')));
      }
    });

    test(
      'T4: missing ingredients → ingredients_text is absent from insert map',
      () {
        final map = ProductStagingApprovalRepository.buildProductInsertMap(
          webScraped(ingredientsText: null),
          const StagingApprovalEdits(),
        );
        expect(
          map.containsKey('ingredients_text'),
          isFalse,
          reason: 'null ingredients must be absent, not fake text',
        );
      },
    );

    test(
      'T4b: admin leaving ingredients empty → not inserted as empty string',
      () {
        final map = ProductStagingApprovalRepository.buildProductInsertMap(
          webScraped(ingredientsText: null),
          const StagingApprovalEdits(ingredientsText: ''),
        );
        // Empty admin edit for ingredients → treated as null → not in map
        expect(map.containsKey('ingredients_text'), isFalse);
      },
    );

    test('T8: Product.hasNutrition is false when nutritionText is null', () {
      final product = Product(
        id: 'p-partial',
        name: 'Partial Ürün',
        nutritionText: null,
        verificationStatus: 'pending',
        createdAt: now,
        updatedAt: now,
      );
      expect(
        product.hasNutrition,
        isFalse,
        reason: 'null nutrition_text → hasNutrition false (no score guessing)',
      );
      expect(product.nutrition, isNull);
    });

    test(
      'T9: Product.hasIngredients is false when ingredientsText is null',
      () {
        final product = Product(
          id: 'p-partial',
          name: 'Partial Ürün',
          ingredientsText: null,
          verificationStatus: 'pending',
          createdAt: now,
          updatedAt: now,
        );
        expect(
          product.hasIngredients,
          isFalse,
          reason: 'null ingredients_text → hasIngredients false',
        );
      },
    );

    test(
      'T9b: Product.hasIngredients is false when ingredientsText is too short',
      () {
        final product = Product(
          id: 'p-partial',
          name: 'Partial Ürün',
          ingredientsText: 'su',
          verificationStatus: 'pending',
          createdAt: now,
          updatedAt: now,
        );
        expect(product.hasIngredients, isFalse);
      },
    );

    test(
      'T10: partial product (null nutrition + null ingredients) insert map has name and source_url',
      () {
        final map = ProductStagingApprovalRepository.buildProductInsertMap(
          webScraped(ingredientsText: null, nutritionJson: null),
          const StagingApprovalEdits(),
        );
        expect(map['name'], 'Namet Macar Salam Kg');
        expect(
          map['source_url'],
          'https://www.migros.com.tr/namet-macar-salam-kg-p-d749ff',
        );
        expect(map.containsKey('nutrition_text'), isFalse);
        expect(map.containsKey('ingredients_text'), isFalse);
        expect(map['verification_status'], 'pending');
      },
    );

    test(
      'T3c: missing nutrition with full ingredients → nutrition_text absent, ingredients present',
      () {
        final map = ProductStagingApprovalRepository.buildProductInsertMap(
          webScraped(nutritionJson: null),
          const StagingApprovalEdits(),
        );
        expect(map.containsKey('nutrition_text'), isFalse);
        expect(map.containsKey('ingredients_text'), isTrue);
      },
    );

    test(
      'T5/T6/T7: Product helpers reflect missing state for badges and detail',
      () {
        final withIngNoNutrition = Product(
          id: 'p1',
          name: 'Ürün',
          ingredientsText:
              'buğday unu, şeker, kakao, bitkisel yağ, yumurta, süt',
          nutritionText: null,
          verificationStatus: 'pending',
          createdAt: now,
          updatedAt: now,
        );
        // Card badge logic: hasIngredients=true, hasNutrition=false
        expect(withIngNoNutrition.hasIngredients, isTrue);
        expect(withIngNoNutrition.hasNutrition, isFalse);

        final withNutrNoIng = Product(
          id: 'p2',
          name: 'Ürün 2',
          ingredientsText: null,
          nutritionText: '{"energy_kcal":200.0,"fat":5.0}',
          verificationStatus: 'pending',
          createdAt: now,
          updatedAt: now,
        );
        // Card badge logic: hasIngredients=false, hasNutrition=true
        expect(withNutrNoIng.hasIngredients, isFalse);
        expect(withNutrNoIng.hasNutrition, isTrue);

        final withNeither = Product(
          id: 'p3',
          name: 'Ürün 3',
          ingredientsText: null,
          nutritionText: null,
          verificationStatus: 'pending',
          createdAt: now,
          updatedAt: now,
        );
        // Card badge logic: both missing → both "yok" badges
        expect(withNeither.hasIngredients, isFalse);
        expect(withNeither.hasNutrition, isFalse);
      },
    );
  });

  // ── auto-reject: no analysis data ──────────────────────────────────────────

  group('shouldAutoRejectForNoAnalysisData', () {
    test(
      'missing nutrition only → NOT auto-rejected (approval still allowed)',
      () {
        final candidate = webScraped(nutritionJson: null);
        expect(
          ProductStagingApprovalRepository.shouldAutoRejectForNoAnalysisData(
            candidate,
          ),
          isFalse,
          reason: 'missing only nutrition must NOT trigger auto-reject',
        );
      },
    );

    test(
      'missing ingredients only → NOT auto-rejected (approval still allowed)',
      () {
        final candidate = webScraped(ingredientsText: null);
        expect(
          ProductStagingApprovalRepository.shouldAutoRejectForNoAnalysisData(
            candidate,
          ),
          isFalse,
          reason: 'missing only ingredients must NOT trigger auto-reject',
        );
      },
    );

    test('missing BOTH ingredients and nutrition → auto-rejected', () {
      final candidate = webScraped(ingredientsText: null, nutritionJson: null);
      expect(
        ProductStagingApprovalRepository.shouldAutoRejectForNoAnalysisData(
          candidate,
        ),
        isTrue,
        reason: 'missing both must trigger auto-reject',
      );
    });

    test('complete product is never auto-rejected', () {
      expect(
        ProductStagingApprovalRepository.shouldAutoRejectForNoAnalysisData(
          webScraped(),
        ),
        isFalse,
      );
    });

    test(
      'missing both → insert map does NOT include nutrition or ingredients',
      () {
        final map = ProductStagingApprovalRepository.buildProductInsertMap(
          webScraped(ingredientsText: null, nutritionJson: null),
          const StagingApprovalEdits(),
        );
        expect(map.containsKey('nutrition_text'), isFalse);
        expect(map.containsKey('ingredients_text'), isFalse);
        expect(map['name'], isNotNull);
        expect(map['source_url'], isNotNull);
      },
    );

    test('hasMissingIngredients: null text → true', () {
      expect(
        ProductStagingApprovalRepository.hasMissingIngredients(
          webScraped(ingredientsText: null),
        ),
        isTrue,
      );
    });

    test('hasMissingIngredients: non-empty text → false', () {
      expect(
        ProductStagingApprovalRepository.hasMissingIngredients(webScraped()),
        isFalse,
      );
    });

    test('hasMissingNutrition: null json → true', () {
      expect(
        ProductStagingApprovalRepository.hasMissingNutrition(
          webScraped(nutritionJson: null),
        ),
        isTrue,
      );
    });

    test('hasMissingNutrition: non-empty json → false', () {
      expect(
        ProductStagingApprovalRepository.hasMissingNutrition(webScraped()),
        isFalse,
      );
    });

    test('ProductCandidate.hasNoAnalysisData matches helper', () {
      final candidate = webScraped(ingredientsText: null, nutritionJson: null);
      expect(candidate.hasNoAnalysisData, isTrue);
      expect(candidate.hasMissingIngredients, isTrue);
      expect(candidate.hasMissingNutrition, isTrue);
    });

    test('autoRejectedNoAnalysisData is not stagingWasApproved', () {
      expect(
        ApproveStagedResult.autoRejectedNoAnalysisData.stagingWasApproved,
        isFalse,
      );
    });
  });

  // ── image field round-trip (T8–T12) ──────────────────────────────────────
  // image_front_url is the primary staging column.
  // image_url is a compatibility alias (kept in sync by the scraper).
  // displayImageUrl = imageFrontUrl ?? imageUrl (used by admin UI and approval).

  group('staging image field (T8–T12)', () {
    const cdnUrl =
        'https://images.migrosone.com/sanalmarket/product/5039483/5039483-26169b-1650x1650.jpg';
    const aliasUrl =
        'https://images.migrosone.com/sanalmarket/product/5039483/alias.jpg';

    // T8: fromJson reads image_front_url into imageFrontUrl (spec item 1).
    test('T8: fromJson reads image_front_url → imageFrontUrl', () {
      final json = {
        'id': 'staging-img-1',
        'name': 'Mutlu Spagetti Makarna 500 G',
        'brand': 'Mutlu',
        'source': 'web_scraper:migros',
        'status': 'pending',
        'image_front_url': cdnUrl,
      };
      final candidate = ProductCandidate.fromJson(json);
      expect(candidate.imageFrontUrl, cdnUrl);
    });

    // T8b: image_url is parsed into the separate imageUrl field.
    test('T8b: fromJson reads image_url → imageUrl field', () {
      final json = {
        'id': 'staging-img-2',
        'source': 'web_scraper:migros',
        'status': 'pending',
        'image_url': aliasUrl,
      };
      final candidate = ProductCandidate.fromJson(json);
      expect(candidate.imageUrl, aliasUrl);
      expect(candidate.imageFrontUrl, isNull);
    });

    // T8c: displayImageUrl prefers imageFrontUrl over imageUrl (spec item 2).
    test('T8c: displayImageUrl prefers image_front_url over image_url', () {
      final json = {
        'id': 'staging-img-3',
        'source': 'web_scraper:migros',
        'status': 'pending',
        'image_front_url': cdnUrl,
        'image_url': aliasUrl,
      };
      final candidate = ProductCandidate.fromJson(json);
      expect(candidate.imageFrontUrl, cdnUrl);
      expect(candidate.imageUrl, aliasUrl);
      expect(
        candidate.displayImageUrl,
        cdnUrl,
        reason: 'image_front_url must take priority over image_url',
      );
    });

    // T8d: displayImageUrl falls back to imageUrl when imageFrontUrl is null.
    test(
      'T8d: displayImageUrl falls back to image_url when image_front_url absent',
      () {
        final json = {
          'id': 'staging-img-4',
          'source': 'web_scraper:migros',
          'status': 'pending',
          'image_url': aliasUrl,
        };
        final candidate = ProductCandidate.fromJson(json);
        expect(candidate.displayImageUrl, aliasUrl);
      },
    );

    // T8e: placeholder (null) only when both fields absent (spec item 5).
    test('T8e: displayImageUrl is null when both image fields are absent', () {
      final json = {
        'id': 'staging-img-5',
        'source': 'web_scraper:migros',
        'status': 'pending',
        'image_front_url': null,
        'image_url': null,
      };
      final candidate = ProductCandidate.fromJson(json);
      expect(candidate.displayImageUrl, isNull);
    });

    // T9: toStagingInsertMap writes image_front_url (primary) and image_url (alias).
    test('T9: toStagingInsertMap includes image_front_url and image_url', () {
      final candidate = webScraped(imageFrontUrl: cdnUrl);
      final map = candidate.toStagingInsertMap();
      expect(
        map['image_front_url'],
        cdnUrl,
        reason: 'image_front_url is the primary staging column',
      );
      expect(
        map['image_url'],
        cdnUrl,
        reason: 'image_url is the compatibility alias',
      );
    });

    // T10: toStagingInsertMap omits both image fields when imageFrontUrl is null.
    test(
      'T10: toStagingInsertMap omits image fields when imageFrontUrl is null',
      () {
        final candidate = webScraped(imageFrontUrl: null);
        final map = candidate.toStagingInsertMap();
        expect(map.containsKey('image_front_url'), isFalse);
        expect(map.containsKey('image_url'), isFalse);
      },
    );

    // T11: manual approval maps image_front_url → products.image_url (spec item 7).
    test(
      'T11: buildProductInsertMap maps image_front_url to products.image_url',
      () {
        final map = ProductStagingApprovalRepository.buildProductInsertMap(
          webScraped(imageFrontUrl: cdnUrl),
          const StagingApprovalEdits(),
        );
        expect(
          map['image_url'],
          cdnUrl,
          reason: 'staging.image_front_url must map to products.image_url',
        );
      },
    );

    // T11b: image_url alias is used as fallback when imageFrontUrl is null (spec item 8).
    test(
      'T11b: buildProductInsertMap uses image_url alias when image_front_url absent',
      () {
        final candidate = ProductCandidate.fromJson({
          'source': 'web_scraper:migros',
          'status': 'pending',
          'image_url': aliasUrl,
        });
        final map = ProductStagingApprovalRepository.buildProductInsertMap(
          candidate,
          const StagingApprovalEdits(),
        );
        expect(
          map['image_url'],
          aliasUrl,
          reason: 'displayImageUrl fallback must reach products.image_url',
        );
      },
    );

    // T12: buildProductInsertMap omits image_url when both image fields are null.
    test(
      'T12: buildProductInsertMap omits image_url when both image fields null',
      () {
        final map = ProductStagingApprovalRepository.buildProductInsertMap(
          webScraped(imageFrontUrl: null),
          const StagingApprovalEdits(),
        );
        expect(map.containsKey('image_url'), isFalse);
      },
    );
  });
}
