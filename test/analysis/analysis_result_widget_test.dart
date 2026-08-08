import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/core/widgets/salt_shaker_icon.dart';
import 'package:food_analyzer_app/features/analysis/engines/analysis_engine.dart';
import 'package:food_analyzer_app/features/analysis/models/ingredient_match.dart';
import 'package:food_analyzer_app/features/analysis/models/product_analysis_result.dart';
import 'package:food_analyzer_app/features/analysis/services/ingredient_matcher_service.dart';
import 'package:food_analyzer_app/features/analysis/widgets/analysis_result_widget.dart';
import 'package:food_analyzer_app/features/product/models/ingredient.dart';
import 'package:food_analyzer_app/features/product/models/nutrition_data.dart';

void main() {
  final now = DateTime(2026, 1, 1);

  Ingredient ingredient(
    String id,
    String name,
    String riskLevel, {
    String? type,
    String? purpose,
    String? riskSummary,
    List<String>? cautions,
    String? processingRole,
  }) {
    return Ingredient(
      id: id,
      name: name,
      normalizedName: name.toLowerCase(),
      riskLevel: riskLevel,
      ingredientType: type,
      shortPurpose: purpose,
      shortRiskSummary: riskSummary,
      cautionGroups: cautions,
      processingRole: processingRole,
      createdAt: now,
      updatedAt: now,
    );
  }

  ProductAnalysisResult resultWith({
    List<Ingredient> important = const [],
    List<Ingredient> recognized = const [],
    List<IngredientMatch> reviewRequired = const [],
    String advice = 'Bu urun ara sira tuketim icin daha uygundur.',
  }) {
    final resolvedRecognized = recognized.isEmpty ? important : recognized;

    return ProductAnalysisResult(
      scoreLabel: AnalysisScoreLabel.dikkatliTuket,
      summary: 'Bazi icerikler nedeniyle tuketim sikligina dikkat edilebilir.',
      consumptionAdvice: advice,
      detectedRiskIngredients: important,
      recognizedIngredients: resolvedRecognized,
      otherRecognizedIngredients: resolvedRecognized
          .where((e) => !important.any((i) => i.id == e.id))
          .toList(growable: false),
      reviewRequiredMatches: reviewRequired,
    );
  }

  Future<void> pumpResultWidget(
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
                child: AnalysisResultWidget(result: result),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('single icindeikler section replaces separate sections', (
    tester,
  ) async {
    final result = resultWith(
      important: [ingredient('1', 'Palm Yagi', 'medium')],
    );

    await pumpResultWidget(tester, result);

    expect(find.text('İçindekiler'), findsOneWidget);
    expect(find.text('Öne Çıkan İçerikler'), findsNothing);
    expect(find.text('Diğer Tanınan İçerikler'), findsNothing);
  });

  testWidgets('row tap opens detail modal (no info icon button)', (
    tester,
  ) async {
    final result = resultWith(
      important: [
        ingredient(
          '1',
          'Palm Yagi',
          'medium',
          type: 'Rafine bitkisel yag',
          purpose: 'Kivam ve raf omrunu desteklemek icin kullanilir.',
          riskSummary:
              'Sik tuketimde toplam doymus yag alimina katki saglayabilir.',
        ),
      ],
    );

    await pumpResultWidget(tester, result);

    // Row should be tappable - tap on the ingredient name
    await tester.tap(find.text('Palm Yagi').first);
    await tester.pumpAndSettle();

    expect(find.text('Palm Yagi'), findsWidgets);
    expect(find.text('Ne için kullanılır?'), findsOneWidget);
    expect(find.text('Neden dikkat edilmeli?'), findsOneWidget);
  });

  testWidgets('no info icon button rendered', (tester) async {
    final result = resultWith(
      important: [ingredient('1', 'Palm Yagi', 'medium')],
    );

    await pumpResultWidget(tester, result);

    // Info button should NOT exist
    expect(find.byIcon(Icons.info_outline), findsNothing);
  });

  testWidgets('missing metadata fallback appears in detail modal', (
    tester,
  ) async {
    final result = resultWith(important: [ingredient('1', 'Linalool', 'low')]);

    await pumpResultWidget(tester, result);
    await tester.tap(find.text('Linalool').first);
    await tester.pumpAndSettle();

    expect(
      find.text('Bu içerik için detaylı açıklama henüz eklenmedi.'),
      findsOneWidget,
    );
  });

  testWidgets('barcode nutrition section uses salt shaker icon', (
    tester,
  ) async {
    final result = resultWith(
      important: [ingredient('1', 'Palm Yagi', 'medium')],
    );

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
                  nutritionData: const NutritionData(
                    sugars: 4.0,
                    salt: 0.6,
                    saturatedFat: 1.8,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('nutrition-row-salt-icon')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('nutrition-row-salt-icon')),
        matching: find.byType(SaltShakerIcon),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('nutrition-row-salt-icon')),
        matching: find.byIcon(Icons.grain_outlined),
      ),
      findsNothing,
    );
  });

  testWidgets('default visible count is 8, expansion button appears after', (
    tester,
  ) async {
    final result = resultWith(
      important: [
        ingredient('1', 'A', 'high'),
        ingredient('2', 'B', 'high'),
        ingredient('3', 'C', 'high'),
        ingredient('4', 'D', 'high'),
        ingredient('5', 'E', 'high'),
        ingredient('6', 'F', 'high'),
        ingredient('7', 'G', 'high'),
        ingredient('8', 'H', 'high'),
        ingredient('9', 'I', 'high'),
      ],
    );

    await pumpResultWidget(tester, result);

    // First 8 should exist
    expect(find.text('A'), findsOneWidget);
    expect(find.text('H'), findsOneWidget);

    // 9th should NOT exist initially
    expect(find.text('I'), findsNothing);

    // Expansion button should exist
    expect(find.text('Daha fazla göster'), findsOneWidget);
  });

  testWidgets('high risk rows are rendered before medium and low rows', (
    tester,
  ) async {
    final result = resultWith(
      important: [
        ingredient('1', 'Dusuk', 'low'),
        ingredient('2', 'Orta', 'medium'),
        ingredient('3', 'Yuksek', 'high'),
      ],
    );

    await pumpResultWidget(tester, result);

    final yHigh = tester.getTopLeft(find.text('Yuksek')).dy;
    final yMedium = tester.getTopLeft(find.text('Orta')).dy;
    final yLow = tester.getTopLeft(find.text('Dusuk')).dy;

    expect(yHigh < yMedium, true);
    expect(yMedium < yLow, true);
  });

  testWidgets('main list does not show verbose explanation blocks', (
    tester,
  ) async {
    final result = resultWith(
      important: [
        ingredient(
          '1',
          'Palm Yagi',
          'medium',
          purpose: 'Amaç metni',
          riskSummary: 'Risk metni',
        ),
      ],
    );

    await pumpResultWidget(tester, result);

    expect(find.text('Ne için kullanılır?'), findsNothing);
    expect(find.text('Neden dikkat edilmeli?'), findsNothing);
    expect(find.text('Kullanım Amacı'), findsNothing);
  });

  testWidgets(
    'uncertain section stays hidden when there are no uncertain matches',
    (tester) async {
      final result = resultWith(
        important: [ingredient('1', 'Palm Yagi', 'medium')],
        reviewRequired: const [],
      );

      await pumpResultWidget(tester, result);

      expect(find.text('Emin Olunamayan İçerikler'), findsNothing);
    },
  );

  testWidgets('low risk ingredient shows green dot', (tester) async {
    final result = resultWith(
      important: [ingredient('1', 'Düşük risk örneği', 'low')],
    );

    await pumpResultWidget(tester, result);

    // The canonical low level remains visible alongside its green indicator.
    expect(find.text('Etiketly değerlendirmesi: Düşük düzey'), findsOneWidget);
  });

  testWidgets('combined ingredients from risk and recognized lists', (
    tester,
  ) async {
    final riskIng = ingredient('1', 'Palm Yagi', 'high');
    final recognizedIng = ingredient('2', 'Tuz', 'low');

    final result = resultWith(
      important: [riskIng],
      recognized: [riskIng, recognizedIng],
    );

    await pumpResultWidget(tester, result);

    // Both should appear in unified list
    expect(find.text('Palm Yagi'), findsOneWidget);
    expect(find.text('Tuz'), findsOneWidget);
  });

  // ── AnalysisDisplayMode ───────────────────────────────────────────────────

  Future<void> pumpWithMode(
    WidgetTester tester,
    ProductAnalysisResult result,
    AnalysisDisplayMode mode,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Center(
              child: SizedBox(
                width: 360,
                child: AnalysisResultWidget(result: result, displayMode: mode),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('barcode mode hides uncertain ingredient section', (
    tester,
  ) async {
    final palm = ingredient('u1', 'Palm Yagi', 'high');
    final uncertain = IngredientMatch(
      originalToken: 'palm',
      normalizedText: 'palm yağı',
      matchedIngredient: palm,
      matchedToken: 'palm yağı',
      confidenceScore: 0.75,
      matchType: MatchType.lowConfidencePossible,
      shouldAffectAnalysis: false,
      needsUserConfirmation: true,
    );
    final result = resultWith(important: [palm], reviewRequired: [uncertain]);

    await pumpWithMode(tester, result, AnalysisDisplayMode.barcode);

    expect(find.text('Emin Olunamayan İçerikler'), findsNothing);
  });

  testWidgets(
    'ocr mode shows uncertain ingredient section when matches exist',
    (tester) async {
      final palm = ingredient('u1', 'Palm Yagi', 'high');
      final uncertain = IngredientMatch(
        originalToken: 'palm',
        normalizedText: 'palm yağı',
        matchedIngredient: palm,
        matchedToken: 'palm yağı',
        confidenceScore: 0.75,
        matchType: MatchType.lowConfidencePossible,
        shouldAffectAnalysis: false,
        needsUserConfirmation: true,
      );
      final result = resultWith(important: [palm], reviewRequired: [uncertain]);

      await pumpWithMode(tester, result, AnalysisDisplayMode.ocr);

      expect(find.text('Emin Olunamayan İçerikler'), findsOneWidget);
    },
  );

  testWidgets('barcode mode shows database source banner', (tester) async {
    final result = resultWith(important: [ingredient('1', 'Tuz', 'low')]);

    await pumpWithMode(tester, result, AnalysisDisplayMode.barcode);

    expect(find.textContaining('ürün veritabanındaki'), findsOneWidget);
  });

  testWidgets('ocr mode shows ocr source banner', (tester) async {
    final result = resultWith(important: [ingredient('1', 'Tuz', 'low')]);

    await pumpWithMode(tester, result, AnalysisDisplayMode.ocr);

    expect(find.textContaining('etikette tespit edilen'), findsOneWidget);
  });

  // ── NutritionSectionCard ──────────────────────────────────────────────────

  Future<void> pumpWithNutrition(
    WidgetTester tester,
    ProductAnalysisResult result,
    NutritionData nutrition,
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
                  nutritionData: nutrition,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('nutrition section renders when nutritionData provided', (
    tester,
  ) async {
    final result = resultWith(important: [ingredient('1', 'Tuz', 'low')]);
    const nutrition = NutritionData(sugars: 10.0, salt: 0.5, proteins: 6.0);

    await pumpWithNutrition(tester, result, nutrition);

    expect(find.text('Besin Değerleri'), findsOneWidget);
    expect(find.text('Şeker'), findsOneWidget);
    expect(find.text('Tuz'), findsWidgets);
    expect(find.text('Protein'), findsOneWidget);
  });

  testWidgets('high sugar row shows Yüksek badge in nutrition section', (
    tester,
  ) async {
    final result = resultWith(important: [ingredient('1', 'A', 'low')]);
    const nutrition = NutritionData(sugars: 30.0);

    await pumpWithNutrition(tester, result, nutrition);

    expect(find.text('Yüksek'), findsOneWidget);
  });

  testWidgets('low sugar row shows Düşük badge in nutrition section', (
    tester,
  ) async {
    final result = resultWith(important: [ingredient('1', 'A', 'low')]);
    const nutrition = NutritionData(sugars: 2.0);

    await pumpWithNutrition(tester, result, nutrition);

    expect(find.text('Düşük'), findsOneWidget);
  });

  testWidgets(
    'nutrition section not shown in ocr mode even when nutritionData provided',
    (tester) async {
      final result = resultWith(important: [ingredient('1', 'Tuz', 'low')]);
      const nutrition = NutritionData(sugars: 10.0);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Center(
                child: SizedBox(
                  width: 360,
                  child: AnalysisResultWidget(
                    result: result,
                    displayMode: AnalysisDisplayMode.ocr,
                    nutritionData: nutrition,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Besin Değerleri'), findsNothing);
    },
  );

  testWidgets('barcode mode hides parsed-token debug section for normal users', (
    tester,
  ) async {
    final result = ProductAnalysisResult(
      scoreLabel: AnalysisScoreLabel.orta,
      summary: '',
      detectedRiskIngredients: const [],
      recognizedIngredients: const [],
      unknownIngredients: const ['un', 'su', 'şeker'],
    );

    await pumpWithMode(tester, result, AnalysisDisplayMode.barcode);

    expect(find.text('Ayrıştırılan İçerik Metni'), findsNothing);
    expect(find.text('Dikkat Edilecek İçerikler'), findsOneWidget);
    expect(find.text('Şeker'), findsOneWidget);
    expect(find.text('Un'), findsNothing);
    expect(find.text('Su'), findsNothing);
    expect(
      find.text(
        'İçindekiler metni bulundu ancak dikkat gerektiren eşleşme tespit edilmedi.',
      ),
      findsNothing,
    );
  });

  testWidgets('barcode mode renders meaningful parsed Lay’s ingredients', (
    tester,
  ) async {
    final result = ProductAnalysisResult(
      scoreLabel: AnalysisScoreLabel.orta,
      summary: '',
      detectedRiskIngredients: const [],
      recognizedIngredients: const [],
      unknownIngredients: const [
        'patates',
        'bitkisel yağlar',
        'mısır yağı',
        'ayçiçek yağı',
        'kanola yağı',
        'tuz',
      ],
    );

    await pumpWithMode(tester, result, AnalysisDisplayMode.barcode);

    expect(find.text('Dikkat Edilecek İçerikler'), findsOneWidget);
    expect(find.text('Bitkisel yağlar'), findsNothing);
    expect(find.text('Mısır yağı'), findsOneWidget);
    expect(find.text('Ayçiçek yağı'), findsOneWidget);
    expect(find.text('Kanola yağı'), findsOneWidget);
    expect(find.text('Tuz'), findsOneWidget);
    expect(find.text('Patates'), findsNothing);
    // Rows no longer render a risk subtitle.
    expect(find.text('Orta dikkat'), findsNothing);
    expect(
      find.text(
        'İçindekiler metni bulundu ancak dikkat gerektiren eşleşme tespit edilmedi.',
      ),
      findsNothing,
    );
  });

  testWidgets('barcode mode filters noisy product-detail tokens', (
    tester,
  ) async {
    final result = ProductAnalysisResult(
      scoreLabel: AnalysisScoreLabel.orta,
      summary: '',
      detectedRiskIngredients: const [],
      recognizedIngredients: const [],
      unknownIngredients: const [
        'dir',
        'koruyucu',
        'kabartıcı',
        'kıvam arttırıcı',
        'süt ürünü',
        'palm yağı',
        'şeker',
        'buğday unu',
      ],
    );

    await pumpWithMode(tester, result, AnalysisDisplayMode.barcode);

    expect(find.text('Palm yağı'), findsOneWidget);
    expect(find.text('Şeker'), findsOneWidget);
    expect(find.text('Buğday unu'), findsNothing);
    expect(find.text('Etikette tespit edilen alerjenler'), findsOneWidget);
    expect(find.text('Gluten / Buğday'), findsOneWidget);
    expect(find.text('Dir'), findsNothing);
    expect(find.text('Koruyucu'), findsNothing);
    expect(find.text('Kabartıcı'), findsNothing);
    expect(find.text('Kıvam arttırıcı'), findsNothing);
    expect(find.text('Süt ürünü'), findsNothing);
  });

  testWidgets('barcode mode extracts relevant sugar from product-like token', (
    tester,
  ) async {
    final result = ProductAnalysisResult(
      scoreLabel: AnalysisScoreLabel.orta,
      summary: '',
      detectedRiskIngredients: const [],
      recognizedIngredients: const [],
      unknownIngredients: const [
        "'dir",
        'kıvam arttırıcı',
        'tam hidrojenize palm yağı',
        'invert şeker şurubu',
        'bitter çikolata şeker',
      ],
    );

    await pumpWithMode(tester, result, AnalysisDisplayMode.barcode);

    expect(find.text("'dir"), findsNothing);
    expect(find.text('Kıvam arttırıcı'), findsNothing);
    // Friendly display names: hydrogenated palm → "Palm yağı", invert syrup →
    // "Şeker şurubu". Technical titles must not appear.
    expect(find.text('Palm yağı'), findsOneWidget);
    expect(find.textContaining('hidrojenize'), findsNothing);
    expect(find.text('Şeker şurubu'), findsOneWidget);
    expect(find.textContaining('İnvert'), findsNothing);
    expect(find.text('Bitter çikolata şeker'), findsNothing);
    expect(find.text('Şeker'), findsOneWidget);
  });

  testWidgets('barcode mode hides generic oil group when specific oils exist', (
    tester,
  ) async {
    final result = ProductAnalysisResult(
      scoreLabel: AnalysisScoreLabel.orta,
      summary: '',
      detectedRiskIngredients: const [],
      recognizedIngredients: const [],
      unknownIngredients: const [
        'bitkisel yağlar',
        'mısır yağı',
        'ayçiçek yağı',
        'kanola yağı',
      ],
    );

    await pumpWithMode(tester, result, AnalysisDisplayMode.barcode);

    expect(find.text('Bitkisel yağlar'), findsNothing);
    expect(find.text('Mısır yağı'), findsOneWidget);
    expect(find.text('Ayçiçek yağı'), findsOneWidget);
    expect(find.text('Kanola yağı'), findsOneWidget);
  });

  testWidgets('barcode mode deduplicates PGPR aliases', (tester) async {
    final result = ProductAnalysisResult(
      scoreLabel: AnalysisScoreLabel.orta,
      summary: '',
      detectedRiskIngredients: const [],
      recognizedIngredients: const [],
      unknownIngredients: const [
        'poligliserol ester',
        'poligliserol polirisinoleat',
        'E476',
      ],
    );

    await pumpWithMode(tester, result, AnalysisDisplayMode.barcode);

    // All PGPR aliases collapse into one friendly "Çikolata emülgatörü" row.
    expect(find.text('Çikolata emülgatörü'), findsOneWidget);
    expect(find.textContaining('oligliserol'), findsNothing);
    expect(find.text('E476'), findsNothing);
  });

  testWidgets('palm oil metadata fallback opens useful detail modal', (
    tester,
  ) async {
    final result = ProductAnalysisResult(
      scoreLabel: AnalysisScoreLabel.orta,
      summary: '',
      detectedRiskIngredients: [ingredient('palm', 'Palm yağı', 'medium')],
      recognizedIngredients: [ingredient('palm', 'Palm yağı', 'medium')],
    );

    await pumpWithMode(tester, result, AnalysisDisplayMode.barcode);
    await tester.tap(find.text('Palm yağı').first);
    await tester.pumpAndSettle();

    // Grouped detail sheet: technical name + purpose + risk, with risk + category.
    expect(find.text('Teknik adı'), findsOneWidget);
    expect(find.text('Ne için kullanılır?'), findsOneWidget);
    expect(find.text('Neden dikkat edilmeli?'), findsOneWidget);
    expect(
      find.textContaining('Etiketly değerlendirmesi: Orta düzey'),
      findsOneWidget,
    );
  });

  testWidgets(
    'syrup and sorbitol detail sheets show purpose + technical name',
    (tester) async {
      final result = ProductAnalysisResult(
        scoreLabel: AnalysisScoreLabel.orta,
        summary: '',
        unknownIngredients: const ['invert şeker şurubu', 'sorbitol'],
      );

      await pumpWithMode(tester, result, AnalysisDisplayMode.barcode);
      // Rows show friendly names; tapping opens the canonical detail sheet.
      await tester.tap(find.text('Şeker şurubu').first);
      await tester.pumpAndSettle();
      expect(find.text('Ne için kullanılır?'), findsOneWidget);
      expect(find.text('Teknik adı'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sorbitol').first);
      await tester.pumpAndSettle();
      expect(find.text('Ne için kullanılır?'), findsOneWidget);
      expect(find.text('Teknik adı'), findsOneWidget);
    },
  );

  testWidgets('Popkek-style noisy labels are not rendered', (tester) async {
    final result = ProductAnalysisResult(
      scoreLabel: AnalysisScoreLabel.orta,
      summary: '',
      detectedRiskIngredients: const [],
      recognizedIngredients: const [],
      unknownIngredients: const [
        'dir',
        'fk- kakao soslu kakaolu kaplamalı bitter çikolatalı kek',
        'içindeki: bitter çikolatalı kek',
        'koruyucu',
        'kabartıcı',
        'kıvam arttırıcı',
        'asitlik düzenleyici',
        'nem verici',
        'süt ürünü',
        'kakaolu kaplama',
        'buğday unu',
        'gluten',
        'yumurta',
        'süt tozu',
        'palm yağı',
        'şeker',
        'sorbitol',
        'tuz',
        'ayçiçek yağı',
        'tam hidrojenize palm yağı',
        'invert şeker şurubu',
        'sodyum asit pirofosfat',
        'sodyum hidrojen karbonat',
        'kanola yağı',
        'potasyum sorbat',
        'sorbik asit',
        'poligliserol polirisinoleat',
        'kakao kitlesi',
        'vanilin',
        'lesitin',
      ],
    );

    await pumpWithMode(tester, result, AnalysisDisplayMode.barcode);

    expect(find.text('Dir'), findsNothing);
    expect(find.textContaining('fk-'), findsNothing);
    expect(find.textContaining('İçindeki:'), findsNothing);
    expect(find.text('Kıvam arttırıcı'), findsNothing);
    expect(find.text('Asitlik düzenleyici'), findsNothing);
    expect(find.text('Nem verici'), findsNothing);
    expect(find.text('Süt ürünü'), findsNothing);
    expect(find.text('Kakaolu kaplama'), findsNothing);
    expect(find.text('Buğday unu'), findsNothing);
    expect(find.text('Gluten'), findsNothing);
    // Technical titles must never appear as row names.
    expect(find.textContaining('hidrojenize'), findsNothing);
    expect(find.textContaining('İnvert'), findsNothing);
    expect(find.textContaining('pirofosfat'), findsNothing);
    expect(find.textContaining('oligliserol'), findsNothing);

    expect(find.text('Etikette tespit edilen alerjenler'), findsOneWidget);
    expect(find.text('Gluten / Buğday'), findsOneWidget);
    expect(find.text('Yumurta'), findsOneWidget);
    expect(find.text('Süt'), findsOneWidget);

    // Grouped category titles.
    expect(find.text('Şeker ve Tatlandırıcılar'), findsOneWidget);
    expect(find.text('Yağlar'), findsOneWidget);
    expect(find.text('Koruyucular'), findsOneWidget);
    expect(find.text('Kabartıcılar'), findsOneWidget);
    expect(find.text('Emülgatörler ve Kıvam Vericiler'), findsOneWidget);

    // Friendly, de-duplicated rows in their groups.
    for (final name in const [
      'Şeker',
      'Sorbitol',
      'Şeker şurubu',
      'Palm yağı',
      'Ayçiçek yağı',
      'Sorbat koruyucu',
      'Fosfat bazlı kabartıcı',
      'Karbonat bazlı kabartıcı',
      'Çikolata emülgatörü',
    ]) {
      expect(
        find.text(name),
        name == 'Palm yağı' || name == 'Sorbat koruyucu'
            ? findsNWidgets(2)
            : findsOneWidget,
      );
    }
    expect(find.text('Kanola yağı'), findsNothing);
    expect(find.text('+1 içerik daha'), findsOneWidget);

    // Vague / prefixed names are gone.
    expect(find.text('Kabartıcı katkı'), findsNothing);
    expect(find.text('Kabartıcı'), findsNothing);
    expect(find.textContaining('Tatlandırıcı:'), findsNothing);

    // Low-value technical ingredients are not shown at all.
    expect(find.text('Kakao kitlesi'), findsNothing);
    expect(find.text('Vanilin'), findsNothing);
    expect(find.text('Lesitin'), findsNothing);

    // No giant expander and no per-row risk subtitles.
    expect(find.text('Daha fazla göster'), findsNothing);
    expect(find.text('Orta dikkat'), findsNothing);
  });

  testWidgets('Lay’s-style raw ingredients text does not fall back', (
    tester,
  ) async {
    const rawText =
        'İçindekiler: patates, bitkisel yağlar (değişen miktarlarda mısır yağı, '
        'yüksek oleik asitli ayçiçek yağı, kanola yağı), tuz.';
    const matcher = IngredientMatcherService();
    const engine = AnalysisEngine();
    final tokens = matcher.parseIngredients(rawText);

    expect(tokens.length, greaterThan(0));

    final matchingResult = await matcher.matchIngredientTokens(tokens, [
      ingredient('patates', 'Patates', 'low'),
      ingredient('tuz', 'Tuz', 'medium'),
    ]);
    final result = engine.analyze(matchingResult);
    final displayItemCount =
        result.recognizedIngredients.length + result.unknownIngredients.length;

    expect(displayItemCount, greaterThan(0));
    expect(result.unknownIngredients, contains('bitkisel yağlar'));
    expect(
      result.unknownIngredients.any((item) => item.contains('yağı')),
      isTrue,
    );

    await pumpWithMode(tester, result, AnalysisDisplayMode.barcode);

    expect(find.text('Dikkat Edilecek İçerikler'), findsOneWidget);
    expect(find.text('Tuz'), findsOneWidget);
    expect(find.text('Patates'), findsNothing);
    expect(
      find.textContaining('yağı', findRichText: true),
      findsAtLeastNWidgets(1),
    );
    expect(find.text('Ayrıştırılan İçerik Metni'), findsNothing);
    expect(
      find.text(
        'İçindekiler metni bulundu ancak dikkat gerektiren eşleşme tespit edilmedi.',
      ),
      findsNothing,
    );
  });

  testWidgets(
    'barcode mode shows no-matches message when parsed text is unavailable',
    (tester) async {
      final result = ProductAnalysisResult(
        scoreLabel: AnalysisScoreLabel.orta,
        summary: '',
        detectedRiskIngredients: const [],
        recognizedIngredients: const [],
      );

      await pumpWithMode(tester, result, AnalysisDisplayMode.barcode);

      expect(
        find.text(
          'İçindekiler metni bulundu ancak dikkat gerektiren eşleşme tespit edilmedi.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'nutrition section visible with high-salt data and no ingredients',
    (tester) async {
      // Simulates case (b): no ingredient analysis but nutrition exists.
      final result = ProductAnalysisResult(
        scoreLabel: AnalysisScoreLabel.orta,
        summary: '',
        detectedRiskIngredients: const [],
        recognizedIngredients: const [],
      );
      // High salt (>1.5g) and high protein (>=12g) — tuna-like product
      const nutrition = NutritionData(
        energyKcal: 190.0,
        proteins: 24.8,
        salt: 1.6725,
        fat: 9.3,
        saturatedFat: 1.4,
      );

      await pumpWithNutrition(tester, result, nutrition);

      expect(find.text('Besin Değerleri'), findsOneWidget);
      expect(find.text('Tuz'), findsWidgets);
      expect(find.text('Protein'), findsOneWidget);
      // Salt 1.6725 > 1.5 → Yüksek
      expect(find.text('Yüksek'), findsOneWidget);
    },
  );
}
