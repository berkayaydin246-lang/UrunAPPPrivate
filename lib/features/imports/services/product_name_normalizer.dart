import 'package:food_analyzer_app/features/search/services/product_category_classifier.dart';

/// Utilities for cleaning Open Food Facts product names and building
/// search keyword tokens for Turkish packaged food products.
///
/// Three concerns are kept separate:
///   1. Display name  — what the user sees in the UI (clean, no junk)
///   2. Normalized name — lowercase ASCII-safe version for ilike queries
///   3. Search keywords — token array stored in products.search_keywords
class ProductNameNormalizer {
  ProductNameNormalizer._();

  /// Choose the best user-facing product name from OFF payload.
  ///
  /// Priority:
  /// 1. product_name_tr
  /// 2. product_name (TR-localized response)
  /// 3. abbreviated_product_name_tr
  /// 4. generic_name_tr
  /// 5. product_name
  /// 6. product_name_en
  /// 7. generic_name
  /// 8. fallback label
  static String pickBestProductName(Map<String, dynamic> product) {
    String? s(dynamic v) {
      final text = (v as String?)?.trim();
      if (text == null || text.isEmpty) return null;
      return text;
    }

    return s(product['product_name_tr']) ??
        s(product['product_name']) ??
        s(product['abbreviated_product_name_tr']) ??
        s(product['generic_name_tr']) ??
        s(product['product_name']) ??
        s(product['product_name_en']) ??
        s(product['generic_name']) ??
        'Bilinmeyen Ürün';
  }

  // ── Display name cleaning ─────────────────────────────────────────────────

