class CleanedIngredientText {
  const CleanedIngredientText({
    required this.ingredientsText,
    this.allergenText,
  });

  final String ingredientsText;
  final String? allergenText;

  bool get hasIngredientsText => ingredientsText.trim().isNotEmpty;
  bool get hasAllergenText => allergenText?.trim().isNotEmpty == true;
}

/// Ingredient canonicalization utilities.
///
/// Provides deterministic normalization and canonical mapping for common
/// Turkish/English ingredient variants, E-code variants, OCR mistakes and
/// separator inconsistencies.
class IngredientCanonicalizer {
  /// Small canonical map: canonical -> known variants (Turkish, English, OCR)
  /// Expand this map as the DB grows. Keep deterministic, no AI.
  static final Map<String, List<String>> _canonicalVariants = {
    'sodyum nitrit': [
      'sodyum nitrit',
      'sodium nitrite',
      'nitrit',
      'sodym nitrit', // common OCR
      'sodym',
    ],
    'tuz': ['tuz', 'salt'],
    'şeker': ['şeker', 'sugar', 'toz şeker', 'toz seker'],

    'bitkisel yağlar': [
      'bitkisel yağlar',
      'bitkisel yağ',
      'vegetable oils',
      'bitkisel yaglar',
    ],
    'palm yağı': ['palm', 'palm yağı', 'palmiye yağı', 'palm oil', 'palm fat'],
    'ayçiçek yağı': [
      'ayçiçek',
      'ayçiçek yağı',
      'aycicek yagi',
      'yüksek oleik asitli ayçiçek yağı',
      'yüksek oleik ayçiçek yağı',
      'sunflower oil',
      'high oleic sunflower oil',
    ],
    'mısır yağı': [
      'mısır yağı',
      'misir yagi',
      'değişen miktarlarda mısır yağı',
      'corn oil',
      'maize oil',
    ],
    'kanola yağı': ['kanola', 'kanola yağı', 'canola oil', 'rapeseed oil'],
    'patates': ['patates', 'potato'],

    'mono ve digliseritler': [
      'mono ve digliseritler',
      'mono ve digliserit',
      'mono- ve digliseritler',
      'mono- ve digliserit',
      'yağ asitlerinin mono ve digliseritleri',
      'yağ asitlerinin mono- ve digliseritleri',
      'e471',
    ],
    'lesitin': [
      'lesitin',
      'lesitinler',
      'soya lesitini',
      'soy lecithin',
      'lecithin',
    ],
    'emülgatör': ['emülgatör', 'emulgator', 'emulsifier'],

    'antioksidan': ['antioksidan', 'antioxidant', 'antioksidanlar'],
    'tokoferolce zengin ekstrakt': [
      'tokoferolce zengin ekstrakt',
      'tokoferolce zengin özü',
      'mixed tocopherols',
    ],

    'patlamış pirinç': ['patlamış pirinç', 'popped rice'],
    'pirinç unu': ['pirinç unu', 'rice flour'],
    'malt ekstraktı': ['malt ekstraktı', 'arpa malt ekstraktı', 'malt extract'],
    'kabartıcı': [
      'kabartıcı',
      'kabartıcılar',
      'raising agent',
      'kabartma tozu',
    ],
    'kalsiyum karbonat': ['kalsiyum karbonat', 'calcium carbonate'],
    'sodyum karbonat': [
      'sodyum karbonat',
      'sodyum karbonatlar',
      'sodium carbonate',
    ],
    'kakao tozu': [
      'kakao tozu',
      'yağı azaltılmış kakao tozu',
      'yağsız kakao tozu',
      'cocoa powder',
    ],
    'fındık': ['fındık', 'fındık püresi', 'hazelnut'],
    'süt tozu': ['süt tozu', 'yağsız süt tozu', 'milk powder'],
    'aroma vericiler': [
      'aroma vericiler',
      'aroma verici',
      'aroma vericiler',
      'flavoring',
    ],
  };

  static final RegExp _ingredientHeadingAtStart = RegExp(
    r'^\s*(?:[İiIı]çindekiler|içerik|ingredients)\s*[:\-]?\s*',
    caseSensitive: false,
  );

  static final RegExp _ingredientHeadingAnywhere = RegExp(
    r'(?:^|\n)\s*(?:[İiIı]çindekiler|içerik|ingredients)\s*[:\-]?\s*',
    caseSensitive: false,
  );

