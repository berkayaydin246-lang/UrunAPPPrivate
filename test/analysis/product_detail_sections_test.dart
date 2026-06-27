import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/analysis/models/product_analysis_result.dart';
import 'package:food_analyzer_app/features/analysis/services/ingredient_canonicalizer.dart';
import 'package:food_analyzer_app/features/analysis/widgets/analysis_result_widget.dart';
import 'package:food_analyzer_app/features/product/models/ingredient.dart';

void main() {
  final now = DateTime(2026, 1, 1);

  Ingredient ingredient(
    String id,
    String name,
    String riskLevel, {
    String? type,
    String? purpose,
    String? riskSummary,
  }) {
    return Ingredient(
      id: id,
      name: name,
      normalizedName: name.toLowerCase(),
      riskLevel: riskLevel,
      ingredientType: type,
      shortPurpose: purpose,
      shortRiskSummary: riskSummary,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Build a barcode-mode result whose ingredients come from parsed tokens
  /// (the realistic OFF/approved-product path), plus optional DB ingredients.
  ProductAnalysisResult barcodeResult({
    List<String> parsedTokens = const [],
    List<Ingredient> recognized = const [],
    List<String> allergenTokens = const [],
  }) {
    return ProductAnalysisResult(
      scoreLabel: AnalysisScoreLabel.orta,
      summary: '',
      recognizedIngredients: recognized,
      unknownIngredients: parsedTokens,
      allergenTokens: allergenTokens,
    );
  }

  Future<void> pumpBarcode(
    WidgetTester tester,
    ProductAnalysisResult result,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Center(
              child: SizedBox(
                width: 360,
                child: AnalysisResultWidget(
                  result: result,
                  displayMode: AnalysisDisplayMode.barcode,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // ── Popkek ────────────────────────────────────────────────────────────────

  group('Popkek-style product', () {
    const popkekTokens = [
      'buğday unu',
      'şeker',
      'palm yağı',
      'yumurta',
      'sorbitol',
      'tuz',
      'invert şeker şurubu',
      'sodyum asit pirofosfat',
      'gliserol',
      'lesitin',
      'kakao tozu',
      'sitrik asit',
      'ksantan gam',
      'modifiye nişasta',
      'kıvam arttırıcı',
    ];

    testWidgets('renders the "Dikkat Edilecek İçerikler" section', (
      tester,
    ) async {
      await pumpBarcode(tester, barcodeResult(parsedTokens: popkekTokens));
      expect(find.text('Dikkat Edilecek İçerikler'), findsOneWidget);
    });

    testWidgets('main section contains palm, sugar, syrup, salt items', (
      tester,
    ) async {
      await pumpBarcode(tester, barcodeResult(parsedTokens: popkekTokens));
      expect(find.textContaining('Palm'), findsWidgets);
      expect(find.textContaining('Şeker'), findsWidgets);
      expect(find.textContaining('Sorbitol'), findsWidgets);
      expect(find.textContaining('Tuz'), findsWidgets);
    });

    testWidgets('main section does not show buğday unu or gluten as rows', (
      tester,
    ) async {
      await pumpBarcode(tester, barcodeResult(parsedTokens: popkekTokens));
      // "Buğday unu" never renders (allergen chip is "Gluten / Buğday").
      expect(find.text('Buğday unu'), findsNothing);
      // Bare "Gluten" never renders (chip text is exactly "Gluten / Buğday").
      expect(find.text('Gluten'), findsNothing);
    });

    testWidgets('allergen section shows Gluten/Buğday and Yumurta', (
      tester,
    ) async {
      await pumpBarcode(tester, barcodeResult(parsedTokens: popkekTokens));
      expect(find.text('Alerjenler'), findsOneWidget);
      expect(find.text('Gluten / Buğday'), findsOneWidget);
      // Yumurta appears exactly once → only in allergens, never in main list.
      expect(find.text('Yumurta'), findsOneWidget);
    });

    testWidgets('noise + functional-category tokens are hidden', (
      tester,
    ) async {
      await pumpBarcode(
        tester,
        barcodeResult(parsedTokens: ['palm yağı', 'kıvam arttırıcı', 'dir']),
      );
      expect(find.textContaining('arttırıcı'), findsNothing);
      // 'dir' is too short / noise — never a row.
      expect(find.text('Dir'), findsNothing);
    });

    testWidgets('koruyucu and kabartıcı standalone are hidden', (tester) async {
      await pumpBarcode(
        tester,
        barcodeResult(parsedTokens: ['tuz', 'koruyucu', 'kabartıcı']),
      );
      expect(find.text('Koruyucu'), findsNothing);
      expect(find.text('Kabartıcı'), findsNothing);
    });

    testWidgets(
      'polluted Migros text keeps Tuz in risks and allergens separate',
      (tester) async {
        const rawText =
            'İçindekiler\n'
            'BEYAZ LEBLEBİ, TUZ A\n\n'
            'Alerjen Uyarısı\n'
            'eser miktarda badem, ceviz, buğday gluteni içerir.';
        final parsedTokens = IngredientCanonicalizer.parseIngredientsAdvanced(
          rawText,
        );
        final allergenTokens = IngredientCanonicalizer.extractAllergenTokens(
          rawText,
        );

        await pumpBarcode(
          tester,
          barcodeResult(
            parsedTokens: parsedTokens,
            allergenTokens: allergenTokens,
          ),
        );

        expect(find.text('Tuz'), findsOneWidget);
        expect(find.text('TUZ A'), findsNothing);
        expect(find.text('Badem'), findsOneWidget);
        expect(find.text('Ceviz'), findsOneWidget);
        expect(find.text('Gluten / Buğday'), findsOneWidget);
        expect(find.text('Beyaz Leblebi'), findsNothing);
      },
    );
  });

  // ── Lay's ─────────────────────────────────────────────────────────────────

  group("Lay's-style product", () {
    const laysTokens = [
      'patates',
      'bitkisel yağlar',
      'ayçiçek yağı',
      'mısır yağı',
      'kanola yağı',
      'tuz',
    ];

    testWidgets('main section contains Tuz and specific oils', (tester) async {
      await pumpBarcode(tester, barcodeResult(parsedTokens: laysTokens));
      expect(find.text('Dikkat Edilecek İçerikler'), findsOneWidget);
      expect(find.textContaining('Tuz'), findsWidgets);
      expect(find.textContaining('Ayçiçek'), findsWidgets);
      expect(find.textContaining('Mısır'), findsWidgets);
      expect(find.textContaining('Kanola'), findsWidgets);
    });

    testWidgets(
      'does not show generic "Bitkisel yağlar" when specific oils exist',
      (tester) async {
        await pumpBarcode(tester, barcodeResult(parsedTokens: laysTokens));
        expect(find.textContaining('Bitkisel'), findsNothing);
      },
    );

    testWidgets('Patates is not shown in the main risk section', (
      tester,
    ) async {
      await pumpBarcode(tester, barcodeResult(parsedTokens: laysTokens));
      // Patates goes to the collapsed "Diğer İçerikler" section, hidden by default.
      expect(find.text('Patates'), findsNothing);
    });
  });

  // ── Metadata (Part 7) ───────────────────────────────────────────────────────

  group('important ingredient metadata is not placeholder', () {
    Future<void> tapAndExpectMetadata(
      WidgetTester tester,
      Ingredient ing,
      String findName,
    ) async {
      await pumpBarcode(tester, barcodeResult(recognized: [ing]));
      await tester.tap(find.text(findName).first);
      await tester.pumpAndSettle();
      // The placeholder must NOT appear for important items.
      expect(
        find.text('Bu içerik için detaylı açıklama henüz eklenmedi.'),
        findsNothing,
      );
      // A real purpose section is shown instead.
      expect(find.text('Ne için kullanılır?'), findsOneWidget);
    }

    testWidgets('palm oil detail is not placeholder', (tester) async {
      // Row shows the friendly name "Palm yağı"; the modal keeps the metadata.
      await tapAndExpectMetadata(
        tester,
        ingredient('1', 'Palm Yağı', 'unknown'),
        'Palm yağı',
      );
    });

    testWidgets('invert sugar syrup detail is not placeholder', (tester) async {
      await tapAndExpectMetadata(
        tester,
        ingredient('2', 'İnvert Şeker Şurubu', 'unknown'),
        'Şeker şurubu',
      );
    });

    testWidgets('sorbitol detail is not placeholder', (tester) async {
      await tapAndExpectMetadata(
        tester,
        ingredient('3', 'Sorbitol', 'unknown'),
        'Sorbitol',
      );
    });

    testWidgets('palm oil detail shows sources and disclaimer', (tester) async {
      await pumpBarcode(
        tester,
        barcodeResult(recognized: [ingredient('4', 'Palm Yağı', 'unknown')]),
      );
      await tester.tap(find.text('Palm yağı').first);
      await tester.pumpAndSettle();

      expect(find.text('Kaynaklar'), findsOneWidget);
      expect(
        find.text('Bilgilendirme amaçlıdır; tıbbi tavsiye değildir.'),
        findsOneWidget,
      );
      expect(find.textContaining('WHO'), findsWidgets);
      expect(find.textContaining('Saturated fatty acid'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('specific additive detail shows E-code only when valid', (
      tester,
    ) async {
      await pumpBarcode(
        tester,
        barcodeResult(
          recognized: [ingredient('5', 'Potasyum sorbat', 'unknown')],
        ),
      );
      await tester.tap(find.text('Sorbat koruyucu').first);
      await tester.pumpAndSettle();

      expect(find.text('Potasyum sorbat'), findsOneWidget);
      expect(find.text('E-kodu'), findsOneWidget);
      expect(find.text('E202'), findsWidgets);
    });

    testWidgets('narrow width source cards stay stable', (tester) async {
      tester.view.physicalSize = const Size(320, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await pumpBarcode(
        tester,
        barcodeResult(recognized: [ingredient('6', 'Palm Yağı', 'unknown')]),
      );
      await tester.tap(find.text('Palm yağı').first);
      await tester.pumpAndSettle();

      expect(find.text('Kaynaklar'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
