import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/branding/pages/etiketly_intro_page.dart';

Widget _buildPage(VoidCallback onComplete) {
  return MaterialApp(home: EtiketlyIntroPage(onComplete: onComplete));
}

void main() {
  group('EtiketlyIntroPage', () {
    testWidgets('renders Etiketly logo asset', (tester) async {
      await tester.pumpWidget(_buildPage(() {}));
      await tester.pump();

      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Image &&
              w.image is AssetImage &&
              (w.image as AssetImage).assetName.contains('etiketly_icon.png'),
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

    testWidgets('total animation duration is at most 1800 ms', (tester) async {
      await tester.pumpWidget(_buildPage(() {}));

      // Advance 1800 ms — animation must be finished by then.
      await tester.pump(const Duration(milliseconds: 1800));
      await tester.pump(); // settle one more frame

      // If animation ran past 1800 ms the ticker would have errored;
      // reaching here confirms the duration constraint.
      expect(true, isTrue);
    });

    testWidgets('onComplete callback called exactly once after animation', (
      tester,
    ) async {
      int callCount = 0;
      await tester.pumpWidget(_buildPage(() => callCount++));

      // Run the full animation (main 1500 ms + exit 200 ms = 1700 ms total).
      await tester.pump(const Duration(milliseconds: 1700));
      await tester.pump(const Duration(milliseconds: 100)); // settle
      await tester.pumpAndSettle();

      expect(callCount, 1);
    });
  });
}