  static final RegExp _allergenHeading = RegExp(
    r'(?:^|\n|[.!?;,]\s+)\s*(?:alerjen uyarısı|alerjen bilgisi|alerjenler|alerjen|allergen warning|allergen information|allergens?|may contain)\s*[:\-]?\s*',
    caseSensitive: false,
  );

  static final RegExp _sectionHeading = RegExp(
    r'(?:^|\n|[.!?]\s+)\s*(?:besin değerleri|besin öğeleri|saklama koşulları|kullanım önerisi|kullanım önerileri|menşei|net miktar|işletme kayıt no|işletmeci / üretici / ithalatçı / dağıtıcı(?: numarası)?|ürün bilgilerini kullanma hakkında)\s*[:\-]?\s*',
    caseSensitive: false,
  );

  static final RegExp _inlineAllergenTail = RegExp(
    r'(?:^|[.!?;,]\s+)(?:eser miktarda\s+.+?(?:içerebilir|içerir)|may contain\s+.+)$',
    caseSensitive: false,
    dotAll: true,
  );

  static final RegExp _escapedLineBreaks = RegExp(r'\\r\\n|\\n|\\r');

  static const Set<String> _protectedTrailingSingleLetterPrefixes = {
    'vitamin',
    'provitamin',
  };

  /// E-code canonicalization: normalize variants to 'e###' lowercase
  static String normalizeECode(String input) {
    final m = RegExp(
      r'e\s*[-:]?\s*(\d{2,3})',
      caseSensitive: false,
    ).firstMatch(input);
    if (m != null) {
      return 'e${m[1]}'.toLowerCase();
    }
    // If already clean like E250 or e250
    final clean = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (clean.length >= 2 && clean.length <= 3) return 'e$clean';
    return input.toLowerCase();
  }

  /// Normalize a token: trim, lower, remove extra punctuation, normalize turkish chars
  static String normalizeToken(String token) {
    var s = token.trim();
    if (s.isEmpty) return s;

    // Replace common bullets/separators with comma handled in parser
    s = s.replaceAll('\n', ' ');
    s = s.replaceAll(';', ',');
    s = s.replaceAll('•', ',');
    s = s.replaceAll('·', ',');

    // Remove percentages like ( %2 ), (%8.7) or %2,5
    s = s.replaceAll(RegExp(r'%\s*\d+(?:[.,]\d+)?'), '');
    s = s.replaceAll(RegExp(r'\(\s*%?\s*\d+(?:[.,]\d+)?(?:\s*%?)?\s*\)'), '');
    s = s.replaceAll(
      RegExp(r'\bdeğişen miktarlarda\b', caseSensitive: false),
      '',
    );

    // Remove surrounding punctuation while preserving parentheses content for parsing.
    s = s.replaceAll(RegExp(r'^[\-–—\s.,:]+|[\-–—\s.,:]+$'), '');
    s = s.replaceAll(RegExp(r'[\[\]{}]'), '');

    // Normalize Turkish-specific uppercase to lowercase preserving dotted/dotless i
    s = s.replaceAll('İ', 'i');
    s = s.replaceAll('I', 'ı');
    s = s.toLowerCase();

    // Normalize multiple spaces and separators
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    s = s.replaceAll(RegExp(r',\s*,'), ',');

    // Normalize E-codes inline
    s = s.replaceAllMapped(
      RegExp(r'e[\s\-:]*?(\d{2,3})', caseSensitive: false),
      (m) => 'e${m[1]}',
    );

    // Common OCR corrections and plural -> singular normalizations
    s = s.replaceAllMapped(
      RegExp(r'\b(digliseritleri|digliseritler)\b'),
      (_) => 'digliseritler',
    );
    s = s.replaceAllMapped(RegExp(r'\b(lesitinler)\b'), (_) => 'lesitin');
    s = _stripTurkishPluralSuffixes(s);
    s = _stripPossessiveSuffixes(s);

    return s.trim();
  }

  static String _stripTurkishPluralSuffixes(String s) {
    return s.replaceAllMapped(RegExp(r'(lar|ler|ları|leri)\b'), (m) => '');
  }

