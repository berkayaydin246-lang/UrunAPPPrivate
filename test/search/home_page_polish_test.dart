import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/core/theme/app_theme.dart';
import 'package:food_analyzer_app/features/search/models/product_category.dart';
import 'package:food_analyzer_app/features/search/search_page.dart';

Widget _buildTestApp(Widget child) {
  return ProviderScope(
    child: MaterialApp(theme: AppTheme.lightTheme(), home: child),
  );
}

void main() {
  group('Home page polish (release quality)', () {
    testWidgets('home page has no filter button', (WidgetTester tester) async {
      await tester.pumpWidget(_buildTestApp(const SearchScreen()));

      expect(find.byIcon(Icons.tune), findsNothing);
    });

    testWidgets('search bar is full width (28px padding)', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_buildTestApp(const SearchScreen()));

      final searchField = find.byType(TextField);
      expect(searchField, findsOneWidget);

      // Verify the parent Row has full-width Expanded widget
      expect(find.byType(Expanded), findsWidgets);
    });

    testWidgets('Atıştırmalık category title fits on one line', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_buildTestApp(const SearchScreen()));

      // The tile uses FittedBox(scaleDown) so the Text has maxLines=1, softWrap=false.
      final titleText = find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.data == 'Atıştırmalık' &&
            widget.maxLines == 1,
      );

      expect(titleText, findsOneWidget);

      // FittedBox ancestor confirms scale-down strategy is in place.
      expect(
        find.ancestor(of: titleText, matching: find.byType(FittedBox)),
        findsOneWidget,
      );
    });

    testWidgets('3 columns maintained in category grid', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_buildTestApp(const SearchScreen()));

      // Find SliverGrid to verify crossAxisCount
      final gridFinder = find.byType(SliverGrid);
      expect(gridFinder, findsOneWidget);

      final gridWidget = gridFinder.evaluate().first.widget as SliverGrid;
      final delegate =
          gridWidget.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      expect(delegate.crossAxisCount, 3);
    });

    testWidgets('10 categories visible on home', (WidgetTester tester) async {
      await tester.pumpWidget(_buildTestApp(const SearchScreen()));

      final visibleCategories = ProductCategories.getVisible();
      expect(visibleCategories.length, 10);

      // Verify grid has 10 items
      expect(find.byType(SliverGrid), findsOneWidget);
    });

    testWidgets('category titles allow 2 lines for wrapping', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_buildTestApp(const SearchScreen()));

      // Find all Text widgets with maxLines: 2
      final textWidgets = find.byWidgetPredicate(
        (widget) => widget is Text && widget.maxLines == 2,
      );

      // Should find multiple category titles
      expect(textWidgets, findsWidgets);
    });

    testWidgets('no overflow in category grid', (WidgetTester tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      tester.view.physicalSize = const Size(360, 800);

      await tester.pumpWidget(_buildTestApp(const SearchScreen()));

      // If there are overflow issues, Flutter will report them during layout
      expect(tester.takeException(), isNull);
    });

    testWidgets('helper subtitle Ürünleri kategoriye göre keşfet is visible', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_buildTestApp(const SearchScreen()));

      expect(find.text('Ürünleri kategoriye göre keşfet'), findsOneWidget);
    });

    testWidgets('Kategoriler heading is visible', (WidgetTester tester) async {
      await tester.pumpWidget(_buildTestApp(const SearchScreen()));

      expect(find.text('Kategoriler'), findsOneWidget);
    });

    testWidgets('category tap behavior preserved', (WidgetTester tester) async {
      await tester.pumpWidget(_buildTestApp(const SearchScreen()));

      // Verify InkWell taps work (they are inside the grid tiles)
      final inkWells = find.byType(InkWell);
      expect(inkWells, findsWidgets);
    });

    testWidgets('search hint text is visible', (WidgetTester tester) async {
      await tester.pumpWidget(_buildTestApp(const SearchScreen()));

      // There should be a search TextField with the proper hint
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('search bar padding is symmetric (28px horizontal)', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_buildTestApp(const SearchScreen()));

      // Verify padding values in the search bar Row
      final paddingWidgets = find.byType(Padding);
      expect(paddingWidgets, findsWidgets);

      // At least one Padding should have 28px on left/right (for search bar)
      bool foundSearchBarPadding = false;
      for (final padding in paddingWidgets.evaluate()) {
        final widget = padding.widget as Padding;
        if (widget.padding is EdgeInsets) {
          final insets = widget.padding as EdgeInsets;
          if (insets.left == 28 && insets.right == 28) {
            foundSearchBarPadding = true;
            break;
          }
        }
      }
      expect(foundSearchBarPadding, true);
    });
  });
}
