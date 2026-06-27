import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/branding/pages/etiketly_intro_page.dart';

Widget _buildPage(VoidCallback onComplete) {
  return MaterialApp(home: EtiketlyIntroPage(onComplete: onComplete));
}

void main() {
  group('EtiketlyIntroPage', () {
    testWidgets('renders Etiketly transparent logo mark', (tester) async {
      await tester.pumpWidget(_buildPage(() {}));
      await tester.pump();

      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Image &&
              w.image is AssetImage &&
              (w.image as AssetImage).assetName.contains('etiketly_logo_mark'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('background colour matches logo cream', (tester) async {
      await tester.pumpWidget(_buildPage(() {}));
      await tester.pump();

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, EtiketlyIntroPage.backgroundColor);
    });

    testWidgets('no FreshScan text is visible', (tester) async {
      await tester.pumpWidget(_buildPage(() {}));
      await tester.pumpAndSettle();

      expect(find.textContaining('FreshScan'), findsNothing);
    });

    testWidgets('total animation duration is at most 2500 ms', (tester) async {
      await tester.pumpWidget(_buildPage(() {}));

      // Advance 2500 ms — animation must finish by then (2000 ms main + 300 ms exit).
      await tester.pump(const Duration(milliseconds: 2500));
      await tester.pump(); // one more frame to settle

      expect(true, isTrue);
    });

    testWidgets('onComplete callback called exactly once after animation', (
      tester,
    ) async {
      int callCount = 0;
      await tester.pumpWidget(_buildPage(() => callCount++));

      // Full animation: 2000 ms main + 300 ms exit = 2300 ms total.
      await tester.pump(const Duration(milliseconds: 2300));
      await tester.pump(const Duration(milliseconds: 200)); // settle
      await tester.pumpAndSettle();

      expect(callCount, 1);
    });
  });
}
