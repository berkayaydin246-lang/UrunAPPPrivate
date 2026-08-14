import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/analysis/models/ingredient_match.dart';
import 'package:food_analyzer_app/features/analysis/services/ingredient_canonicalizer.dart';
import 'package:food_analyzer_app/features/analysis/services/unknown_ingredient_sanitizer.dart';
import 'package:food_analyzer_app/features/product/models/ingredient.dart';

Ingredient _ingredient({
  required String id,
  required String name,
  required String normalizedName,
  String riskLevel = 'low',
}) {
  final now = DateTime(2026, 5, 12);
  return Ingredient(
    id: id,
    name: name,
    normalizedName: normalizedName,
    riskLevel: riskLevel,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  test('cleans trailing Migros section-letter artifact', () {
    const input = 'BEYAZ LEBLEBİ, TUZ A';

    final cleaned = IngredientCanonicalizer.cleanIngredientTextForAnalysis(
      input,
    );

    expect(cleaned.ingredientsText, 'BEYAZ LEBLEBİ, TUZ');
  });

  test('keeps legitimate vitamin A ending while trimming bleed artifacts', () {
    const input = 'Şeker, vitamin A';

    final cleaned = IngredientCanonicalizer.cleanIngredientTextForAnalysis(
      input,
    );

    expect(cleaned.ingredientsText, 'Şeker, vitamin A');
  });

  test('cleans literal escaped line breaks for display', () {
    const input = r'Su\r\nElma püresi\nTuz';

    expect(
      IngredientCanonicalizer.cleanIngredientTextForDisplay(input),
      'Su\nElma püresi\nTuz',
    );
  });

  test('cleans actual line breaks for display', () {
    const input = 'Su\r\nElma püresi\nTuz';

    expect(
      IngredientCanonicalizer.cleanIngredientTextForDisplay(input),
      'Su\nElma püresi\nTuz',
    );
  });

  test('parses and canonicalizes the production sample cleanly', () {
    const input =
        'Şeker, bitkisel yağlar (ayçiçek, palm), emülgatör (yağ asitlerinin mono- ve digliseritleri), antioksidan (tokoferolce zengin ekstrakt), patlamış pirinç, pirinç unu, arpa malt ekstraktı, kabartıcı (kalsiyum karbonat), yağı azaltılmış kakao tozu, fındık püresi, yağsız süt tozu, emülgatör (lesitinler), aroma vericiler, tuz, kabartıcı (sodyum karbonatlar)';

    final tokens = IngredientCanonicalizer.parseIngredientsAdvanced(input);

    expect(
      tokens,
      containsAllInOrder(<String>[
        'şeker',
        'bitkisel yağlar',
        'ayçiçek yağı',
        'palm yağı',
        'mono ve digliseritler',
        'tokoferolce zengin ekstrakt',
        'patlamış pirinç',
        'pirinç unu',
        'malt ekstraktı',
        'kalsiyum karbonat',
        'kakao tozu',
        'fındık',
        'süt tozu',
        'lesitin',
        'aroma vericiler',
        'tuz',
        'sodyum karbonat',
      ]),
    );
    expect(tokens, isNot(contains('palm')));
    expect(tokens, isNot(contains('7 yağı')));
    expect(tokens, isNot(contains('.7')));
  });

  test('preserves Turkish decimal percentages without numeric tokens', () {
    const input =
        'çilek parçaları (%4), çilek püresi (%1,5), elma püresi (%1.5)';

    final cleaned = IngredientCanonicalizer.cleanIngredientTextForAnalysis(
      input,
    );
    final tokens = IngredientCanonicalizer.parseIngredientsAdvanced(input);

    expect(cleaned.ingredientsText, contains('(%4)'));
    expect(cleaned.ingredientsText, contains('(%1,5)'));
    expect(cleaned.ingredientsText, contains('(%1.5)'));
    expect(
      tokens,
      containsAll(['çilek parçaı', 'çilek püresi', 'elma püresi']),
    );
    expect(tokens, isNot(contains('5')));
    expect(tokens.where((token) => RegExp(r'^\d+$').hasMatch(token)), isEmpty);
  });

  test('explicit functional children replace parent labels', () {
    const input =
        'emülgatör (yağ asitlerinin mono- ve digliseritleri), '
        'koruyucular (kalsiyum propiyonat, potasyum sorbat), '
        'jelleştirici (pektin), asitlik düzenleyici (sitrik asit), '
        'aroma vericiler';

    final tokens = IngredientCanonicalizer.parseIngredientsAdvanced(input);

    expect(
      tokens,
      containsAll([
        'mono ve digliseritler',
        'kalsiyum propiyonat',
        'potasyum sorbat',
        'pektin',
        'sitrik asit',
        'aroma vericiler',
      ]),
    );
    expect(tokens, isNot(contains('emülgatör')));
    expect(tokens, isNot(contains('koruyucu')));
    expect(tokens, isNot(contains('jelleştirici')));
    expect(tokens, isNot(contains('asitlik düzenleyici')));
  });

  test('removes implicit Turkish allergen tail before tokenization', () {
    const input =
        'un, çilek püresi (%1,5). YUMURTA, SÜT VE SERT KABUKLU '
        'MEYVELER İÇEREBİLİR. Aler';

    final cleaned = IngredientCanonicalizer.cleanIngredientTextForAnalysis(
      input,
    );
    final tokens = IngredientCanonicalizer.parseIngredientsAdvanced(input);

    expect(cleaned.ingredientsText, 'un, çilek püresi (%1,5)');
    expect(tokens, contains('çilek püresi'));
    expect(tokens.any((token) => token.contains('içerebilir')), isFalse);
  });

  test('sanitizes broken unknown fragments', () {
    final matchedPalm = IngredientMatch(
      originalToken: 'palm',
      normalizedText: 'palm',
      matchedIngredient: _ingredient(
        id: '1',
        name: 'Palm Yağı',
        normalizedName: 'palm yağı',
      ),
      matchedToken: 'palm yağı',
      confidenceScore: 1,
      matchType: MatchType.exactMatch,
      shouldAffectAnalysis: true,
    );

    final sanitized = UnknownIngredientSanitizer.sanitizeUnknownIngredients(
      rawUnknowns: const [
        'palm',
        'pirinç unu ()',
        '7 yağı',
        '.7',
        'mg/l',
        '()',
        'ayçiçek',
        'emülgatör yağı (sunflower mono- ve digliserit)',
      ],
      matches: [matchedPalm],
    );

    expect(sanitized, isNot(contains('palm')));
    expect(sanitized, isNot(contains('pirinç unu ()')));
    expect(sanitized, isNot(contains('7 yağı')));
    expect(sanitized, isNot(contains('.7')));
    expect(sanitized, isNot(contains('mg/l')));
    expect(sanitized, isNot(contains('()')));
  });

  test('parses OFF-style prefix and allergen note safely', () {
    const input =
        'İçindekiler: patates, bitkisel yağlar (ayçiçek yağı, palm), tuz. Alerjen: gluten içerebilir.';

    final tokens = IngredientCanonicalizer.parseIngredientsAdvanced(input);

    expect(tokens.any((t) => t.contains('patates')), isTrue);
    expect(
      tokens,
      containsAll(<String>['bitkisel yağlar', 'ayçiçek yağı', 'palm yağı']),
    );
    expect(tokens.any((t) => t.contains('tuz')), isTrue);
    expect(tokens.any((t) => t.contains('alerjen')), isFalse);
    expect(tokens.any((t) => t.contains('gluten içerebilir')), isFalse);
  });

  test('splits allergen warning section before ingredient matching', () {
    const input =
        'İçindekiler\n'
        'BEYAZ LEBLEBİ, TUZ A\n\n'
        'Alerjen Uyarısı\n'
        'eser miktarda badem, ceviz, pikan cevizi, antep fıstığı, '
        'fındık, kaju fıstığı, buğday gluteni içerir.\n'
        'Besin Değerleri\n'
        'Enerji 100 kcal';

    final cleaned = IngredientCanonicalizer.cleanIngredientTextForAnalysis(
      input,
    );
    final ingredientTokens = IngredientCanonicalizer.parseIngredientsAdvanced(
      input,
    );
    final allergenTokens = IngredientCanonicalizer.extractAllergenTokens(input);

    expect(cleaned.ingredientsText, 'BEYAZ LEBLEBİ, TUZ');
    expect(cleaned.allergenText, contains('eser miktarda badem'));
    expect(ingredientTokens, containsAll(<String>['beyaz leblebi', 'tuz']));
    expect(ingredientTokens.any((token) => token.contains('badem')), isFalse);
    expect(
      allergenTokens,
      containsAll(<String>[
        'badem',
        'ceviz',
        'pikan cevizi',
        'antep fıstığı',
        'fındık',
        'kaju fıstığı',
        'buğday gluteni',
      ]),
    );
  });

  test('parses english ingredients prefix and may contain note', () {
    const input = 'ingredients: potato, sunflower oil, salt; may contain milk';

    final tokens = IngredientCanonicalizer.parseIngredientsAdvanced(input);

    expect(tokens, contains('patates'));
    // canonical map normalizes sunflower oil to Turkish canonical form.
    expect(tokens, contains('ayçiçek yağı'));
    expect(tokens, contains('tuz'));
    expect(tokens.any((t) => t.contains('may contain')), isFalse);
  });

  test('normalizes Lay’s style oil phrases into displayable tokens', () {
    const input =
        'İçindekiler: patates, bitkisel yağlar (değişen miktarlarda mısır yağı, '
        'yüksek oleik asitli ayçiçek yağı, kanola yağı), tuz.';

    final tokens = IngredientCanonicalizer.parseIngredientsAdvanced(input);

    expect(
      tokens,
      containsAll(<String>[
        'patates',
        'bitkisel yağlar',
        'mısır yağı',
        'ayçiçek yağı',
        'kanola yağı',
        'tuz',
      ]),
    );
  });

  test('tokenizes colon and compact percentage expressions', () {
    const input = 'emülgatör: lesitin (soya), KAKAO(%5)';

    final tokens = IngredientCanonicalizer.parseIngredientsAdvanced(input);

    expect(
      tokens,
      containsAll(<String>['emülgatör', 'lesitin', 'soya', 'kakao']),
    );
  });
}
