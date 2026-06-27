import 'package:flutter/material.dart';
import 'package:food_analyzer_app/core/theme/category_accent_colors.dart';
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
        primaryColor: CategoryAccentColors.atistirmalik,
        secondaryColor: Color(0xFFFFB8AD),
        backgroundTint: Color(0xFFFFF6F3),
        cardTint: Color(0xFFFFECE7),
        chipTint: Color(0xFFFFDAD4),
        borderColor: Color(0xFFF1B1A8),
        selectedChipColor: CategoryAccentColors.atistirmalik,
        selectedChipTextColor: Colors.white,
        searchBorderColor: CategoryAccentColors.atistirmalik,
        filterButtonColor: CategoryAccentColors.atistirmalik,
        badgeColor: CategoryAccentColors.atistirmalik,
        fallbackIcon: '🍫',
        imageAssetPath: 'assets/category_images/snacks.png',
      );

    // kSut and kKahvaltilik are compile-time aliases for kSutKahvaltilik —
    // only one case label is needed here.
    case CanonicalCategoryMapper.kSutKahvaltilik:
      return const CategoryThemeData(
        mainCategory: CanonicalCategoryMapper.kSutKahvaltilik,
        primaryColor: CategoryAccentColors.sutKahvaltilik,
        secondaryColor: Color(0xFFF0C37E),
        backgroundTint: Color(0xFFFFF9EF),
        cardTint: Color(0xFFFFEED4),
        chipTint: Color(0xFFFCE0B6),
        borderColor: Color(0xFFEDC98D),
        selectedChipColor: CategoryAccentColors.sutKahvaltilik,
        selectedChipTextColor: Color(0xFF2B1A2D),
        searchBorderColor: CategoryAccentColors.sutKahvaltilik,
        filterButtonColor: CategoryAccentColors.sutKahvaltilik,
        badgeColor: CategoryAccentColors.sutKahvaltilik,
        fallbackIcon: '🥛',
        imageAssetPath: 'assets/category_images/dairy.png',
      );

    // kEt is a compile-time alias for kEtTavukBalik.
    case CanonicalCategoryMapper.kEtTavukBalik:
      return const CategoryThemeData(
        mainCategory: CanonicalCategoryMapper.kEtTavukBalik,
        primaryColor: CategoryAccentColors.etTavukBalik,
        secondaryColor: Color(0xFFF0A597),
        backgroundTint: Color(0xFFFFF7F4),
        cardTint: Color(0xFFF8E6E1),
        chipTint: Color(0xFFF5D5CE),
        borderColor: Color(0xFFE3B0A5),
        selectedChipColor: CategoryAccentColors.etTavukBalik,
        selectedChipTextColor: Colors.white,
        searchBorderColor: CategoryAccentColors.etTavukBalik,
        filterButtonColor: CategoryAccentColors.etTavukBalik,
        badgeColor: CategoryAccentColors.etTavukBalik,
        fallbackIcon: '🥩',
        imageAssetPath: 'assets/category_images/meat_fish.png',
      );

    // kIcecekler is a compile-time alias for kIcecek.
    case CanonicalCategoryMapper.kIcecek:
      return const CategoryThemeData(
        mainCategory: CanonicalCategoryMapper.kIcecek,
        primaryColor: CategoryAccentColors.icecek,
        secondaryColor: Color(0xFFA4D2FB),
        backgroundTint: Color(0xFFF3F9FF),
        cardTint: Color(0xFFE8F2FF),
        chipTint: Color(0xFFD8EBFF),
        borderColor: Color(0xFFA9D1F6),
        selectedChipColor: CategoryAccentColors.icecek,
        selectedChipTextColor: Colors.white,
        searchBorderColor: CategoryAccentColors.icecek,
        filterButtonColor: CategoryAccentColors.icecek,
        badgeColor: CategoryAccentColors.icecek,
        fallbackIcon: '🥤',
        imageAssetPath: 'assets/category_images/drinks.png',
      );

    // kSosKonserve is a compile-time alias for kTemelGida — merged into one case.
    case CanonicalCategoryMapper.kTemelGida:
      return const CategoryThemeData(
        mainCategory: CanonicalCategoryMapper.kTemelGida,
        primaryColor: CategoryAccentColors.temelGida,
        secondaryColor: Color(0xFFF3C56F),
        backgroundTint: Color(0xFFFFF8EE),
        cardTint: Color(0xFFFFEFD8),
        chipTint: Color(0xFFFBE2BA),
        borderColor: Color(0xFFF0C983),
        selectedChipColor: CategoryAccentColors.temelGida,
        selectedChipTextColor: Color(0xFF2B1A2D),
        searchBorderColor: CategoryAccentColors.temelGida,
        filterButtonColor: CategoryAccentColors.temelGida,
        badgeColor: CategoryAccentColors.temelGida,
        fallbackIcon: '🌾',
        imageAssetPath: 'assets/category_images/staples.png',
      );

    case CanonicalCategoryMapper.kMeyveSebze:
      return const CategoryThemeData(
        mainCategory: CanonicalCategoryMapper.kMeyveSebze,
        primaryColor: CategoryAccentColors.meyveSebze,
        secondaryColor: Color(0xFFA7D7B4),
        backgroundTint: Color(0xFFF4FBF6),
        cardTint: Color(0xFFE5F4E9),
        chipTint: Color(0xFFD5ECD8),
        borderColor: Color(0xFFA9D1B0),
        selectedChipColor: CategoryAccentColors.meyveSebze,
        selectedChipTextColor: Colors.white,
        searchBorderColor: CategoryAccentColors.meyveSebze,
        filterButtonColor: CategoryAccentColors.meyveSebze,
        badgeColor: CategoryAccentColors.meyveSebze,
        fallbackIcon: '🥦',
        imageAssetPath: 'assets/category_images/produce.png',
      );

    case CanonicalCategoryMapper.kHazirDonuk:
      return const CategoryThemeData(
        mainCategory: CanonicalCategoryMapper.kHazirDonuk,
        primaryColor: CategoryAccentColors.hazirDonuk,
        secondaryColor: Color(0xFFF5BD7B),
        backgroundTint: Color(0xFFFFF8EF),
        cardTint: Color(0xFFFFE9D3),
        chipTint: Color(0xFFFAD7B0),
        borderColor: Color(0xFFF0B473),
        selectedChipColor: CategoryAccentColors.hazirDonuk,
        selectedChipTextColor: Colors.white,
        searchBorderColor: CategoryAccentColors.hazirDonuk,
        filterButtonColor: CategoryAccentColors.hazirDonuk,
        badgeColor: CategoryAccentColors.hazirDonuk,
        fallbackIcon: '🥡',
        imageAssetPath: 'assets/category_images/ready_meals.png',
      );

    case CanonicalCategoryMapper.kDondurma:
      return const CategoryThemeData(
        mainCategory: CanonicalCategoryMapper.kDondurma,
        primaryColor: CategoryAccentColors.dondurma,
        secondaryColor: Color(0xFFF0B9E4),
        backgroundTint: Color(0xFFFFF6FC),
        cardTint: Color(0xFFF8E6F3),
        chipTint: Color(0xFFF1D3EB),
        borderColor: Color(0xFFE2B3D6),
        selectedChipColor: CategoryAccentColors.dondurma,
        selectedChipTextColor: Color(0xFF2B1A2D),
        searchBorderColor: CategoryAccentColors.dondurma,
        filterButtonColor: CategoryAccentColors.dondurma,
        badgeColor: CategoryAccentColors.dondurma,
        fallbackIcon: '🍦',
        imageAssetPath: 'assets/category_images/ice_cream.png',
      );

    case CanonicalCategoryMapper.kFirinPastane:
      return const CategoryThemeData(
        mainCategory: CanonicalCategoryMapper.kFirinPastane,
        primaryColor: CategoryAccentColors.firinPastane,
        secondaryColor: Color(0xFFD4A47B),
        backgroundTint: Color(0xFFFCF7F2),
        cardTint: Color(0xFFF3E6D9),
        chipTint: Color(0xFFECD3BC),
        borderColor: Color(0xFFD8B48F),
        selectedChipColor: CategoryAccentColors.firinPastane,
        selectedChipTextColor: Colors.white,
        searchBorderColor: CategoryAccentColors.firinPastane,
        filterButtonColor: CategoryAccentColors.firinPastane,
        badgeColor: CategoryAccentColors.firinPastane,
        fallbackIcon: '🍞',
        imageAssetPath: 'assets/category_images/bakery.png',
      );

    case CanonicalCategoryMapper.kBebek:
      return const CategoryThemeData(
        mainCategory: CanonicalCategoryMapper.kBebek,
        primaryColor: CategoryAccentColors.bebek,
        secondaryColor: Color(0xFFF7C8A7),
        backgroundTint: Color(0xFFFFF8F3),
        cardTint: Color(0xFFFFE9DA),
        chipTint: Color(0xFFF8D8C0),
        borderColor: Color(0xFFE9B792),
        selectedChipColor: CategoryAccentColors.bebek,
        selectedChipTextColor: Color(0xFF2B1A2D),
        searchBorderColor: CategoryAccentColors.bebek,
        filterButtonColor: CategoryAccentColors.bebek,
        badgeColor: CategoryAccentColors.bebek,
        fallbackIcon: '🍼',
        imageAssetPath: 'assets/category_images/baby.png',
      );

    case CanonicalCategoryMapper.kOzelBeslenme:
      return const CategoryThemeData(
        mainCategory: CanonicalCategoryMapper.kOzelBeslenme,
        primaryColor: CategoryAccentColors.ozelBeslenme,
        secondaryColor: Color(0xFFB5D9A8),
        backgroundTint: Color(0xFFF5FBF1),
        cardTint: Color(0xFFE6F3DE),
        chipTint: Color(0xFFD4EAC9),
        borderColor: Color(0xFFB6D3A6),
        selectedChipColor: CategoryAccentColors.ozelBeslenme,
        selectedChipTextColor: Colors.white,
        searchBorderColor: CategoryAccentColors.ozelBeslenme,
        filterButtonColor: CategoryAccentColors.ozelBeslenme,
        badgeColor: CategoryAccentColors.ozelBeslenme,
        fallbackIcon: '🌿',
        imageAssetPath: 'assets/category_images/health.png',
      );

    case CanonicalCategoryMapper.kDiger:
    default:
      return const CategoryThemeData(
        mainCategory: CanonicalCategoryMapper.kDiger,
        primaryColor: CategoryAccentColors.diger,
        secondaryColor: Color(0xFFCDBDDA),
        backgroundTint: Color(0xFFF9F6FC),
        cardTint: Color(0xFFF0E8F5),
        chipTint: Color(0xFFE5DBED),
        borderColor: Color(0xFFD4C4DF),
        selectedChipColor: CategoryAccentColors.diger,
        selectedChipTextColor: Colors.white,
        searchBorderColor: CategoryAccentColors.diger,
        filterButtonColor: CategoryAccentColors.diger,
        badgeColor: CategoryAccentColors.diger,
        fallbackIcon: '🛒',
        imageAssetPath: 'assets/category_images/other.png',
      );
  }
}

