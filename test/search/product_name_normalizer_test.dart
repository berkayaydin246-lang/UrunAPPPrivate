import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/imports/services/product_name_normalizer.dart';

void main() {
  group('ProductNameNormalizer.pickBestProductName', () {
    test('prefers product_name_tr over generic product_name', () {
      final name = ProductNameNormalizer.pickBestProductName({
        'product_name': 'Chocolate Wafer',
        'product_name_tr': 'Çikolatalı Gofret',
      });
      expect(name, 'Çikolatalı Gofret');
    });

    test('falls back to product_name_en when Turkish fields missing', () {
      final name = ProductNameNormalizer.pickBestProductName({
        'product_name_en': 'Tomato Ketchup',
      });
      expect(name, 'Tomato Ketchup');
    });

    test('returns Bilinmeyen Ürün when all fields empty', () {
      final name = ProductNameNormalizer.pickBestProductName({
        'product_name': '   ',
        'product_name_tr': '',
      });
      expect(name, 'Bilinmeyen Ürün');
    });

    test('keeps Turkish product_name_tr such as Popkek Bitter Çikolatalı', () {
      final name = ProductNameNormalizer.pickBestProductName({
        'product_name_tr': 'Popkek Bitter Çikolatalı',
        'product_name': 'Popcake Dark Chocolate',
      });
      expect(name, 'Popkek Bitter Çikolatalı');
    });
  });

  // ── cleanDisplayName ───────────────────────────────────────────────────────

  group('ProductNameNormalizer.cleanDisplayName', () {
    test('strips en-dash separated duplicate + size fragment', () {
      expect(
        ProductNameNormalizer.cleanDisplayName(
          'Eti Çikolatalı Gofret – eti cikolatali gofret –34g',
        ),
        'Eti Çikolatalı Gofret',
      );
    });

    test('strips brand embedded via en-dash + size', () {
      expect(
        ProductNameNormalizer.cleanDisplayName('Banada–Torku–700g'),
        'Banada',
      );
    });

    test('strips brand via en-dash + size with space', () {
      expect(
        ProductNameNormalizer.cleanDisplayName('Albeni–Ülker–40 g'),
        'Albeni',
      );
    });

    test(
      'removes duplicate brand fragment when brand is provided separately',
      () {
        expect(
          ProductNameNormalizer.cleanDisplayName('Eti - Salam', brand: 'Eti'),
          'Salam',
        );
      },
    );

    test('strips price fragment and title-cases', () {
      final result = ProductNameNormalizer.cleanDisplayName(
        'ülker çikolata –20₺',
      );
      expect(result, 'Ülker Çikolata');
    });

    test('strips standalone size without dash', () {
      expect(
        ProductNameNormalizer.cleanDisplayName('Coca-Cola 330ml'),
        'Coca-Cola',
      );
    });

    test('leaves clean name unchanged', () {
      expect(
        ProductNameNormalizer.cleanDisplayName('Ülker Çikolatalı Gofret'),
        'Ülker Çikolatalı Gofret',
      );
    });

    test('title-cases all-lowercase input', () {
      expect(
        ProductNameNormalizer.cleanDisplayName('ülker gofret'),
        'Ülker Gofret',
      );
    });

    test('handles empty string', () {
      expect(ProductNameNormalizer.cleanDisplayName(''), '');
    });

    test('strips only price — no price in result', () {
      final result = ProductNameNormalizer.cleanDisplayName('Test Ürün 25₺');
      expect(result.contains('₺'), isFalse);
      expect(result.contains('25'), isFalse);
    });

    test('no size in result', () {
      final result = ProductNameNormalizer.cleanDisplayName('Atıştırmalık 50g');
      expect(result.contains('50g'), isFalse);
      expect(result.contains('50 g'), isFalse);
    });
  });

  // ── toSearchable ───────────────────────────────────────────────────────────

  group('ProductNameNormalizer.toSearchable', () {
    test('çikolatalı → cikolatali', () {
      expect(ProductNameNormalizer.toSearchable('çikolatalı'), 'cikolatali');
    });

    test('Ülker → ulker (lowercase + ASCII)', () {
      expect(ProductNameNormalizer.toSearchable('ülker'), 'ulker');
    });

    test('şeker → seker', () {
      expect(ProductNameNormalizer.toSearchable('şeker'), 'seker');
    });

    test('ğ → g', () {
      expect(ProductNameNormalizer.toSearchable('soğuk'), 'soguk');
    });

    test('ö → o', () {
      expect(ProductNameNormalizer.toSearchable('köfte'), 'kofte');
    });

    test('ASCII-only string is unchanged', () {
      expect(ProductNameNormalizer.toSearchable('gofret'), 'gofret');
    });
  });

  // ── buildSearchKeywords ────────────────────────────────────────────────────

  group('ProductNameNormalizer.buildSearchKeywords', () {
    test('includes brand tokens', () {
      final kw = ProductNameNormalizer.buildSearchKeywords(
        displayName: 'Çikolatalı Gofret',
        brand: 'Eti',
      );
      expect(kw, containsAll(['eti']));
    });

    test('includes Turkish + ASCII name tokens', () {
      final kw = ProductNameNormalizer.buildSearchKeywords(
        displayName: 'Çikolatalı Gofret',
        brand: 'Eti',
      );
      expect(kw, containsAll(['çikolatalı', 'cikolatali']));
    });

    test('includes gofret + wafer synonym', () {
      final kw = ProductNameNormalizer.buildSearchKeywords(
        displayName: 'Çikolatalı Gofret',
        brand: 'Eti',
      );
      expect(kw, containsAll(['gofret', 'wafer']));
    });

    test('includes çikolata stem from çikolatalı synonym chain', () {
      final kw = ProductNameNormalizer.buildSearchKeywords(
        displayName: 'Çikolatalı Gofret',
        brand: 'Eti',
      );
      // çikolatalı → synonym → çikolata
      expect(kw, contains('çikolata'));
    });

    test('no price/size tokens', () {
      final kw = ProductNameNormalizer.buildSearchKeywords(
        displayName: 'Granola Bar',
        brand: null,
      );
      expect(kw.any((t) => RegExp(r'^\d').hasMatch(t)), isFalse);
    });

    test('no stop-word tokens (ve, ve, g, ml)', () {
      final kw = ProductNameNormalizer.buildSearchKeywords(
        displayName: 'Ürün ve Marka',
        brand: null,
      );
      expect(kw, isNot(contains('ve')));
      expect(kw, isNot(contains('g')));
    });

    test('result is sorted', () {
      final kw = ProductNameNormalizer.buildSearchKeywords(
        displayName: 'Bisküvi Kek',
        brand: 'Ülker',
      );
      final sorted = [...kw]..sort();
      expect(kw, sorted);
    });
  });

  // ── tokenizeQuery ──────────────────────────────────────────────────────────

  group('ProductNameNormalizer.tokenizeQuery', () {
    test('çikolatalı gofret → includes cikolatali + gofret + wafer', () {
      final tokens = ProductNameNormalizer.tokenizeQuery('çikolatalı gofret');
      expect(tokens, containsAll(['cikolatali', 'gofret', 'wafer']));
    });

    test('ülker gofret → includes ulker + gofret', () {
      final tokens = ProductNameNormalizer.tokenizeQuery('ülker gofret');
      expect(tokens, containsAll(['ulker', 'gofret']));
    });

    test('bisküvi → includes biskuvi + biscuit', () {
      final tokens = ProductNameNormalizer.tokenizeQuery('bisküvi');
      expect(tokens, containsAll(['biskuvi', 'biscuit']));
    });

    test('empty query → empty list', () {
      expect(ProductNameNormalizer.tokenizeQuery(''), isEmpty);
    });

    test('single-letter tokens are excluded', () {
      final tokens = ProductNameNormalizer.tokenizeQuery('a b c test');
      expect(tokens.any((t) => t.length < 2), isFalse);
    });

    test('stop words excluded', () {
      final tokens = ProductNameNormalizer.tokenizeQuery('çay ve kahve');
      expect(tokens, isNot(contains('ve')));
    });
  });

  // ── Cross-language matching ────────────────────────────────────────────────

  group('cross-language matching', () {
    test(
      'query tokens from "çikolatalı" match keywords built from "cikolatali"',
      () {
        final queryTokens = ProductNameNormalizer.tokenizeQuery(
          'çikolatalı gofret',
        );
        final productKeywords = ProductNameNormalizer.buildSearchKeywords(
          displayName: 'Cikolatali Gofret',
          brand: null,
        );
        final overlap = queryTokens.toSet().intersection(
          productKeywords.toSet(),
        );
        expect(overlap, isNotEmpty);
      },
    );

    test('query "ulker gofret" overlaps with Ülker product keywords', () {
      final queryTokens = ProductNameNormalizer.tokenizeQuery('ulker gofret');
      final productKeywords = ProductNameNormalizer.buildSearchKeywords(
        displayName: 'Çikolatalı Gofret',
        brand: 'Ülker',
      );
      final overlap = queryTokens.toSet().intersection(productKeywords.toSet());
      expect(overlap, isNotEmpty);
    });
  });
}
