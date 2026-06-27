import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/core/theme/category_accent_colors.dart';
import 'package:food_analyzer_app/core/theme/category_theme.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/search/models/product_category.dart';
import 'package:food_analyzer_app/features/search/services/canonical_category_mapper.dart';
import 'package:food_analyzer_app/features/search/widgets/category_theme_artwork.dart';

void main() {
  test('getCategoryTheme returns configured Atistirmalik palette', () {
    final theme = getCategoryTheme(CanonicalCategoryMapper.kAtistirmalik);

    expect(
      theme.primaryColor.toARGB32(),
      CategoryAccentColors.atistirmalik.toARGB32(),
    );
    expect(theme.backgroundTint.toARGB32(), const Color(0xFFFFF6F3).toARGB32());
    expect(theme.cardTint.toARGB32(), const Color(0xFFFFECE7).toARGB32());
    expect(theme.chipTint.toARGB32(), const Color(0xFFFFDAD4).toARGB32());
    expect(theme.borderColor.toARGB32(), const Color(0xFFF1B1A8).toARGB32());
    expect(
      theme.selectedChipColor.toARGB32(),
      CategoryAccentColors.atistirmalik.toARGB32(),
    );
    expect(theme.searchBorderColor.toARGB32(), theme.primaryColor.toARGB32());
    expect(theme.filterButtonColor.toARGB32(), theme.primaryColor.toARGB32());
    expect(theme.badgeColor.toARGB32(), theme.primaryColor.toARGB32());
    expect(theme.selectedChipTextColor.toARGB32(), Colors.white.toARGB32());
    expect(theme.imageAssetPath, 'assets/category_images/snacks.png');
  });

  test('getCategoryTheme returns configured Sut palette', () {
    final theme = getCategoryTheme(CanonicalCategoryMapper.kSut);

    expect(
      theme.primaryColor.toARGB32(),
      CategoryAccentColors.sutKahvaltilik.toARGB32(),
    );
    expect(theme.backgroundTint.toARGB32(), const Color(0xFFFFF9EF).toARGB32());
    expect(theme.cardTint.toARGB32(), const Color(0xFFFFEED4).toARGB32());
    expect(theme.chipTint.toARGB32(), const Color(0xFFFCE0B6).toARGB32());
    expect(theme.borderColor.toARGB32(), const Color(0xFFEDC98D).toARGB32());
    expect(theme.searchBorderColor.toARGB32(), theme.primaryColor.toARGB32());
    expect(theme.filterButtonColor.toARGB32(), theme.primaryColor.toARGB32());
    expect(theme.badgeColor.toARGB32(), theme.primaryColor.toARGB32());
    expect(theme.imageAssetPath, 'assets/category_images/dairy.png');
  });

  test(
    'configured visible main-category accents match the Etiketly palette',
    () {
      expect(
        getCategoryTheme(CanonicalCategoryMapper.kAtistirmalik).primaryColor,
        CategoryAccentColors.atistirmalik,
      );
      expect(
        getCategoryTheme(CanonicalCategoryMapper.kIcecek).primaryColor,
        CategoryAccentColors.icecek,
      );
      expect(
        getCategoryTheme(CanonicalCategoryMapper.kSutKahvaltilik).primaryColor,
        CategoryAccentColors.sutKahvaltilik,
      );
      expect(
        getCategoryTheme(CanonicalCategoryMapper.kTemelGida).primaryColor,
        CategoryAccentColors.temelGida,
      );
      expect(
        getCategoryTheme(CanonicalCategoryMapper.kEtTavukBalik).primaryColor,
        CategoryAccentColors.etTavukBalik,
      );
      expect(
        getCategoryTheme(CanonicalCategoryMapper.kMeyveSebze).primaryColor,
        CategoryAccentColors.meyveSebze,
      );
      expect(
        getCategoryTheme(CanonicalCategoryMapper.kHazirDonuk).primaryColor,
        CategoryAccentColors.hazirDonuk,
      );
      expect(
        getCategoryTheme(CanonicalCategoryMapper.kDondurma).primaryColor,
        CategoryAccentColors.dondurma,
      );
      expect(
        getCategoryTheme(CanonicalCategoryMapper.kFirinPastane).primaryColor,
        CategoryAccentColors.firinPastane,
      );
      expect(
        getCategoryTheme(CanonicalCategoryMapper.kBebek).primaryColor,
        CategoryAccentColors.bebek,
      );
    },
  );

  test('visible main category accent colors are unique', () {
    final themes = ProductCategories.getVisible().map(
      getCategoryThemeForCategory,
    );
    final colors = themes
        .map((theme) => theme.selectedChipColor.toARGB32())
        .toList(growable: false);

    expect(colors.toSet(), hasLength(colors.length));
    expect(
      getCategoryTheme(CanonicalCategoryMapper.kAtistirmalik).primaryColor,
      isNot(getCategoryTheme(CanonicalCategoryMapper.kIcecek).primaryColor),
    );
    expect(
      getCategoryTheme(CanonicalCategoryMapper.kIcecek).primaryColor,
      isNot(
        getCategoryTheme(CanonicalCategoryMapper.kSutKahvaltilik).primaryColor,
      ),
    );
    expect(
      getCategoryTheme(CanonicalCategoryMapper.kTemelGida).primaryColor,
      isNot(
        getCategoryTheme(CanonicalCategoryMapper.kEtTavukBalik).primaryColor,
      ),
    );
    expect(
      getCategoryTheme(CanonicalCategoryMapper.kMeyveSebze).primaryColor,
      isNot(getCategoryTheme(CanonicalCategoryMapper.kHazirDonuk).primaryColor),
    );
  });

  test(
    'visible ProductCategory color values use the central accent mapping',
    () {
      for (final category in ProductCategories.getVisible()) {
        final theme = getCategoryThemeForCategory(category);
        expect(
          category.color.toARGB32(),
          theme.primaryColor.toARGB32(),
          reason: '${category.id} should use the centralized category accent',
        );
      }
    },
  );

  test('unknown category returns fallback theme', () {
    final theme = getCategoryTheme('Bilinmeyen');

    expect(theme.mainCategory, CanonicalCategoryMapper.kDiger);
    expect(theme.primaryColor.toARGB32(), const Color(0xFF8A739C).toARGB32());
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