  /// Clean a raw OFF product name for display in the UI.
  ///
  /// OFF names often look like:
  ///   "Eti Çikolatalı Gofret – eti cikolatali gofret –34g"
  ///   "Banada–Torku–700g"
  ///   "ülker çikolata –20₺"
  ///
  /// Returns a clean, title-cased display name with price/size/duplicate
  /// fragments removed.
  static String cleanDisplayName(String raw, {String? brand}) {
    var s = raw.trim();
    if (s.isEmpty) return s;

    // Normalize separators and split into fragments.
    final rawParts = s
        .split(RegExp(r'\s*[–—]\s*|\s+-\s+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);

    final cleanedParts = <String>[];
    for (final part in rawParts) {
      var candidate = part;

      // Remove price fragments: "20₺", "20 TL", "₺"
      candidate = candidate.replaceAll(
        RegExp(r'\d+[\.,]?\d*\s*(?:₺|TL)', caseSensitive: false),
        '',
      );
      candidate = candidate.replaceAll('₺', '');

      // Remove package sizes: 55 g, 34g, 1 l, 500 ml ...
      candidate = candidate.replaceAll(
        RegExp(
          r'\b\d+[\.,]?\d*\s*(?:kg|gr|g|lt|l|ml|cl|kkal|kcal)\b',
          caseSensitive: false,
        ),
        '',
      );

      candidate = candidate.replaceAll(RegExp(r'[\s\-|,]+$'), '').trim();
      candidate = candidate.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
      if (candidate.isEmpty) continue;

      if (brand != null && brand.trim().isNotEmpty) {
        final brandNorm = toSearchable(brand.trim());
        final candidateNorm = toSearchable(candidate);
        // Remove standalone brand fragment only when brand is shown separately.
        if (candidateNorm == brandNorm) {
          continue;
        }
      }

      cleanedParts.add(candidate);
    }

    if (cleanedParts.isNotEmpty) {
      // Prefer the longest non-brand fragment as display candidate.
      cleanedParts.sort((a, b) => b.length.compareTo(a.length));
      s = cleanedParts.first;
    }

    // Remove exact duplicated phrase fragments: "X - X" style noise.
    s = _dedupeRepeatedFragments(s);

    s = s.replaceAll(RegExp(r'\s{2,}'), ' ').trim();

    // Keep natural casing when string is already well-cased.
    if (_looksMessyOrLowercase(s)) {
      s = _titleCase(s);
    }

    return s;
  }

  // ── Search normalization ──────────────────────────────────────────────────

  /// Convert Turkish characters to ASCII equivalents for keyword storage
  /// and search matching.
  ///
  /// This lets "çikolatalı" match "cikolatali" and vice-versa.
  static String toSearchable(String text) {
    var s = text.toLowerCase().trim();
    s = s
        .replaceAll('ç', 'c')
        .replaceAll('ğ', 'g')
        .replaceAll('ı', 'i')
        .replaceAll('ö', 'o')
        .replaceAll('ş', 's')
        .replaceAll('ü', 'u')
        .replaceAll('â', 'a')
        .replaceAll('î', 'i')
        .replaceAll('û', 'u');
    return s;
  }

  // ── Keyword building ──────────────────────────────────────────────────────

  /// Build a deduplicated list of search keyword tokens from a product's
  /// display name, brand, and optional OFF category tags.
  ///
  /// These are stored in products.search_keywords (TEXT[]) and matched via
  /// PostgreSQL array overlap (&&) queries.
  static List<String> buildSearchKeywords({
    required String displayName,
    String? brand,
    List<String>? offCategories,
  }) {
    final tokens = <String>{};

    // Brand tokens
    if (brand != null && brand.trim().isNotEmpty) {
      final b = brand.trim().toLowerCase();
      tokens.add(b);
      tokens.add(toSearchable(b));
    }

    // Name word tokens
    final words = _splitWords(displayName.toLowerCase());
    for (final word in words) {
      if (word.length < 2) continue;
      tokens.add(word);
      final ascii = toSearchable(word);
      if (ascii != word) tokens.add(ascii);
      // Add synonym expansions
      tokens.addAll(_synonymsFor(word));
      tokens.addAll(_synonymsFor(ascii));
    }

    // OFF category tags: "en:biscuits-and-cakes" → ["biscuits", "cakes"]
    if (offCategories != null) {
      for (final tag in offCategories.take(5)) {
        final cleaned = tag
            .replaceFirst(RegExp(r'^[a-z]{2}:'), '')
            .replaceAll('-', ' ')
            .toLowerCase();
        for (final w in cleaned.split(' ')) {
          if (w.length >= 3) tokens.add(w);
        }
      }
    }

    // Remove noise tokens
    tokens.removeAll(_stopWords);
    return tokens.where((t) => t.length >= 2).toList()..sort();
  }

  /// Build deterministic category tags from normalized keywords and OFF tags.
  ///
  /// Tags are stored in products.category_tags and used for strict category
  /// filtering before relevance scoring.
  static List<String> inferCategoryTags({
    required List<String> searchKeywords,
    List<String>? offCategories,
  }) {
    return ProductCategoryClassifier.classify(
      name: searchKeywords.join(' '),
      searchKeywords: searchKeywords,
      offCategories: offCategories,
    ).categoryTags;
  }

  /// Tokenize a user search query into normalized tokens for matching against
  /// products.search_keywords.
  static List<String> tokenizeQuery(String query) {
    final tokens = <String>{};
    for (final word in _splitWords(query.toLowerCase())) {
      if (word.length < 2) continue;
      tokens.add(word);
      final ascii = toSearchable(word);
      if (ascii != word) tokens.add(ascii);
      tokens.addAll(_synonymsFor(word));
      tokens.addAll(_synonymsFor(ascii));
    }
    tokens.removeAll(_stopWords);
    return tokens.where((t) => t.length >= 2).toList();
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  static String _titleCase(String s) {
    return s
        .split(' ')
        .map((w) {
          if (w.isEmpty) return w;
          final first = switch (w[0]) {
            'i' => 'İ',
            'ı' => 'I',
            _ => w[0].toUpperCase(),
          };
          return first + w.substring(1);
        })
        .join(' ');
  }

  static List<String> _splitWords(String s) {
    return s
        .split(RegExp(r'[\s\-–—,\/\|()]+'))
        .where((w) => w.isNotEmpty)
        .toList();
  }

  static String _dedupeRepeatedFragments(String input) {
    final fragments = input
        .split(RegExp(r'\s*[–—]\s*|\s+-\s+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (fragments.length <= 1) return input;

    final seen = <String>{};
    final out = <String>[];
    for (final f in fragments) {
      final key = toSearchable(f);
      if (seen.add(key)) out.add(f);
    }
    return out.join(' ');
  }

  static bool _looksMessyOrLowercase(String text) {
    if (text.isEmpty) return false;
    final hasUpper = text.contains(RegExp(r'[A-ZÇĞİÖŞÜ]'));
    if (!hasUpper) return true;
    final tooManySeparators = text.contains(RegExp(r'\s{2,}|--|__'));
    return tooManySeparators;
  }

  static List<String> _synonymsFor(String word) {
    return _synonymMap[word] ?? const [];
  }

  // Known Turkish food synonyms (both directions).
  static const _synonymMap = <String, List<String>>{
    'çikolata': ['cikolata', 'chocolate'],
    'çikolatalı': ['cikolatali', 'çikolata', 'cikolata'],
    'cikolata': ['çikolata', 'chocolate'],
    'cikolatali': ['çikolatalı', 'çikolata', 'cikolata'],
    'chocolate': ['çikolata', 'cikolata'],
    'gofret': ['wafer'],
    'wafer': ['gofret'],
    'bisküvi': ['biskuvi', 'biscuit', 'cookie'],
    'biskuvi': ['bisküvi', 'biscuit', 'cookie'],
    'biscuit': ['bisküvi', 'biskuvi'],
    'içecek': ['icecek', 'drink'],
    'icecek': ['içecek', 'drink'],
    'drink': ['içecek', 'icecek'],
    'süt': ['sut', 'milk'],
    'sut': ['süt', 'milk'],
    'milk': ['süt', 'sut'],
    'peynir': ['cheese'],
    'cheese': ['peynir'],
    'yoğurt': ['yogurt', 'yoghurt'],
    'yogurt': ['yoğurt'],
    'makarna': ['pasta'],
    'pasta': ['makarna'],
    'atıştırmalık': ['atistirmalik', 'snack'],
    'atistirmalik': ['atıştırmalık', 'snack'],
    'snack': ['atıştırmalık', 'atistirmalik'],
    'dondurma': ['ice cream', 'icecream'],
    'icecream': ['dondurma'],
    'kek': ['cake'],
    'cake': ['kek'],
    'meyve': ['fruit'],
    'mısır': ['corn', 'misir'],
    'misir': ['mısır', 'corn'],
  };

  static const _stopWords = <String>{
    've',
    'ile',
    'and',
    'the',
    'bir',
    'a',
    'an',
    'g',
    'ml',
    'kg',
    'lt',
    'gr',
    'cl',
    'kkal',
    'kcal',
  };
}
