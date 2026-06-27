import 'package:food_analyzer_app/features/search/models/category_query_plan.dart';
import 'package:food_analyzer_app/features/search/services/canonical_category_mapper.dart';

/// Sort options for product search results.
enum SearchSortOrder {
  relevance,
  nameAsc,
  nameDesc,
  brandAsc,
  brandDesc,
  newestFirst,
  // ── Nutrition sorts ─────────────────────────────────────────────────────────
  energyAsc,
  energyDesc,
  proteinsAsc,
  proteinsDesc,
  sugarsAsc,
  sugarsDesc,
  fatAsc,
  fatDesc,
  saturatedFatAsc,
  saturatedFatDesc,
  saltAsc,
  saltDesc,
  fiberAsc,
  fiberDesc,
}

extension SearchSortOrderLabel on SearchSortOrder {
  String get label {
    switch (this) {
      case SearchSortOrder.relevance:
        return 'En Alakalı';
      case SearchSortOrder.nameAsc:
        return 'İsim A–Z';
      case SearchSortOrder.nameDesc:
        return 'İsim Z–A';
      case SearchSortOrder.brandAsc:
        return 'Marka A–Z';
      case SearchSortOrder.brandDesc:
        return 'Marka Z–A';
      case SearchSortOrder.newestFirst:
        return 'Yeni Eklenenler';
      case SearchSortOrder.energyAsc:
        return 'Kalori: Azdan Çoğa';
      case SearchSortOrder.energyDesc:
        return 'Kalori: Çoktan Aza';
      case SearchSortOrder.proteinsAsc:
        return 'Protein: Azdan Çoğa';
      case SearchSortOrder.proteinsDesc:
        return 'Protein: Çoktan Aza';
      case SearchSortOrder.sugarsAsc:
        return 'Şeker: Azdan Çoğa';
      case SearchSortOrder.sugarsDesc:
        return 'Şeker: Çoktan Aza';
      case SearchSortOrder.fatAsc:
        return 'Yağ: Azdan Çoğa';
      case SearchSortOrder.fatDesc:
        return 'Yağ: Çoktan Aza';
      case SearchSortOrder.saturatedFatAsc:
        return 'Doymuş Yağ: Azdan Çoğa';
      case SearchSortOrder.saturatedFatDesc:
        return 'Doymuş Yağ: Çoktan Aza';
      case SearchSortOrder.saltAsc:
        return 'Tuz: Azdan Çoğa';
      case SearchSortOrder.saltDesc:
        return 'Tuz: Çoktan Aza';
      case SearchSortOrder.fiberAsc:
        return 'Lif: Azdan Çoğa';
      case SearchSortOrder.fiberDesc:
        return 'Lif: Çoktan Aza';
    }
  }
}

/// Per-nutrient filter with bidirectional (En fazla / En az) support.
///
/// Each nutrient has independent max and min fields so a range filter is
/// possible (e.g. protein ≥ 10 g AND ≤ 25 g).
class NutritionFilter {
  // Kalori (kcal)
  final double? maxEnergyKcal;
  final double? minEnergyKcal;

  // Protein (g)
  final double? minProteins;
  final double? maxProteins;

  // Şeker (g)
  final double? maxSugars;
  final double? minSugars;

  // Yağ (g)
  final double? maxFat;
  final double? minFat;

  // Doymuş Yağ (g)
  final double? maxSaturatedFat;
  final double? minSaturatedFat;

  // Tuz (g)
  final double? maxSalt;
  final double? minSalt;

  // Lif (g)
  final double? minFiber;
  final double? maxFiber;

  // Karbonhidrat (g)
  final double? maxCarbohydrates;
  final double? minCarbohydrates;

  const NutritionFilter({
    this.maxEnergyKcal,
    this.minEnergyKcal,
    this.minProteins,
    this.maxProteins,
    this.maxSugars,
    this.minSugars,
    this.maxFat,
    this.minFat,
    this.maxSaturatedFat,
    this.minSaturatedFat,
    this.maxSalt,
    this.minSalt,
    this.minFiber,
    this.maxFiber,
    this.maxCarbohydrates,
    this.minCarbohydrates,
  });

  bool get isEmpty =>
      maxEnergyKcal == null &&
      minEnergyKcal == null &&
      minProteins == null &&
      maxProteins == null &&
      maxSugars == null &&
      minSugars == null &&
      maxFat == null &&
      minFat == null &&
      maxSaturatedFat == null &&
      minSaturatedFat == null &&
      maxSalt == null &&
      minSalt == null &&
      minFiber == null &&
      maxFiber == null &&
      maxCarbohydrates == null &&
      minCarbohydrates == null;

