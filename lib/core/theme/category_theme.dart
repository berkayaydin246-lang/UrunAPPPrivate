import 'package:flutter/material.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/search/models/product_category.dart';
import 'package:food_analyzer_app/features/search/services/canonical_category_mapper.dart';

@immutable
class CategoryThemeData {
  final String mainCategory;
  final Color primaryColor;
  final Color secondaryColor;
  final Color backgroundTint;
  final Color cardTint;
  final Color chipTint;
  final Color borderColor;
  final Color selectedChipColor;
  final Color selectedChipTextColor;
  final Color searchBorderColor;
  final Color filterButtonColor;
  final Color badgeColor;
  final String fallbackIcon;
  final String imageAssetPath;

  const CategoryThemeData({
    required this.mainCategory,
    required this.primaryColor,
    required this.secondaryColor,
    required this.backgroundTint,
    required this.cardTint,
    required this.chipTint,
    required this.borderColor,
    required this.selectedChipColor,
    required this.selectedChipTextColor,
    required this.searchBorderColor,
    required this.filterButtonColor,
    required this.badgeColor,
    required this.fallbackIcon,
    required this.imageAssetPath,
  });

  Color get textOnPrimary => selectedChipTextColor;

  LinearGradient get pageGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      backgroundTint,
      Color.lerp(backgroundTint, Colors.white, 0.62) ?? Colors.white,
    ],
  );

  LinearGradient get cardGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color.lerp(cardTint, Colors.white, 0.55) ?? cardTint,
      Color.lerp(cardTint, Colors.white, 0.82) ?? Colors.white,
    ],
  );
}

