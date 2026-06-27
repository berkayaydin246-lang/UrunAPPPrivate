import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('App shell smoke test', (WidgetTester tester) async {
    // Simulate returning user so the intro navigates directly to /search.
    SharedPreferences.setMockInitialValues({
      'etiketly_onboarding_completed_v1': true,
    });

    await tester.pumpWidget(const ProviderScope(child: MyApp()));
    await tester.pumpAndSettle();

    expect(find.text('Etiketly'), findsOneWidget);
    expect(find.text('Ara'), findsOneWidget);
    expect(find.text('Barkod'), findsOneWidget);
    expect(
      find.text('Admin'),
      findsNothing,
    ); // admin tab removed from consumer UI
  });
}