  NutritionFilter copyWith({
    Object? maxEnergyKcal = _absent,
    Object? minEnergyKcal = _absent,
    Object? minProteins = _absent,
    Object? maxProteins = _absent,
    Object? maxSugars = _absent,
    Object? minSugars = _absent,
    Object? maxFat = _absent,
    Object? minFat = _absent,
    Object? maxSaturatedFat = _absent,
    Object? minSaturatedFat = _absent,
    Object? maxSalt = _absent,
    Object? minSalt = _absent,
    Object? minFiber = _absent,
    Object? maxFiber = _absent,
    Object? maxCarbohydrates = _absent,
    Object? minCarbohydrates = _absent,
  }) {
    return NutritionFilter(
      maxEnergyKcal: identical(maxEnergyKcal, _absent)
          ? this.maxEnergyKcal
          : maxEnergyKcal as double?,
      minEnergyKcal: identical(minEnergyKcal, _absent)
          ? this.minEnergyKcal
          : minEnergyKcal as double?,
      minProteins: identical(minProteins, _absent)
          ? this.minProteins
          : minProteins as double?,
      maxProteins: identical(maxProteins, _absent)
          ? this.maxProteins
          : maxProteins as double?,
      maxSugars: identical(maxSugars, _absent)
          ? this.maxSugars
          : maxSugars as double?,
      minSugars: identical(minSugars, _absent)
          ? this.minSugars
          : minSugars as double?,
      maxFat: identical(maxFat, _absent) ? this.maxFat : maxFat as double?,
      minFat: identical(minFat, _absent) ? this.minFat : minFat as double?,
      maxSaturatedFat: identical(maxSaturatedFat, _absent)
          ? this.maxSaturatedFat
          : maxSaturatedFat as double?,
      minSaturatedFat: identical(minSaturatedFat, _absent)
          ? this.minSaturatedFat
          : minSaturatedFat as double?,
      maxSalt: identical(maxSalt, _absent) ? this.maxSalt : maxSalt as double?,
      minSalt: identical(minSalt, _absent) ? this.minSalt : minSalt as double?,
      minFiber: identical(minFiber, _absent)
          ? this.minFiber
          : minFiber as double?,
      maxFiber: identical(maxFiber, _absent)
          ? this.maxFiber
          : maxFiber as double?,
      maxCarbohydrates: identical(maxCarbohydrates, _absent)
          ? this.maxCarbohydrates
          : maxCarbohydrates as double?,
      minCarbohydrates: identical(minCarbohydrates, _absent)
          ? this.minCarbohydrates
          : minCarbohydrates as double?,
    );
  }
}

/// Ingredient-based filter toggles.
class IngredientFilterConfig {
  final bool excludePalmOil;
  final bool excludePreservatives;
  final bool excludeArtificialColorants;
  final bool excludeArtificialSweeteners;
  final bool excludeAddedSugar;

  const IngredientFilterConfig({
    this.excludePalmOil = false,
    this.excludePreservatives = false,
    this.excludeArtificialColorants = false,
    this.excludeArtificialSweeteners = false,
    this.excludeAddedSugar = false,
  });

  bool get isEmpty =>
      !excludePalmOil &&
      !excludePreservatives &&
      !excludeArtificialColorants &&
      !excludeArtificialSweeteners &&
      !excludeAddedSugar;

  IngredientFilterConfig copyWith({
    bool? excludePalmOil,
    bool? excludePreservatives,
    bool? excludeArtificialColorants,
    bool? excludeArtificialSweeteners,
    bool? excludeAddedSugar,
  }) {
    return IngredientFilterConfig(
      excludePalmOil: excludePalmOil ?? this.excludePalmOil,
      excludePreservatives: excludePreservatives ?? this.excludePreservatives,
      excludeArtificialColorants:
          excludeArtificialColorants ?? this.excludeArtificialColorants,
      excludeArtificialSweeteners:
          excludeArtificialSweeteners ?? this.excludeArtificialSweeteners,
      excludeAddedSugar: excludeAddedSugar ?? this.excludeAddedSugar,
    );
  }
}

/// Immutable filter + sort state for the public product search.
class ProductSearchFilter {
  final String query;

  /// Canonical main category (e.g. 'Atıştırmalık').
  final String? mainCategory;

  /// Canonical sub-category (e.g. 'Cips').  Requires [mainCategory] to be set.
  final String? subCategory;

  /// Exact brand name filter. Multiple values are OR-ed.
  final List<String> brands;

  final NutritionFilter nutritionFilter;
  final IngredientFilterConfig ingredientFilter;
  final SearchSortOrder sortOrder;

  const ProductSearchFilter({
    this.query = '',
    this.mainCategory,
    this.subCategory,
    this.brands = const [],
    this.nutritionFilter = const NutritionFilter(),
    this.ingredientFilter = const IngredientFilterConfig(),
    this.sortOrder = SearchSortOrder.relevance,
  });