CategoryThemeData getCategoryThemeForCategory(ProductCategory category) {
  final directMainCategory = _mainCategoryForProductCategoryId(category.id);
  if (directMainCategory != null) {
    return getCategoryTheme(directMainCategory);
  }

  final canonical = CanonicalCategoryMapper.map(
    categoryTags: category.databaseTags.isNotEmpty
        ? category.databaseTags
        : null,
    name: category.title,
  );
  return getCategoryTheme(canonical.main);
}

String? _mainCategoryForProductCategoryId(String id) {
  switch (id) {
    case 'atistirmalik':
      return CanonicalCategoryMapper.kAtistirmalik;
    case 'icecek':
      return CanonicalCategoryMapper.kIcecek;
    case 'sut-kahvaltilik':
      return CanonicalCategoryMapper.kSutKahvaltilik;
    case 'temel-gida':
      return CanonicalCategoryMapper.kTemelGida;
    case 'et-tavuk-balik':
      return CanonicalCategoryMapper.kEtTavukBalik;
    case 'meyve-sebze':
      return CanonicalCategoryMapper.kMeyveSebze;
    case 'hazir-donuk':
      return CanonicalCategoryMapper.kHazirDonuk;
    case 'dondurma':
      return CanonicalCategoryMapper.kDondurma;
    case 'firin-pastane':
      return CanonicalCategoryMapper.kFirinPastane;
    case 'bebek-gida':
      return CanonicalCategoryMapper.kBebek;
    case 'ozel-beslenme':
      return CanonicalCategoryMapper.kOzelBeslenme;
    case 'diger':
      return CanonicalCategoryMapper.kDiger;
    default:
      return null;
  }
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
