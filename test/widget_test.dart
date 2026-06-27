import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/main.dart';

void main() {
  testWidgets('App shell smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: MyApp()));
    await tester.pumpAndSettle();

    expect(find.text('Etiketly'), findsOneWidget);
    expect(find.text('Ara'), findsOneWidget);
    expect(find.text('Barkod'), findsOneWidget);
    expect(find.text('Admin'), findsOneWidget);
  });
}