  bool get hasQuery => query.trim().length >= 2;

  bool get hasActiveFilters =>
      mainCategory != null ||
      subCategory != null ||
      brands.isNotEmpty ||
      !nutritionFilter.isEmpty ||
      !ingredientFilter.isEmpty;

  bool get isNutritionSort {
    switch (sortOrder) {
      case SearchSortOrder.energyAsc:
      case SearchSortOrder.energyDesc:
      case SearchSortOrder.proteinsAsc:
      case SearchSortOrder.proteinsDesc:
      case SearchSortOrder.sugarsAsc:
      case SearchSortOrder.sugarsDesc:
      case SearchSortOrder.fatAsc:
      case SearchSortOrder.fatDesc:
      case SearchSortOrder.saturatedFatAsc:
      case SearchSortOrder.saturatedFatDesc:
      case SearchSortOrder.saltAsc:
      case SearchSortOrder.saltDesc:
      case SearchSortOrder.fiberAsc:
      case SearchSortOrder.fiberDesc:
        return true;
      default:
        return false;
    }
  }

  bool get isNonRelevanceSort => sortOrder != SearchSortOrder.relevance;

  /// DB tags for server-side category_tags overlap filter (main category only).
  List<String> get categoryTagsForFilter => mainCategory != null
      ? CanonicalCategoryMapper.mainCategoryToTags(mainCategory!)
      : const [];

  /// Effective DB tags for server-side filtering, applied BEFORE pagination.
  ///
  /// Returns subcategory-specific tags when [subCategory] is set (to narrow
  /// the server query before `.range()`), or main-category tags otherwise.
  /// Falls back to main-category tags when a subcategory has no specific tag
  /// mapping (i.e. differentiation is name-based only).
  List<String> get effectiveCategoryTagsForServer {
    if (mainCategory == null) return const [];
    if (subCategory != null) {
      final subTags = CanonicalCategoryMapper.subCategoryToTags(
        mainCategory!,
        subCategory!,
      );
      if (subTags.isNotEmpty) return subTags;
    }
    return CanonicalCategoryMapper.mainCategoryToTags(mainCategory!);
  }

  /// A pure description of the category query this filter will send to the DB.
  ///
  /// This is the single authoritative source for all category-scoped server
  /// queries.  The repository must use this plan and must not independently
  /// read [categoryTagsForFilter] or [effectiveCategoryTagsForServer].
  CategoryQueryPlan get queryPlan {
    if (mainCategory == null) return const CategoryQueryPlan();

    if (subCategory == null) {
      return CategoryQueryPlan(
        mainCategoryKey: mainCategory,
        categoryTagsAny: categoryTagsForFilter,
      );
    }

    final subTags = CanonicalCategoryMapper.subCategoryToTags(
      mainCategory!,
      subCategory!,
    );
    final subKeywords = CanonicalCategoryMapper.subCategoryToKeywords(
      mainCategory!,
      subCategory!,
    );
    final requiresClientValidation =
        CanonicalCategoryMapper.subCategoryRequiresClientValidation(
          subCategory!,
        );

    return CategoryQueryPlan(
      mainCategoryKey: mainCategory,
      subcategoryKey: subCategory,
      categoryTagsAny: subTags.isNotEmpty ? subTags : categoryTagsForFilter,
      searchKeywordsAny: subKeywords,
      requiresClientValidation: requiresClientValidation,
    );
  }

  /// Count of optional filters only — main/sub category are browsing context
  /// and must not contribute to the filter-button badge.
  int get activeFilterCount {
    var count = 0;
    count += brands.length;
    if (!nutritionFilter.isEmpty) count++;
    if (!ingredientFilter.isEmpty) count++;
    if (sortOrder != SearchSortOrder.relevance) count++;
    return count;
  }

  ProductSearchFilter copyWith({
    String? query,
    Object? mainCategory = _absent,
    Object? subCategory = _absent,
    List<String>? brands,
    NutritionFilter? nutritionFilter,
    IngredientFilterConfig? ingredientFilter,
    SearchSortOrder? sortOrder,
  }) {
    return ProductSearchFilter(
      query: query ?? this.query,
      mainCategory: identical(mainCategory, _absent)
          ? this.mainCategory
          : mainCategory as String?,
      subCategory: identical(subCategory, _absent)
          ? this.subCategory
          : subCategory as String?,
      brands: brands ?? this.brands,
      nutritionFilter: nutritionFilter ?? this.nutritionFilter,
      ingredientFilter: ingredientFilter ?? this.ingredientFilter,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  ProductSearchFilter clearCategory() =>
      copyWith(mainCategory: null, subCategory: null);

  ProductSearchFilter clearFilters() =>
      ProductSearchFilter(query: query, sortOrder: sortOrder);
}

const _absent = Object();