  static String _stripPossessiveSuffixes(String s) {
    s = s.replaceAllMapped(
      RegExp(r'(lerinin|larının|inin|ının|unun|ünün|nın|nin)\b'),
      (m) => '',
    );
    return s;
  }

  /// Derive context-aware inner forms based on outer category.
  /// Examples:
  ///  - bitkisel yağlar (ayçiçek, palm) -> ['ayçiçek yağı','palm yağı']
  ///  - emülgatör (yağ asitlerinin mono- ve digliseritleri) -> ['mono ve digliseritler']
  static List<String> _deriveInnerForms(String outer, String innerRaw) {
    final out = <String>[];
    // Split inner by comma/slash/semicolon; avoid splitting on "ve" globally
    // because phrases like "mono- ve digliseritleri" should stay together.
    final parts = innerRaw.split(RegExp(r',|/|;'));
    for (var p in parts) {
      p = p.trim();
      if (p.isEmpty) continue;
      // Normalize hyphenated constructs like 'mono- ve digliseritleri' -> 'mono ve digliseritleri'
      p = p.replaceAll('-', ' ');
      p = p.replaceAll(RegExp(r'\s+'), ' ').trim();

      // Specific canonical phrases first.
      final lowered = p.toLowerCase();
      if (lowered.contains('mono') && lowered.contains('digliserit')) {
        out.add('mono ve digliseritler');
        continue;
      }
      if (lowered.contains('lesitin')) {
        out.add('lesitin');
        continue;
      }
      if (lowered.contains('sodyum karbonat')) {
        out.add('sodyum karbonat');
        continue;
      }
      if (lowered.contains('kalsiyum karbonat')) {
        out.add('kalsiyum karbonat');
        continue;
      }
      if (lowered.contains('malt ekstrakt')) {
        out.add('malt ekstraktı');
        continue;
      }

      // If outer mentions oils, append 'yağı' when inner is simple name
      final outerLower = outer.toLowerCase();
      if (outerLower.contains('yağ')) {
        final cand = _stripPossessiveSuffixes(_stripTurkishPluralSuffixes(p));
        if (!cand.contains('yağ')) {
          out.add('$cand yağı');
        } else {
          out.add(cand);
        }
        continue;
      }

      // If inner contains phrases like 'yağ asitleri' followed by 'mono ve digliseritleri'
      // try to extract the latter
      var cleaned = lowered;
      cleaned = cleaned.replaceAll(RegExp(r'yağ asitleri|yağ asitlerinin'), '');
      cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (cleaned.isNotEmpty) out.add(cleaned);
    }

    return out;
  }

  static CleanedIngredientText cleanIngredientTextForAnalysis(String raw) {
    final normalized = _normalizeRawText(raw);
    if (normalized.isEmpty) {
      return const CleanedIngredientText(ingredientsText: '');
    }

    var text = normalized;
    final ingredientHeadingMatch = _ingredientHeadingAnywhere.firstMatch(text);
    if (ingredientHeadingMatch != null && ingredientHeadingMatch.start <= 24) {
      text = text.substring(ingredientHeadingMatch.end);
    }
    text = _trimLeadingIngredientHeadings(text);

    final allergenMatch = _allergenHeading.firstMatch(text);
    final stopMatch = _sectionHeading.firstMatch(text);
    final ingredientEnd =
        _firstIndex(allergenMatch?.start, stopMatch?.start) ?? text.length;

    var ingredientText = text.substring(0, ingredientEnd);
    String? allergenText;

    if (allergenMatch != null &&
        allergenMatch.start < (stopMatch?.start ?? text.length)) {
      final afterAllergen = text.substring(allergenMatch.end);
      final allergenStop = _sectionHeading.firstMatch(afterAllergen);
      allergenText = allergenStop == null
          ? afterAllergen
          : afterAllergen.substring(0, allergenStop.start);
    } else {
      final inlineAllergen = _inlineAllergenTail.firstMatch(ingredientText);
      if (inlineAllergen != null) {
        allergenText = inlineAllergen.group(0);
        ingredientText = ingredientText.substring(0, inlineAllergen.start);
      }
    }

    ingredientText =
        _cleanupSectionText(ingredientText, stripTrailingSingleLetter: true) ??
        '';
    allergenText = _cleanupSectionText(
      allergenText,
      stripTrailingSingleLetter: false,
    );

    return CleanedIngredientText(
      ingredientsText: ingredientText,
      allergenText: allergenText?.isEmpty == true ? null : allergenText,
    );
  }

