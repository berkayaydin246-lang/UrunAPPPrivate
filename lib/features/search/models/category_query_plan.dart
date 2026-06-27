/// Describes the database query that should be sent for a given category
/// selection.  Pure value type — no Supabase or Flutter imports, fully testable.
///
/// Built from [ProductSearchFilter.queryPlan].  Callers use [categoryTagsAny]
/// to build a PostgREST `category_tags.ov.{…}` overlap filter and
/// [searchKeywordsAny] for a `search_keywords.ov.{…}` overlap filter, both
/// applied server-side BEFORE the pagination `.range()` call.
class CategoryQueryPlan {
  final String? mainCategoryKey;
  final String? subcategoryKey;

  /// DB `category_tags` values that should be OR-ed (overlap) for this query.
  /// Empty when no category is selected.
  final List<String> categoryTagsAny;

  /// DB `search_keywords` values that should be OR-ed (overlap) to narrow
  /// broad shared-tag subcategories (e.g. kahvaltiliklar → bal/reçel/pekmez).
  /// Applied server-side with AND after [categoryTagsAny].
  final List<String> searchKeywordsAny;

  /// Additional keywords whose presence disqualifies a product.  Unused for
  /// most categories; reserved for future exclusion rules.
  final List<String> excludedKeywords;

  /// True only when server-side tag + keyword filtering cannot fully determine
  /// the subcategory (e.g. makarna/bakliyat/yağ/un all share makarna_bakliyat).
  /// When false, products returned by the server query must NOT be removed by
  /// a client-side canonical-category check.
  final bool requiresClientValidation;

  const CategoryQueryPlan({
    this.mainCategoryKey,
    this.subcategoryKey,
    this.categoryTagsAny = const [],
    this.searchKeywordsAny = const [],
    this.excludedKeywords = const [],
    this.requiresClientValidation = false,
  });

  bool get hasFilter => mainCategoryKey != null;

  @override
  String toString() {
    final sub = subcategoryKey != null ? ' / $subcategoryKey' : '';
    return 'CategoryQueryPlan('
        'main=$mainCategoryKey$sub, '
        'tags=$categoryTagsAny, '
        'keywords=$searchKeywordsAny, '
        'requiresClientValidation=$requiresClientValidation)';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CategoryQueryPlan &&
          mainCategoryKey == other.mainCategoryKey &&
          subcategoryKey == other.subcategoryKey &&
          _listEquals(categoryTagsAny, other.categoryTagsAny) &&
          _listEquals(searchKeywordsAny, other.searchKeywordsAny) &&
          _listEquals(excludedKeywords, other.excludedKeywords) &&
          requiresClientValidation == other.requiresClientValidation;

  @override
  int get hashCode => Object.hash(
    mainCategoryKey,
    subcategoryKey,
    Object.hashAll(categoryTagsAny),
    Object.hashAll(searchKeywordsAny),
    Object.hashAll(excludedKeywords),
    requiresClientValidation,
  );

  static bool _listEquals(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
