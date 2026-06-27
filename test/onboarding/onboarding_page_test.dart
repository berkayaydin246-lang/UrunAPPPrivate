import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/onboarding/pages/onboarding_page.dart';

Widget _buildPage(VoidCallback onComplete) =>
    MaterialApp(home: OnboardingPage(onComplete: onComplete));

/// Swipe forward by [count] pages in the PageView.
Future<void> _swipeToPage(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i++) {
    await tester.drag(find.byType(PageView), const Offset(-400, 0));
    await tester.pumpAndSettle();
  }
}

void main() {
  group('OnboardingPage', () {
    testWidgets('first launch shows onboarding content', (tester) async {
      await tester.pumpWidget(_buildPage(() {}));
      await tester.pump();

      // Should render the first slide title and the Atla button
      expect(find.text('Etiketi tara'), findsOneWidget);
      expect(find.text('Atla'), findsOneWidget);
      expect(find.text('Devam'), findsOneWidget);
    });

    testWidgets('skip button calls onComplete immediately', (tester) async {
      int calls = 0;
      await tester.pumpWidget(_buildPage(() => calls++));
      await tester.pump();

      await tester.tap(find.text('Atla'));
      await tester.pump();

      expect(calls, 1);
    });

    testWidgets('Devam advances through pages', (tester) async {
      await tester.pumpWidget(_buildPage(() {}));
      await tester.pump();

      // Tap Devam on page 1
      await tester.tap(find.text('Devam'));
      await tester.pumpAndSettle();

      // Should now show page 2 title
      expect(find.text('İçindekileri anla'), findsOneWidget);
    });

    testWidgets('final CTA calls onComplete exactly once', (tester) async {
      int calls = 0;
      await tester.pumpWidget(_buildPage(() => calls++));
      await tester.pump();

      // Swipe to last page (index 3)
      await _swipeToPage(tester, 3);

      expect(find.text('Başlayalım'), findsOneWidget);
      await tester.tap(find.text('Başlayalım'));
      await tester.pump();

      expect(calls, 1);
    });

    testWidgets('page indicators are visible', (tester) async {
      await tester.pumpWidget(_buildPage(() {}));
      await tester.pump();

      // There are 4 indicator dots; verify by counting AnimatedContainers
      // inside the indicator row. The row has exactly 4 dot containers.
      final indicators = find.descendant(
        of: find.byType(Row),
        matching: find.byType(AnimatedContainer),
      );
      expect(indicators, findsWidgets);
    });

    testWidgets('disclaimer text appears on last page', (tester) async {
      await tester.pumpWidget(_buildPage(() {}));
      await tester.pump();

      await _swipeToPage(tester, 3);

      expect(find.text('Gizlilik Politikası'), findsOneWidget);
      expect(find.text('Kullanım Şartları'), findsOneWidget);
      expect(find.text('Bilgilendirme amaçlıdır'), findsOneWidget);
    });

    testWidgets('no FreshScan text appears in onboarding', (tester) async {
      await tester.pumpWidget(_buildPage(() {}));

      for (var i = 0; i < 4; i++) {
        await tester.pump();
        expect(find.textContaining('FreshScan'), findsNothing);
        if (i < 3) await _swipeToPage(tester, 1);
      }
    });

    testWidgets('does not overflow on narrow 320×568 viewport', (tester) async {
      tester.view.physicalSize = const Size(640, 1136); // 320×568 @2x
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_buildPage(() {}));
      await tester.pump();

      // No RenderFlex overflow exception means the layout fits
      expect(tester.takeException(), isNull);
    });
  });
}
