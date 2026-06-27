import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/analysis/models/product_analysis_result.dart';
import 'package:food_analyzer_app/features/analysis/widgets/analysis_result_widget.dart';

void main() {
  ProductAnalysisResult barcodeResult(List<String> parsedTokens) {
    return ProductAnalysisResult(
      scoreLabel: AnalysisScoreLabel.orta,
      summary: '',
      unknownIngredients: parsedTokens,
    );
  }

  Future<void> pumpBarcode(
    WidgetTester tester,
    List<String> parsedTokens,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Center(
              child: SizedBox(
                width: 360,
                child: AnalysisResultWidget(
                  result: barcodeResult(parsedTokens),
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

  // ── Test 1: grouping ────────────────────────────────────────────────────────

  testWidgets('groups ingredients by category with friendly names', (
    tester,
  ) async {
    await pumpBarcode(tester, [
      'palm yağı',
      'tam hidrojenize palm yağı',
      'şeker',
      'invert şeker şurubu',
      'sorbitol',
      'sorbik asit',
      'potasyum sorbat',
      'sodyum asit pirofosfat',
      'sodyum hidrojen karbonat',
      'poligliserol polirisinoleat',
    ]);

    expect(find.text('Şeker ve Tatlandırıcılar'), findsOneWidget);
    expect(find.text('Şeker'), findsOneWidget);
    expect(find.text('Şeker şurubu'), findsOneWidget);
    expect(find.text('Sorbitol'), findsOneWidget);

    expect(find.text('Yağlar'), findsOneWidget);
    expect(find.text('Palm yağı'), findsOneWidget);

    expect(find.text('Koruyucular'), findsOneWidget);
    expect(find.text('Sorbat koruyucu'), findsOneWidget);

    expect(find.text('Kabartıcılar'), findsOneWidget);
    expect(find.text('Fosfat bazlı kabartıcı'), findsOneWidget);
    expect(find.text('Karbonat bazlı kabartıcı'), findsOneWidget);

    expect(find.text('Emülgatörler ve Kıvam Vericiler'), findsOneWidget);
    expect(find.text('Çikolata emülgatörü'), findsOneWidget);

    // Technical names never appear as row titles.
    expect(find.textContaining('hidrojenize'), findsNothing);
    expect(find.textContaining('İnvert'), findsNothing);
    expect(find.textContaining('pirofosfat'), findsNothing);
    expect(find.textContaining('oligliserol'), findsNothing);
    // Vague titles are gone.
    expect(find.text('Kabartıcı katkı'), findsNothing);
    expect(find.text('Kabartıcı'), findsNothing);
  });

  // ── Test 2: no duplicate palm ───────────────────────────────────────────────

  testWidgets('palm variants merge into a single "Palm yağı" row', (
    tester,
  ) async {
    await pumpBarcode(tester, ['palm yağı', 'tam hidrojenize palm yağı']);
    expect(find.text('Palm yağı'), findsOneWidget);
    expect(find.textContaining('hidrojenize'), findsNothing);
  });

  // ── Test 3: consistent risk (low → detail says Az dikkat) ───────────────────

  testWidgets('sorbat preservative risk is consistent (low)', (tester) async {
    await pumpBarcode(tester, ['potasyum sorbat']);
    await tester.tap(find.text('Sorbat koruyucu'));
    await tester.pumpAndSettle();
    // Same spec.risk drives the list dot and this label → guaranteed consistent.
    expect(find.textContaining('Az dikkat'), findsOneWidget);
    expect(find.textContaining('Koruyucu'), findsWidgets);
  });

  // ── Test 4: no risk subtitle under rows ─────────────────────────────────────

  testWidgets('rows do not render risk subtitle text', (tester) async {
    await pumpBarcode(tester, ['palm yağı', 'şeker', 'potasyum sorbat']);
    expect(find.text('Orta dikkat'), findsNothing);
    expect(find.text('Az dikkat'), findsNothing);
    expect(find.text('Yüksek dikkat'), findsNothing);
  });

  // ── Test 5: max 3 per group ─────────────────────────────────────────────────

  testWidgets('a group shows at most 3 rows, rest behind "+N içerik daha"', (
    tester,
  ) async {
    await pumpBarcode(tester, [
      'şeker',
      'invert şeker şurubu',
      'sorbitol',
      'aspartam',
      'sukraloz',
    ]);
    // 5 sweeteners → only the top 3 by risk/order are shown.
    expect(find.text('Aspartam'), findsOneWidget); // high → sorted first
    expect(find.text('Şeker'), findsOneWidget);
    expect(find.text('Şeker şurubu'), findsOneWidget);
    // The 2 lowest-priority items are hidden.
    expect(find.text('Sorbitol'), findsNothing);
    expect(find.text('Sukraloz'), findsNothing);
    expect(find.textContaining('+2 içerik daha'), findsOneWidget);
  });

  // ── Display-name mappings ───────────────────────────────────────────────────

  testWidgets('benzoate → "Benzoat koruyucu"', (tester) async {
    await pumpBarcode(tester, ['sodyum benzoat']);
    expect(find.text('Benzoat koruyucu'), findsOneWidget);
  });

  testWidgets('leaveners map to user-friendly specific names', (tester) async {
    await pumpBarcode(tester, [
      'sodyum asit pirofosfat',
      'sodyum hidrojen karbonat',
    ]);
    expect(find.text('Fosfat bazlı kabartıcı'), findsOneWidget);
    expect(find.text('Karbonat bazlı kabartıcı'), findsOneWidget);
    expect(find.text('Kabartıcı'), findsNothing);
    expect(find.text('Kabartıcı katkı'), findsNothing);
  });

  testWidgets('sorbitol row has no "Tatlandırıcı:" prefix', (tester) async {
    await pumpBarcode(tester, ['sorbitol']);
    expect(find.text('Sorbitol'), findsOneWidget);
    expect(find.textContaining('Tatlandırıcı:'), findsNothing);
  });

  // ── Detail sheet (Part 4) ───────────────────────────────────────────────────

  testWidgets(
    'tapping a grouped row opens a detail sheet with technical name',
    (tester) async {
      await pumpBarcode(tester, ['palm yağı']);
      await tester.tap(find.text('Palm yağı'));
      await tester.pumpAndSettle();
      expect(find.text('Teknik adı'), findsOneWidget);
      expect(find.text('Ne için kullanılır?'), findsOneWidget);
      expect(find.text('Neden dikkat edilmeli?'), findsOneWidget);
      expect(find.textContaining('Orta dikkat'), findsOneWidget);
    },
  );
}