  static String cleanIngredientTextForDisplay(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) {
      return '';
    }

    final cleaned = cleanIngredientTextForAnalysis(value).ingredientsText;
    if (cleaned.isEmpty) {
      return '';
    }

    return cleaned
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n[ \t]+'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  static List<String> extractAllergenTokens(String raw) {
    final cleaned = cleanIngredientTextForAnalysis(raw);
    final allergenText = cleaned.allergenText?.trim();
    if (allergenText == null || allergenText.isEmpty) {
      return const [];
    }

    var normalized = _normalizeRawText(allergenText);
    normalized = normalized
        .replaceAll(
          RegExp(
            r'^\s*(?:alerjen uyarısı|alerjen bilgisi|alerjenler|alerjen)\s*[:\-]?\s*',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(RegExp(r'\beser miktarda\b', caseSensitive: false), '')
        .replaceAll(
          RegExp(
            r'\b(?:içerebilir|içerir|bulunabilir|may contain|contains)\b',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(RegExp(r'[.!?]+$'), '')
        .trim();

    if (normalized.isEmpty) {
      return const [];
    }

    final parts = <String>[];
    final buffer = StringBuffer();
    var parenDepth = 0;

    void flush() {
      final rawToken = buffer.toString().trim();
      buffer.clear();
      if (rawToken.isEmpty) return;
      final token = mapToCanonical(normalizeToken(rawToken));
      if (token.isNotEmpty) {
        parts.add(token);
      }
    }

    final source = normalized
        .replaceAll('\n', ',')
        .replaceAll(';', ',')
        .replaceAll('•', ',')
        .replaceAll('·', ',');

    for (var i = 0; i < source.length; i++) {
      final ch = source[i];
      if (ch == '(') {
        parenDepth++;
      } else if (ch == ')') {
        if (parenDepth > 0) parenDepth--;
      }

      if (parenDepth == 0 && (ch == ',' || ch == '/')) {
        flush();
        continue;
      }
      buffer.write(ch);
    }
    flush();

    final seen = <String>{};
    final deduped = <String>[];
    for (final part in parts) {
      if (part.isEmpty || !seen.add(part)) continue;
      deduped.add(part);
    }
    return deduped;
  }

  /// Advanced parser: splits a raw ingredients string into tokens handling
  /// bullets, semicolons, nested parentheses, additive groups, percentages
  /// and deduplication.
  static List<String> parseIngredientsAdvanced(String raw) {
    if (raw.trim().isEmpty) return [];

    final cleaned = cleanIngredientTextForAnalysis(raw);
    if (!cleaned.hasIngredientsText) {
      return const [];
    }

    // Normalize separators and keep parentheses for inner extraction.
    var s = cleaned.ingredientsText;
    s = s.replaceAll('\n', ',');
    s = s.replaceAll('•', ',');
    s = s.replaceAll('·', ',');
    s = s.replaceAll(';', ',');
    s = s.replaceAll(':', ',');

    final parts = <String>[];
    final buffer = StringBuffer();
    var parenDepth = 0;

    void flushBufferToParts() {
      final tokenRaw = buffer.toString().trim();
      buffer.clear();
      if (tokenRaw.isEmpty) return;

      // Normalize the outer token first, but strip any parenthetical details
      // so we don't leak broken fragments into the output.
      final outerBase = tokenRaw.split('(').first;
      final outer = mapToCanonical(normalizeToken(outerBase));
      if (outer.isNotEmpty) parts.add(outer);

      // Extract inner parentheses groups and derive context-aware tokens
      final parenMatches = RegExp(r'\(([^)]*)\)').allMatches(tokenRaw);
      for (final m in parenMatches) {
        final innerRaw = m.group(1) ?? '';
        if (innerRaw.trim().isEmpty) continue;
        final derived = _deriveInnerForms(outer, innerRaw);
        for (final d in derived) {
          final nd = normalizeToken(d);
          if (nd.isNotEmpty) parts.add(nd);
        }
      }
    }

    for (var i = 0; i < s.length; i++) {
      final ch = s[i];
      if (ch == '(') {
        parenDepth++;
        buffer.write(ch);
        continue;
      }
      if (ch == ')') {
        if (parenDepth > 0) parenDepth--;
        buffer.write(ch);
        continue;
      }
      // Separators at top level flush token.
      if ((ch == ',' || ch == '\u2022') && parenDepth == 0) {
        flushBufferToParts();
        continue;
      }
      buffer.write(ch);
    }

    // final flush
    flushBufferToParts();

    // Post-process: split combined tokens by '/' that may remain
    final expanded = <String>[];
    for (final p in parts) {
      if (p.contains('(') || p.contains(')')) {
        expanded.add(mapToCanonical(normalizeToken(p)));
        continue;
      }
      final splits = p.split(RegExp(r'[/]'));
      for (final sp in splits) {
        final clean = mapToCanonical(normalizeToken(sp));
        if (clean.isNotEmpty) expanded.add(clean);
      }
    }

    // Remove duplicates preserving order
    final seen = <String>{};
    final out = <String>[];
    for (final tok in expanded) {
      final t = mapToCanonical(tok.replaceAll(RegExp(r'%'), '').trim());
      if (t.isEmpty) continue;
      if (seen.contains(t)) continue;
      seen.add(t);
      out.add(t);
    }

    return out;
  }

  /// Attempt to map a token to canonical ingredient name using the canonical map.
  /// Returns canonical name if found, otherwise returns the input token.
  static String mapToCanonical(String token) {
    final t = normalizeToken(token);
    // e-code quick path
    if (RegExp(r'^e\d{2,3}$').hasMatch(t)) return t;

    for (final entry in _canonicalVariants.entries) {
      final canonical = entry.key;
      for (final variant in entry.value) {
        if (normalizeToken(variant) == t) return canonical;
      }
    }

    return t;
  }

  static String _normalizeRawText(String raw) {
    var text = raw
        .replaceAll(_escapedLineBreaks, '\n')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('\u00a0', ' ');

    text = text.replaceAll(RegExp(r'[ \t]+\n'), '\n');
    text = text.replaceAll(RegExp(r'\n[ \t]+'), '\n');
    text = text.replaceAll(RegExp(r'[ \t]+'), ' ');
    text = text.replaceAll(RegExp(r'\n{2,}'), '\n');
    return text.trim();
  }

  static String _trimLeadingIngredientHeadings(String text) {
    var value = text.trim();
    while (true) {
      final next = value.replaceFirst(_ingredientHeadingAtStart, '').trim();
      if (next == value) {
        return value;
      }
      value = next;
    }
  }

  static String? _cleanupSectionText(
    String? input, {
    required bool stripTrailingSingleLetter,
  }) {
    if (input == null) {
      return null;
    }

    var text = input
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n[ \t]+'), '\n')
        .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
        .trim();

    text = text.replaceAll(RegExp(r'^[,;:.\-–—\s]+|[,;:.\-–—\s]+$'), '');
    text = _trimLeadingIngredientHeadings(text);
    text = text.replaceAll(RegExp(r'\n{2,}'), '\n').trim();

    if (stripTrailingSingleLetter) {
      text = _stripTrailingSectionLetterArtifact(text);
    }

    return text.trim();
  }

  static String _stripTrailingSectionLetterArtifact(String text) {
    final match = RegExp(
      r'^(.*(?:,|;|\n)\s*[^,;\n]+?)\s+([A-Za-zÇĞİÖŞÜçğıöşü])$',
    ).firstMatch(text.trim());
    if (match == null) {
      return text.trim();
    }

    final body = (match.group(1) ?? '').trimRight();
    if (body.isEmpty) {
      return text.trim();
    }

    final lastWordMatch = RegExp(
      r'([A-Za-zÇĞİÖŞÜçğıöşü]+)\s*$',
    ).firstMatch(body);
    final lastWord = normalizeToken(lastWordMatch?.group(1) ?? '');
    if (_protectedTrailingSingleLetterPrefixes.contains(lastWord)) {
      return text.trim();
    }

    return body.replaceAll(RegExp(r'[ \t]+$'), '');
  }

  static int? _firstIndex(int? a, int? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a < b ? a : b;
  }

  /*
  Examples / quick tests (in-code):

  final raw = 'Un, su, sodym nitrit (E-250), tuz; yağ %2';
  parseIngredientsAdvanced(raw) -> ['un', 'su', 'sodyum nitrit', 'e250', 'tuz', 'yag']

  */
}
