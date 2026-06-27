import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/core/theme/category_theme.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/search/models/product_category.dart';
import 'package:food_analyzer_app/features/search/services/canonical_category_mapper.dart';
import 'package:food_analyzer_app/features/search/widgets/category_theme_artwork.dart';

void main() {
  test('getCategoryTheme returns configured Atistirmalik palette', () {
    final theme = getCategoryTheme(CanonicalCategoryMapper.kAtistirmalik);

    expect(theme.primaryColor.toARGB32(), const Color(0xFFFF6B6B).toARGB32());
    expect(theme.backgroundTint.toARGB32(), const Color(0xFFFFF7F5).toARGB32());
    expect(theme.cardTint.toARGB32(), const Color(0xFFFFEFEC).toARGB32());
    expect(theme.chipTint.toARGB32(), const Color(0xFFFFD6D6).toARGB32());
    expect(theme.borderColor.toARGB32(), const Color(0xFFFF9A9A).toARGB32());
    expect(
      theme.selectedChipColor.toARGB32(),
      const Color(0xFFFF6B6B).toARGB32(),
    );
    expect(theme.selectedChipTextColor.toARGB32(), Colors.white.toARGB32());
    expect(theme.imageAssetPath, 'assets/category_images/snacks.png');
  });

  test('getCategoryTheme returns configured Sut palette', () {
    final theme = getCategoryTheme(CanonicalCategoryMapper.kSut);

    expect(theme.primaryColor.toARGB32(), const Color(0xFF38BDF8).toARGB32());
    expect(theme.backgroundTint.toARGB32(), const Color(0xFFF0F9FF).toARGB32());
    expect(theme.cardTint.toARGB32(), const Color(0xFFE6F6FF).toARGB32());
    expect(theme.chipTint.toARGB32(), const Color(0xFFD8F0FE).toARGB32());
    expect(theme.borderColor.toARGB32(), const Color(0xFFBAE6FD).toARGB32());
    expect(theme.imageAssetPath, 'assets/category_images/dairy.png');
  });

  test('unknown category returns fallback theme', () {
    final theme = getCategoryTheme('Bilinmeyen');

    expect(theme.mainCategory, CanonicalCategoryMapper.kDiger);
    expect(theme.primaryColor.toARGB32(), const Color(0xFF8B5CF6).toARGB32());
    expect(theme.fallbackIcon, '🛒');
  });

  test('atistirmalik ProductCategory resolves to its main-category theme', () {
    final category = ProductCategories.findById('atistirmalik')!;
    final theme = getCategoryThemeForCategory(category);

    expect(theme.mainCategory, CanonicalCategoryMapper.kAtistirmalik);
    expect(theme.fallbackIcon, '🍫');
  });

  test('product canonical category drives themed product cards', () {
    final now = DateTime.now();
    final product = Product(
      id: '1',
      name: 'Sütaş Süt',
      canonicalCategory: CanonicalCategoryMapper.kSut,
      verificationStatus: 'verified',
      createdAt: now,
      updatedAt: now,
    );

    final theme = getCategoryThemeForProduct(product);

    expect(theme.mainCategory, CanonicalCategoryMapper.kSut);
    expect(theme.fallbackIcon, '🥛');
  });

  testWidgets('missing category image asset falls back to emoji', (
    tester,
  ) async {
    final theme = getCategoryTheme(CanonicalCategoryMapper.kAtistirmalik);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: CategoryThemeArtwork(categoryTheme: theme)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('🍫'), findsOneWidget);
  });
}
