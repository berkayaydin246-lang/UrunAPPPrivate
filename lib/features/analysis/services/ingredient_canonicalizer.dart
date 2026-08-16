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
    // "soya lesitini"/"soy lecithin" are deliberately NOT listed here even
    // though they are lecithin (E322) evidence: they explicitly declare a
    // soy source, and collapsing them into the generic "lesitin" canonical
    // key would discard that source information. They are left to resolve
    // through the ingredient catalogue's own source-specific row (matched
    // via its aliases) instead, preserving the distinction between "E322,
    // source unstated" and "E322, soy-derived" the raw label actually draws.
    'lesitin': ['lesitin', 'lesitinler', 'lecithin'],
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
    // E500 (Sodium carbonates) is an official regulatory group covering
    // sodium carbonate, sodium bicarbonate/hydrogen carbonate, and sodium
    // sesquicarbonate as subtypes of the same additive number — these are
    // not distinct E-codes being merged, just documented aliases of E500.
    'sodyum karbonat': [
      'sodyum karbonat',
      'sodyum karbonatlar',
      'sodyum bikarbonat',
      'sodyum bikarbonatlar',
      'sodyum hidrojen karbonat',
      'sodium carbonate',
      'sodium bicarbonate',
      'sodium hydrogen carbonate',
    ],
    // E503 (Ammonium carbonates) likewise covers ammonium carbonate and
    // ammonium bicarbonate/hydrogen carbonate as subtypes of one E-code.
    'amonyum karbonat': [
      'amonyum karbonat',
      'amonyum karbonatlar',
      'amonyum bikarbonat',
      'amonyum bikarbonatlar',
      'amonyum hidrojen karbonat',
      'ammonium carbonate',
      'ammonium bicarbonate',
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
    r'(?:^|[.!?;]\s+)(?:(?:eser miktarda\s+)?[^.!?]+?\s+(?:[İiIı]çereb[İiIı]l[İiIı]r|[İiIı]çer[İiIı]r|bulunab[İiIı]l[İiIı]r)|may contain\s+[^.!?]+)(?:[.!?]\s*(?:aler\w*)?)?$',
    caseSensitive: false,
    dotAll: true,
  );

  static final RegExp _escapedLineBreaks = RegExp(r'\\r\\n|\\n|\\r');

  static const Set<String> _protectedTrailingSingleLetterPrefixes = {
    'vitamin',
    'provitamin',
  };

  static const Set<String> _functionalGroupLabels = {
    'antioksidan',
    'aroma vericiler',
    'asitlik düzenleyici',
    'emülgatör',
    'jelleştirici',
    'kabartıcı',
    'kıvam artırıcı',
    // "arttırıcı" (double t) is a very common misspelling of "artırıcı" on
    // real product labels — same functional class, not a different label.
    'kıvam arttırıcı',
    'koruyucu',
    'renklendirici',
    'stabilizör',
    'tatlandırıcı',
    'topaklanma önleyici',
  };

  static final RegExp _percentageOnly = RegExp(
    r'^\s*(?:%\s*)?\d+(?:[.,]\d+)?\s*%?\s*$',
  );

  // Up to three words immediately followed by a colon — a broad capture,
  // deliberately not limited to the exact known label spellings, so plural
  // forms ("kabartıcılar:", "emülgatörler:") are also captured. The actual
  // label decision happens afterward via _isFunctionalGroupLabel on the
  // normalized (plural-stripped) text, not via this regex alone.
  static final RegExp _wordsBeforeColon = RegExp(
    r'([A-Za-zÇĞİÖŞÜçğıöşüİı]+(?:\s+[A-Za-zÇĞİÖŞÜçğıöşüİı]+){0,2})\s*:\s*',
  );

  // Matches the end of a bracket-delimited ingredient composition list
  // followed by a new, unrelated declaration sentence (e.g. a minimum
  // cocoa/milk-solids disclosure) — only when no further composition
  // bracket appears anywhere after it, so this never truncates legitimate
  // further ingredient content.
  static final RegExp _trailingDeclarationAfterComposition = RegExp(
    r'[)\]](?![\s\S]*[()\[\]])\s*\.\s*[A-ZÇĞİÖŞÜ][\s\S]*$',
  );

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

    // Common OCR corrections and plural -> singular normalizations.
    // "digliserid" (d) is a common spelling variant of "digliserit" (t) for
    // the same E471 substance, not a different additive.
    s = s.replaceAllMapped(
      RegExp(
        r'\b(digliseritleri|digliseritler|digliseridleri|digliseridler)\b',
      ),
      (_) => 'digliseritler',
    );
    s = s.replaceAllMapped(RegExp(r'\bdigliserid\b'), (_) => 'digliserit');
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
    // Decimal commas are evidence delimiters, not child-ingredient separators.
    final parts = _splitInnerParts(innerRaw);
    for (var p in parts) {
      p = p.trim();
      if (p.isEmpty || _percentageOnly.hasMatch(p)) continue;
      // Normalize hyphenated constructs like 'mono- ve digliseritleri' -> 'mono ve digliseritleri'
      p = p.replaceAll('-', ' ');
      p = p.replaceAll(RegExp(r'\s+'), ' ').trim();

      // Specific canonical phrases first.
      final lowered = p.toLowerCase();
      // "digliserid" (d) is a common spelling variant of "digliserit" (t)
      // for the same E471 substance, not a different additive.
      if (lowered.contains('mono') &&
          (lowered.contains('digliserit') || lowered.contains('digliserid'))) {
        out.add('mono ve digliseritler');
        _appendLeftoverNestedContent(p, out);
        continue;
      }
      if (lowered.contains('lesitin')) {
        out.add('lesitin');
        // A doubly-nested source declaration like "lesitin (soya" can reach
        // here as one unsplit chunk (the non-nested-paren-aware capture
        // regex above stops at the first closing paren). Without this, the
        // source ingredient (e.g. soya, an allergen-relevant ordinary food
        // token) would be silently discarded instead of derived alongside
        // "lesitin".
        _appendLeftoverNestedContent(p, out);
        continue;
      }
      if (lowered.contains('sodyum karbonat')) {
        out.add('sodyum karbonat');
        _appendLeftoverNestedContent(p, out);
        continue;
      }
      if (lowered.contains('kalsiyum karbonat')) {
        out.add('kalsiyum karbonat');
        _appendLeftoverNestedContent(p, out);
        continue;
      }
      if (lowered.contains('malt ekstrakt')) {
        out.add('malt ekstraktı');
        _appendLeftoverNestedContent(p, out);
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

  /// Appends any leftover nested-parenthetical content trailing a matched
  /// canonical-phrase shortcut (e.g. the "(soya" in "lesitin (soya", left
  /// unsplit because the outer non-nested-aware paren capture stops at the
  /// first closing paren) so it is not silently discarded. The leftover is
  /// only ever simple source/qualifier text (never itself another
  /// canonical-phrase trigger for these shortcuts), so it is added as-is
  /// rather than recursively re-derived.
  static void _appendLeftoverNestedContent(String part, List<String> out) {
    final openIndex = part.indexOf('(');
    if (openIndex < 0) return;
    final leftover = part
        .substring(openIndex + 1)
        .replaceAll(RegExp(r'[()]'), '');
    for (final piece in _splitInnerParts(leftover)) {
      final cleaned = piece.trim();
      if (cleaned.isNotEmpty && !_percentageOnly.hasMatch(cleaned)) {
        out.add(cleaned);
      }
    }
  }

  /// Wraps "functionalLabel: child" into "functionalLabel (child)" so the
  /// existing paren-aware label/child suppression logic in
  /// [parseIngredientsAdvanced] can treat colon-introduced children exactly
  /// like parenthetical ones. Only wraps when the text immediately before
  /// the colon normalizes to a known functional group label — any other
  /// colon (including ones already stripped earlier as section headings) is
  /// left untouched for the existing blanket colon-to-comma fallback.
  ///
  /// The child span is bounded by the next top-level comma/semicolon/
  /// newline, tracked with its own paren-depth counter so it works whether
  /// the label appears at the top level or already nested inside another
  /// compound ingredient's own parenthetical breakdown.
  static String _wrapFunctionalLabelColonChildren(String text) {
    final buffer = StringBuffer();
    var i = 0;
    while (i < text.length) {
      final match = _wordsBeforeColon.matchAsPrefix(text, i);
      final label = match?.group(1);
      if (match != null &&
          label != null &&
          _isFunctionalGroupLabel(normalizeToken(label))) {
        var j = match.end;
        var relativeDepth = 0;
        while (j < text.length) {
          final c = text[j];
          if (c == '(') {
            relativeDepth++;
            j++;
            continue;
          }
          if (c == ')') {
            // A close paren at relative depth 0 belongs to an enclosing
            // scope, not to this label's child — stop before consuming it.
            if (relativeDepth == 0) break;
            relativeDepth--;
            j++;
            continue;
          }
          if (relativeDepth == 0 && (c == ',' || c == ';' || c == '\n')) {
            break;
          }
          j++;
        }
        final child = text.substring(match.end, j).trim();
        buffer.write(label);
        if (child.isNotEmpty) {
          buffer.write(' (');
          buffer.write(child);
          buffer.write(')');
        }
        i = j;
        continue;
      }
      buffer.write(text[i]);
      i++;
    }
    return buffer.toString();
  }

  static List<String> _splitInnerParts(String value) {
    final parts = <String>[];
    final buffer = StringBuffer();

    void flush() {
      final part = buffer.toString().trim();
      buffer.clear();
      if (part.isNotEmpty) parts.add(part);
    }

    for (var index = 0; index < value.length; index++) {
      final character = value[index];
      final decimalComma =
          character == ',' &&
          index > 0 &&
          index + 1 < value.length &&
          _isAsciiDigit(value[index - 1]) &&
          _isAsciiDigit(value[index + 1]);
      if (!decimalComma &&
          (character == ',' || character == '/' || character == ';')) {
        flush();
        continue;
      }
      buffer.write(character);
    }
    flush();
    return parts;
  }

  static bool _isAsciiDigit(String value) =>
      value.codeUnitAt(0) >= 48 && value.codeUnitAt(0) <= 57;

  static bool _isFunctionalGroupLabel(String value) =>
      _functionalGroupLabels.contains(value);

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

    ingredientText = _stripTrailingDeclarationAfterComposition(ingredientText);
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
    // Functional-class labels followed by a colon (e.g. "emülgatör: lesitin
    // (soya)") must be wrapped into the same "label (child)" shape a
    // parenthetical label already gets, BEFORE colons are flattened to
    // commas below — otherwise the colon-comma conversion splits the label
    // from its declared child and the label leaks through as a false
    // unresolved additive blocker (its child is discovered and canonicalized
    // separately, but the label itself is orphaned).
    var s = _wrapFunctionalLabelColonChildren(cleaned.ingredientsText);
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

      final outerBase = tokenRaw.split('(').first;
      final outer = mapToCanonical(normalizeToken(outerBase));
      final innerParts = <String>[];
      final parenMatches = RegExp(r'\(([^)]*)\)').allMatches(tokenRaw);
      for (final m in parenMatches) {
        final innerRaw = m.group(1) ?? '';
        if (innerRaw.trim().isEmpty) continue;
        final derived = _deriveInnerForms(outer, innerRaw);
        for (final d in derived) {
          final nd = normalizeToken(d);
          if (nd.isNotEmpty) innerParts.add(nd);
        }
      }

      // A declared child substance carries the additive identity. Keeping the
      // functional parent as another token would create a false unresolved
      // additive. Unspecified labels such as "aroma vericiler" remain intact.
      if (outer.isNotEmpty &&
          !(_isFunctionalGroupLabel(outer) && innerParts.isNotEmpty)) {
        parts.add(outer);
      }
      parts.addAll(innerParts);
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

  /// Removes a trailing declaration sentence (e.g. a minimum cocoa/milk
  /// solids disclosure) that immediately follows the close of a
  /// bracket-delimited compound-ingredient composition list, such as
  /// "...aroma verici]. Bitter çikolata min. %55 kakao kuru maddesi
  /// içermektedir." Without this, the parser has no comma to flush on and
  /// the declaration sentence gets glued onto the last ingredient token,
  /// producing a garbled, misleading blocker instead of correctly ending
  /// the ingredient list at the composition's closing bracket.
  static String _stripTrailingDeclarationAfterComposition(String text) {
    final match = _trailingDeclarationAfterComposition.firstMatch(text);
    if (match == null) return text;
    return text.substring(0, match.start + 1);
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