CategoryThemeData getCategoryTheme(String? mainCategory) {
  switch (mainCategory) {
    case CanonicalCategoryMapper.kAtistirmalik:
      return const CategoryThemeData(
        mainCategory: CanonicalCategoryMapper.kAtistirmalik,
        primaryColor: Color(0xFFFF6B6B),
        secondaryColor: Color(0xFFFFB4A2),
        backgroundTint: Color(0xFFFFF7F5),
        cardTint: Color(0xFFFFEFEC),
        chipTint: Color(0xFFFFD6D6),
        borderColor: Color(0xFFFF9A9A),
        selectedChipColor: Color(0xFFFF6B6B),
        selectedChipTextColor: Colors.white,
        searchBorderColor: Color(0xFFFF8A8A),
        filterButtonColor: Color(0xFFFF6B6B),
        badgeColor: Color(0xFFFF4F5E),
        fallbackIcon: '🍫',
        imageAssetPath: 'assets/category_images/snacks.png',
      );

    // kSut and kKahvaltilik are compile-time aliases for kSutKahvaltilik —
    // only one case label is needed here.
    case CanonicalCategoryMapper.kSutKahvaltilik:
      return const CategoryThemeData(
        mainCategory: CanonicalCategoryMapper.kSutKahvaltilik,
        primaryColor: Color(0xFF38BDF8),
        secondaryColor: Color(0xFF7DD3FC),
        backgroundTint: Color(0xFFF0F9FF),
        cardTint: Color(0xFFE6F6FF),
        chipTint: Color(0xFFD8F0FE),
        borderColor: Color(0xFFBAE6FD),
        selectedChipColor: Color(0xFF38BDF8),
        selectedChipTextColor: Colors.white,
        searchBorderColor: Color(0xFF7DD3FC),
        filterButtonColor: Color(0xFF38BDF8),
        badgeColor: Color(0xFF0284C7),
        fallbackIcon: '🥛',
        imageAssetPath: 'assets/category_images/dairy.png',
      );

    // kEt is a compile-time alias for kEtTavukBalik.
    case CanonicalCategoryMapper.kEtTavukBalik:
      return const CategoryThemeData(
        mainCategory: CanonicalCategoryMapper.kEtTavukBalik,
        primaryColor: Color(0xFFEF4444),
        secondaryColor: Color(0xFFFCA5A5),
        backgroundTint: Color(0xFFFFF7F7),
        cardTint: Color(0xFFFFECEC),
        chipTint: Color(0xFFFEE2E2),
        borderColor: Color(0xFFFECACA),
        selectedChipColor: Color(0xFFEF4444),
        selectedChipTextColor: Colors.white,
        searchBorderColor: Color(0xFFF87171),
        filterButtonColor: Color(0xFFEF4444),
        badgeColor: Color(0xFFDC2626),
        fallbackIcon: '🥩',
        imageAssetPath: 'assets/category_images/meat_fish.png',
      );

    // kIcecekler is a compile-time alias for kIcecek.
    case CanonicalCategoryMapper.kIcecek:
      return const CategoryThemeData(
        mainCategory: CanonicalCategoryMapper.kIcecek,
        primaryColor: Color(0xFF06B6D4),
        secondaryColor: Color(0xFF67E8F9),
        backgroundTint: Color(0xFFF0FDFF),
        cardTint: Color(0xFFE2FAFD),
        chipTint: Color(0xFFCFFAFE),
        borderColor: Color(0xFFA5F3FC),
        selectedChipColor: Color(0xFF06B6D4),
        selectedChipTextColor: Colors.white,
        searchBorderColor: Color(0xFF22D3EE),
        filterButtonColor: Color(0xFF06B6D4),
        badgeColor: Color(0xFF0891B2),
        fallbackIcon: '🥤',
        imageAssetPath: 'assets/category_images/drinks.png',
      );

    // kSosKonserve is a compile-time alias for kTemelGida — merged into one case.
    case CanonicalCategoryMapper.kTemelGida:
      return const CategoryThemeData(
        mainCategory: CanonicalCategoryMapper.kTemelGida,
        primaryColor: Color(0xFF84CC16),
        secondaryColor: Color(0xFFA3E635),
        backgroundTint: Color(0xFFF7FEE7),
        cardTint: Color(0xFFEEFBD0),
        chipTint: Color(0xFFECFCCB),
        borderColor: Color(0xFFD9F99D),
        selectedChipColor: Color(0xFF84CC16),
        selectedChipTextColor: Color(0xFF243000),
        searchBorderColor: Color(0xFFA3E635),
        filterButtonColor: Color(0xFF84CC16),
        badgeColor: Color(0xFF65A30D),
        fallbackIcon: '🌾',
        imageAssetPath: 'assets/category_images/staples.png',
      );

    case CanonicalCategoryMapper.kMeyveSebze:
      return const CategoryThemeData(
        mainCategory: CanonicalCategoryMapper.kMeyveSebze,
        primaryColor: Color(0xFF22C55E),
        secondaryColor: Color(0xFF86EFAC),
        backgroundTint: Color(0xFFF0FDF4),
        cardTint: Color(0xFFDCFCE7),
        chipTint: Color(0xFFBBF7D0),
        borderColor: Color(0xFF86EFAC),
        selectedChipColor: Color(0xFF22C55E),
        selectedChipTextColor: Colors.white,
        searchBorderColor: Color(0xFF4ADE80),
        filterButtonColor: Color(0xFF22C55E),
        badgeColor: Color(0xFF16A34A),
        fallbackIcon: '🥦',
        imageAssetPath: 'assets/category_images/produce.png',
      );

    case CanonicalCategoryMapper.kHazirDonuk:
      return const CategoryThemeData(
        mainCategory: CanonicalCategoryMapper.kHazirDonuk,
        primaryColor: Color(0xFF0EA5E9),
        secondaryColor: Color(0xFF7DD3FC),
        backgroundTint: Color(0xFFF0F9FF),
        cardTint: Color(0xFFE0F2FE),
        chipTint: Color(0xFFBAE6FD),
        borderColor: Color(0xFF7DD3FC),
        selectedChipColor: Color(0xFF0EA5E9),
        selectedChipTextColor: Colors.white,
        searchBorderColor: Color(0xFF38BDF8),
        filterButtonColor: Color(0xFF0EA5E9),
        badgeColor: Color(0xFF0284C7),
        fallbackIcon: '🥡',
        imageAssetPath: 'assets/category_images/ready_meals.png',
      );

    case CanonicalCategoryMapper.kDondurma:
      return const CategoryThemeData(
        mainCategory: CanonicalCategoryMapper.kDondurma,
        primaryColor: Color(0xFF8B5CF6),
        secondaryColor: Color(0xFFC4B5FD),
        backgroundTint: Color(0xFFFAF5FF),
        cardTint: Color(0xFFF3E8FF),
        chipTint: Color(0xFFEDE9FE),
        borderColor: Color(0xFFDDD6FE),
        selectedChipColor: Color(0xFF8B5CF6),
        selectedChipTextColor: Colors.white,
        searchBorderColor: Color(0xFFA78BFA),
        filterButtonColor: Color(0xFF8B5CF6),
        badgeColor: Color(0xFF7C3AED),
        fallbackIcon: '🍦',
        imageAssetPath: 'assets/category_images/ice_cream.png',
      );

    case CanonicalCategoryMapper.kFirinPastane:
      return const CategoryThemeData(
        mainCategory: CanonicalCategoryMapper.kFirinPastane,
        primaryColor: Color(0xFFF59E0B),
        secondaryColor: Color(0xFFFBBF24),
        backgroundTint: Color(0xFFFFFBEB),
        cardTint: Color(0xFFFFF3D1),
        chipTint: Color(0xFFFDE68A),
        borderColor: Color(0xFFFCD34D),
        selectedChipColor: Color(0xFFF59E0B),
        selectedChipTextColor: Colors.white,
        searchBorderColor: Color(0xFFF59E0B),
        filterButtonColor: Color(0xFFF59E0B),
        badgeColor: Color(0xFFD97706),
        fallbackIcon: '🍞',
        imageAssetPath: 'assets/category_images/bakery.png',
      );

    case CanonicalCategoryMapper.kBebek:
      return const CategoryThemeData(
        mainCategory: CanonicalCategoryMapper.kBebek,
        primaryColor: Color(0xFF14B8A6),
        secondaryColor: Color(0xFF5EEAD4),
        backgroundTint: Color(0xFFF0FDFA),
        cardTint: Color(0xFFCCFBF1),
        chipTint: Color(0xFF99F6E4),
        borderColor: Color(0xFF5EEAD4),
        selectedChipColor: Color(0xFF14B8A6),
        selectedChipTextColor: Colors.white,
        searchBorderColor: Color(0xFF2DD4BF),
        filterButtonColor: Color(0xFF14B8A6),
        badgeColor: Color(0xFF0D9488),
        fallbackIcon: '🍼',
        imageAssetPath: 'assets/category_images/baby.png',
      );

    case CanonicalCategoryMapper.kOzelBeslenme:
      return const CategoryThemeData(
        mainCategory: CanonicalCategoryMapper.kOzelBeslenme,
        primaryColor: Color(0xFF10B981),
        secondaryColor: Color(0xFF6EE7B7),
        backgroundTint: Color(0xFFF0FDF4),
        cardTint: Color(0xFFD1FAE5),
        chipTint: Color(0xFFA7F3D0),
        borderColor: Color(0xFF6EE7B7),
        selectedChipColor: Color(0xFF10B981),
        selectedChipTextColor: Colors.white,
        searchBorderColor: Color(0xFF34D399),
        filterButtonColor: Color(0xFF10B981),
        badgeColor: Color(0xFF059669),
        fallbackIcon: '🌿',
        imageAssetPath: 'assets/category_images/health.png',
      );

    case CanonicalCategoryMapper.kDiger:
    default:
      return const CategoryThemeData(
        mainCategory: CanonicalCategoryMapper.kDiger,
        primaryColor: Color(0xFF8B5CF6),
        secondaryColor: Color(0xFFC4B5FD),
        backgroundTint: Color(0xFFFAF8FF),
        cardTint: Color(0xFFF0EAFF),
        chipTint: Color(0xFFEDE9FE),
        borderColor: Color(0xFFDDD6FE),
        selectedChipColor: Color(0xFF8B5CF6),
        selectedChipTextColor: Colors.white,
        searchBorderColor: Color(0xFFA78BFA),
        filterButtonColor: Color(0xFF8B5CF6),
        badgeColor: Color(0xFF7C3AED),
        fallbackIcon: '🛒',
        imageAssetPath: 'assets/category_images/other.png',
      );
  }
}

CategoryThemeData getCategoryThemeForCategory(ProductCategory category) {
  final canonical = CanonicalCategoryMapper.map(
    categoryTags: category.databaseTags.isNotEmpty
        ? category.databaseTags
        : null,
    name: category.title,
  );
  return getCategoryTheme(canonical.main);
}

CategoryThemeData getCategoryThemeForProduct(Product product) {
  final canonical = CanonicalCategoryMapper.map(
    categoryTags: product.categoryTags,
    name: product.name,
    canonicalCategory: product.canonicalCategory,
    canonicalSubcategory: product.canonicalSubcategory,
  );
  return getCategoryTheme(canonical.main);
}
