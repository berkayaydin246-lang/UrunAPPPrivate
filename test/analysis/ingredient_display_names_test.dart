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
    expect(find.text('Palm yağı'), findsNWidgets(2));

    expect(find.text('Koruyucular'), findsOneWidget);
    expect(find.text('Sorbat koruyucu'), findsNWidgets(2));

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

  // ── Test 2: unresolved identity is not inferred from display grouping ───────

  testWidgets('palm variants retain distinct unresolved identities', (
    tester,
  ) async {
    await pumpBarcode(tester, ['palm yağı', 'tam hidrojenize palm yağı']);
    expect(find.text('Palm yağı'), findsNWidgets(2));
    expect(find.textContaining('hidrojenize'), findsNothing);
  });

  // ── Test 3: raw tokens do not receive a display-spec risk ───────────────────

  testWidgets('unresolved sorbat token remains informational', (tester) async {
    await pumpBarcode(tester, ['potasyum sorbat']);
    await tester.tap(find.text('Sorbat koruyucu'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Etiketly değerlendirmesi: Bilgi yok'),
      findsOneWidget,
    );
    expect(find.textContaining('Koruyucu'), findsWidgets);
  });

  // ── Test 4: no risk subtitle under rows ─────────────────────────────────────

  testWidgets('rows do not render risk subtitle text', (tester) async {
    await pumpBarcode(tester, ['palm yağı', 'şeker', 'potasyum sorbat']);
    expect(find.text('Etiketly değerlendirmesi: Orta düzey'), findsNothing);
    expect(find.text('Etiketly değerlendirmesi: Düşük düzey'), findsNothing);
    expect(find.text('Etiketly değerlendirmesi: Yüksek düzey'), findsNothing);
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
    // Unresolved tokens have no inferred risk, so source order is preserved.
    expect(find.text('Şeker'), findsOneWidget);
    expect(find.text('Şeker şurubu'), findsOneWidget);
    expect(find.text('Sorbitol'), findsOneWidget);
    // The final two source items are hidden by the display cap.
    expect(find.text('Aspartam'), findsNothing);
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
      expect(
        find.textContaining('Etiketly değerlendirmesi: Bilgi yok'),
        findsOneWidget,
      );
    },
  );
}
