/// Small normalization utilities used by the Open Food Facts import.
class ImportNormalizer {
  /// Normalize barcode: trim whitespace and remove embedded spaces.
  static String normalizeBarcode(String raw) {
    return raw.trim().replaceAll(' ', '');
  }

  /// Normalize Turkish characters and common whitespace
  static String normalizeText(String input) {
    var s = input.trim();

    // Normalize newlines & separators to commas
    s = s.replaceAll('\n', ',');
    s = s.replaceAll(';', ',');
    s = s.replaceAll('•', ',');
    s = s.replaceAll('·', ',');
    s = s.replaceAll(' - ', ', ');

    // Normalize spacing around commas
    s = s.replaceAll(RegExp(r'\s*,\s*'), ', ');

    // Turkish character mapping (keep proper Turkish letters)
    s = s.replaceAll('İ', 'i');
    s = s.replaceAll('I', 'ı');
    s = s.replaceAll('Ş', 'ş');
    s = s.replaceAll('Ğ', 'ğ');
    s = s.replaceAll('Ü', 'ü');
    s = s.replaceAll('Ö', 'ö');
    s = s.replaceAll('Ç', 'ç');

    // Lowercase final
    s = s.toLowerCase();

    // Normalize e-codes like e100, e-100 -> E100
    s = s.replaceAllMapped(
      RegExp(r'\be-?\s?(\d{2,3})\b', caseSensitive: false),
      (m) => 'E${m[1]}',
    );

    // Remove duplicate commas and trim
    s = s.replaceAll(RegExp(r',\s*,+'), ',');
    s = s.replaceAll(RegExp(r',\s*\$'), '');
    s = s.replaceAll(RegExp(r'\s{2,}'), ' ');

    return s.trim();
  }

  /// Clean ingredient list into a readable single-line text
  static String cleanIngredientsText(String? raw) {
    if (raw == null) return '';
    final n = normalizeText(raw);
    // Ensure commas as separators
    final cleaned = n.replaceAll(RegExp(r'\s*,\s*'), ', ');
    return cleaned;
  }
}
