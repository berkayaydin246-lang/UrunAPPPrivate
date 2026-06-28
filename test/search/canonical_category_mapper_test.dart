import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/search/services/canonical_category_mapper.dart';

void main() {
  CanonicalCategory map({List<String>? tags, required String name}) =>
      CanonicalCategoryMapper.map(categoryTags: tags, name: name);

  // ── Tag-based mapping (primary signal) ───────────────────────────────────

  group('Tag-based mapping', () {
    test('sut_urunleri + "süt" in name → Süt / Süt', () {
      final c = map(tags: ['sut_urunleri'], name: 'Sütaş Tam Yağlı Süt');
      expect(c.main, CanonicalCategoryMapper.kSut);
      expect(c.sub, CanonicalCategoryMapper.kSutSub);
    });

    test('sut_urunleri + "yoğurt" in name → Süt / Yoğurt', () {
      final c = map(tags: ['sut_urunleri'], name: 'İçim Yoğurt');
      expect(c.main, CanonicalCategoryMapper.kSut);
      expect(c.sub, CanonicalCategoryMapper.kYogurt);
    });

    test('peynir_yogurt tag + "peynir" in name → Süt / Peynir', () {
      final c = map(tags: ['peynir_yogurt'], name: 'Lente Gouda Peynir');
      expect(c.main, CanonicalCategoryMapper.kSut);
      expect(c.sub, CanonicalCategoryMapper.kPeynir);
    });

    test('cips_kraker tag → Atıştırmalık / Cips', () {
      final c = map(tags: ['cips_kraker'], name: 'Doritos');
      expect(c.main, CanonicalCategoryMapper.kAtistirmalik);
      expect(c.sub, CanonicalCategoryMapper.kCips);
    });

    test('biskuvi_kek tag → Atıştırmalık / Bisküvi', () {
      final c = map(tags: ['biskuvi_kek'], name: 'Eti Burçak');
      expect(c.main, CanonicalCategoryMapper.kAtistirmalik);
      expect(c.sub, CanonicalCategoryMapper.kBiskuvi);
    });

    test('cikolata_gofret tag → Atıştırmalık / Çikolata', () {
      final c = map(tags: ['cikolata_gofret'], name: 'Milka Çikolata');
      expect(c.main, CanonicalCategoryMapper.kAtistirmalik);
      expect(c.sub, CanonicalCategoryMapper.kCikolata);
    });

    test('enerji_icecekleri tag → İçecekler / Gazlı İçecek', () {
      final c = map(tags: ['enerji_icecekleri'], name: 'Red Bull');
      expect(c.main, CanonicalCategoryMapper.kIcecekler);
      expect(c.sub, CanonicalCategoryMapper.kGazli);
    });

    test('icecekler tag + "kola" in name → İçecekler / Gazlı İçecek', () {
      final c = map(tags: ['icecekler'], name: 'Coca Cola');
      expect(c.main, CanonicalCategoryMapper.kIcecekler);
      expect(c.sub, CanonicalCategoryMapper.kGazli);
    });

    test('icecekler tag + "meyve suyu" in name → İçecekler / Meyve Suyu', () {
      final c = map(tags: ['icecekler'], name: 'Dimes Meyve Suyu');
      expect(c.main, CanonicalCategoryMapper.kIcecekler);
      expect(c.sub, CanonicalCategoryMapper.kMeyvesuyu);
    });

    test('soslar tag → Temel Gıda / Soslar', () {
      final c = map(tags: ['soslar'], name: 'Heinz Ketçap');
      expect(c.main, CanonicalCategoryMapper.kTemelGida);
      expect(c.sub, CanonicalCategoryMapper.kSoslar);
    });

    test('hazir_yemek tag → Hazır & Donuk / Pratik Yemek', () {
      final c = map(tags: ['hazir_yemek'], name: 'Hazır Çorba');
      expect(c.main, CanonicalCategoryMapper.kHazirDonuk);
      // hazir_yemek now maps to kPratikYemek (the broad "ready meal" umbrella).
      expect(c.sub, CanonicalCategoryMapper.kPratikYemek);
    });

    test('ton_konserve tag → Et / Balık / Deniz Ürünleri', () {
      final c = map(tags: ['ton_konserve'], name: 'Tamek Ton Balığı');
      expect(c.main, CanonicalCategoryMapper.kEt);
      expect(c.sub, CanonicalCategoryMapper.kBalik);
    });

    test('et_sarkuteri tag + "tavuk" in name → Et / Tavuk', () {
      final c = map(tags: ['et_sarkuteri'], name: 'Tavuk Göğsü');
      expect(c.main, CanonicalCategoryMapper.kEt);
      expect(c.sub, CanonicalCategoryMapper.kTavuk);
    });

    test('et_sarkuteri tag + "dana" in name → Et / Kırmızı Et', () {
      final c = map(tags: ['et_sarkuteri'], name: 'Dana Sucuk');
      expect(c.main, CanonicalCategoryMapper.kEt);
      expect(c.sub, CanonicalCategoryMapper.kKirmiziEt);
    });

    test('et_sarkuteri tag, no sub-keyword → Et / Şarküteri', () {
      final c = map(tags: ['et_sarkuteri'], name: 'Salam');
      expect(c.main, CanonicalCategoryMapper.kEt);
      expect(c.sub, CanonicalCategoryMapper.kSarkuteri);
    });

    test('makarna_bakliyat tag + "makarna" in name → Temel Gıda / Makarna', () {
      final c = map(tags: ['makarna_bakliyat'], name: 'Barilla Makarna');
      expect(c.main, CanonicalCategoryMapper.kTemelGida);
      expect(c.sub, CanonicalCategoryMapper.kMakarna);
    });

    test('kahvaltilik tag + "bal" in name → Kahvaltılıklar / Bal', () {
      final c = map(tags: ['kahvaltilik'], name: 'Balparmak Çiçek Balı');
      expect(c.main, CanonicalCategoryMapper.kKahvaltilik);
      expect(c.sub, CanonicalCategoryMapper.kBalRecel);
    });

    test('kahvaltilik tag + "tahin" in name → Kahvaltılıklar / Tahin', () {
      final c = map(tags: ['kahvaltilik'], name: 'Torku Tahin Helvası');
      expect(c.main, CanonicalCategoryMapper.kKahvaltilik);
      expect(c.sub, CanonicalCategoryMapper.kTahinHelva);
    });

    test('findik_ezmesi tag → Kahvaltılıklar / Krem Çikolata', () {
      final c = map(tags: ['findik_ezmesi'], name: 'Ülker Çokokrem');
      expect(c.main, CanonicalCategoryMapper.kKahvaltilik);
      expect(c.sub, CanonicalCategoryMapper.kKremCikolata);
    });

    test('saglikli_protein tag → Atıştırmalık / Kuruyemiş', () {
      final c = map(tags: ['saglikli_protein'], name: 'Tadım Badem');
      expect(c.main, CanonicalCategoryMapper.kAtistirmalik);
      expect(c.sub, CanonicalCategoryMapper.kKuruyemis);
    });

    test('bebek_cocuk tag → Bebek Gıda / Bebek Beslenme', () {
      final c = map(tags: ['bebek_cocuk'], name: 'Bebek Maması');
      expect(c.main, CanonicalCategoryMapper.kBebek);
      // Legacy bebek_cocuk tag now maps to the kBebekBeslenme sub.
      expect(c.sub, CanonicalCategoryMapper.kBebekBeslenme);
    });

    test('dondurma_tatli tag → Dondurma', () {
      final c = map(tags: ['dondurma_tatli'], name: 'Magnum Dondurma');
      expect(c.main, CanonicalCategoryMapper.kDondurma);
      expect(c.sub, isNull);
    });
  });

  // ── Keyword-only fallback (no tags) ───────────────────────────────────────

  group('Keyword fallback (no tags)', () {
    test('"süt" in name without tags → Süt / Süt', () {
      final c = map(tags: [], name: 'Sütaş Süt');
      expect(c.main, CanonicalCategoryMapper.kSut);
      expect(c.sub, CanonicalCategoryMapper.kSutSub);
    });

    test('"yoğurt" in name without tags → Süt / Yoğurt', () {
      final c = map(tags: [], name: 'Sek Yoğurt');
      expect(c.main, CanonicalCategoryMapper.kSut);
      expect(c.sub, CanonicalCategoryMapper.kYogurt);
    });

    test('"peynir" in name without tags → Süt / Peynir', () {
      final c = map(tags: [], name: 'Beyaz Peynir');
      expect(c.main, CanonicalCategoryMapper.kSut);
      expect(c.sub, CanonicalCategoryMapper.kPeynir);
    });

    test('"cips" in name without tags → Atıştırmalık / Cips', () {
      final c = map(tags: [], name: 'Lay\'s Cips');
      expect(c.main, CanonicalCategoryMapper.kAtistirmalik);
      expect(c.sub, CanonicalCategoryMapper.kCips);
    });

    test('"bisküvi" in name without tags → Atıştırmalık / Bisküvi', () {
      final c = map(tags: [], name: 'Cicibebe Bisküvi');
      expect(c.main, CanonicalCategoryMapper.kAtistirmalik);
      expect(c.sub, CanonicalCategoryMapper.kBiskuvi);
    });

    test('"çikolata" in name without tags → Atıştırmalık / Çikolata', () {
      final c = map(tags: [], name: 'Ülker Çikolata');
      expect(c.main, CanonicalCategoryMapper.kAtistirmalik);
      expect(c.sub, CanonicalCategoryMapper.kCikolata);
    });

    test('"kola" in name without tags → İçecekler', () {
      final c = map(tags: [], name: 'Pepsi Kola');
      expect(c.main, CanonicalCategoryMapper.kIcecekler);
    });

    test('"ketçap" in name without tags → Temel Gıda / Soslar', () {
      final c = map(tags: [], name: 'Tadım Ketçap');
      expect(c.main, CanonicalCategoryMapper.kTemelGida);
      expect(c.sub, CanonicalCategoryMapper.kSoslar);
    });

    test('"konserve" in name without tags → Temel Gıda / Konserve', () {
      final c = map(tags: [], name: 'Tamek Konserve Mısır');
      expect(c.main, CanonicalCategoryMapper.kTemelGida);
      expect(c.sub, CanonicalCategoryMapper.kKonserve);
    });

    test('unrecognized product → Diğer', () {
      final c = map(tags: [], name: 'XYZ Bilinmeyen Ürün 9000');
      expect(c.main, CanonicalCategoryMapper.kDiger);
    });

    test('null tags treated same as empty list', () {
      final c = map(tags: null, name: 'Bilinmeyen');
      expect(c.main, CanonicalCategoryMapper.kDiger);
    });
  });

  // ── toString helper ───────────────────────────────────────────────────────

  group('CanonicalCategory.toString', () {
    test('with sub returns "main / sub"', () {
      const c = CanonicalCategory(main: 'A', sub: 'B');
      expect(c.toString(), 'A / B');
    });

    test('without sub returns main only', () {
      const c = CanonicalCategory(main: 'A');
      expect(c.toString(), 'A');
    });
  });

  // ── subCategoriesFor ──────────────────────────────────────────────────────

  group('subCategoriesFor', () {
    test('returns non-empty list for known main category', () {
      final subs = CanonicalCategoryMapper.subCategoriesFor(
        CanonicalCategoryMapper.kAtistirmalik,
      );
      expect(subs, contains(CanonicalCategoryMapper.kCips));
      expect(subs, contains(CanonicalCategoryMapper.kBiskuvi));
    });

    test('returns empty list for Diğer', () {
      final subs = CanonicalCategoryMapper.subCategoriesFor(
        CanonicalCategoryMapper.kDiger,
      );
      expect(subs, isEmpty);
    });

    test('returns empty list for unknown category', () {
      final subs = CanonicalCategoryMapper.subCategoriesFor('Tanımsız');
      expect(subs, isEmpty);
    });
  });
}
