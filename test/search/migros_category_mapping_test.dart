/// Tests for expanded CanonicalCategoryMapper handling new Migros scraper tags
/// and canonical_category / canonical_subcategory DB fields.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/product/repositories/product_repository.dart';
import 'package:food_analyzer_app/features/search/controllers/filtered_search_controller.dart';
import 'package:food_analyzer_app/features/search/models/product_search_filter.dart';
import 'package:food_analyzer_app/features/search/services/canonical_category_mapper.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

Product _p({
  required String name,
  List<String>? categoryTags,
  String? canonicalCategory,
  String? canonicalSubcategory,
}) {
  final now = DateTime.now();
  return Product(
    id: name,
    name: name,
    verificationStatus: 'verified',
    createdAt: now,
    updatedAt: now,
    categoryTags: categoryTags,
    canonicalCategory: canonicalCategory,
    canonicalSubcategory: canonicalSubcategory,
  );
}

CanonicalCategory _map({
  List<String>? tags,
  String name = '',
  String? canonicalCategory,
  String? canonicalSubcategory,
}) => CanonicalCategoryMapper.map(
  categoryTags: tags,
  name: name,
  canonicalCategory: canonicalCategory,
  canonicalSubcategory: canonicalSubcategory,
);

class _FakeRepo extends ProductRepository {
  final List<Product> _products;
  _FakeRepo(this._products);

  @override
  Future<({List<Product> results, bool hasMore})> filteredSearch(
    ProductSearchFilter filter, {
    int pageSize = 20,
    int serverOffset = 0,
  }) async {
    var results = _products.toList();
    // Mirror real server: apply the central query plan before pagination so
    // exact-tag subcategories are filtered correctly without client-side pass.
    final plan = filter.queryPlan;
    if (plan.hasFilter && plan.categoryTagsAny.isNotEmpty) {
      results = results.where((p) {
        return (p.categoryTags ?? []).any(plan.categoryTagsAny.contains);
      }).toList();
    }
    return (results: results.take(pageSize).toList(), hasMore: false);
  }
}

Future<FilteredSearchState> _run(
  List<Product> products,
  ProductSearchFilter filter,
) async {
  final container = ProviderContainer(
    overrides: [
      filteredSearchProvider.overrideWith(
        (ref) =>
            FilteredSearchNotifier(_FakeRepo(products), initialFilter: filter),
      ),
    ],
  );
  addTearDown(container.dispose);
  for (var i = 0; i < 50; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    if (!container.read(filteredSearchProvider).isLoading) break;
  }
  return container.read(filteredSearchProvider);
}

// ─────────────────────────────────────────────────────────────────────────────

void main() {
  // ── 1–11: CanonicalCategoryMapper.map() with new Migros tags ────────────────

  group('CanonicalCategoryMapper — new Migros tags', () {
    test('1. tag=sut → kSut / kSutSub', () {
      final c = _map(tags: ['sut']);
      expect(c.main, CanonicalCategoryMapper.kSut);
      expect(c.sub, CanonicalCategoryMapper.kSutSub);
    });

    test('2. tag=yogurt → kSut / kYogurt', () {
      final c = _map(tags: ['yogurt']);
      expect(c.main, CanonicalCategoryMapper.kSut);
      expect(c.sub, CanonicalCategoryMapper.kYogurt);
    });

    test('3. tag=peynir → kSut / kPeynir', () {
      final c = _map(tags: ['peynir']);
      expect(c.main, CanonicalCategoryMapper.kSut);
      expect(c.sub, CanonicalCategoryMapper.kPeynir);
    });

    test('4. tag=sutlu_tatli_krema → kSut / kSutluTatli', () {
      final c = _map(tags: ['sutlu_tatli_krema']);
      expect(c.main, CanonicalCategoryMapper.kSut);
      expect(c.sub, CanonicalCategoryMapper.kSutluTatli);
    });

    test('5. tag=cips → kAtistirmalik / kCips', () {
      final c = _map(tags: ['cips']);
      expect(c.main, CanonicalCategoryMapper.kAtistirmalik);
      expect(c.sub, CanonicalCategoryMapper.kCips);
    });

    test('6. tag=biskuvi → kAtistirmalik / kBiskuvi', () {
      final c = _map(tags: ['biskuvi']);
      expect(c.main, CanonicalCategoryMapper.kAtistirmalik);
      expect(c.sub, CanonicalCategoryMapper.kBiskuvi);
    });

    test('7. tag=kuruyemis → kAtistirmalik / kKuruyemis', () {
      final c = _map(tags: ['kuruyemis']);
      expect(c.main, CanonicalCategoryMapper.kAtistirmalik);
      expect(c.sub, CanonicalCategoryMapper.kKuruyemis);
    });

    test('8. tag=gazli_icecek → kIcecekler / kGazli', () {
      final c = _map(tags: ['gazli_icecek']);
      expect(c.main, CanonicalCategoryMapper.kIcecekler);
      expect(c.sub, CanonicalCategoryMapper.kGazli);
    });

    test('9. tag=gazsiz_icecek → kIcecekler / kGazsiz', () {
      final c = _map(tags: ['gazsiz_icecek']);
      expect(c.main, CanonicalCategoryMapper.kIcecekler);
      expect(c.sub, CanonicalCategoryMapper.kGazsiz);
    });

    test('10. tag=sos → kSosKonserve / kSoslar', () {
      final c = _map(tags: ['sos']);
      expect(c.main, CanonicalCategoryMapper.kSosKonserve);
      expect(c.sub, CanonicalCategoryMapper.kSoslar);
    });

    test('11. tag=konserve → kSosKonserve / kKonserve', () {
      final c = _map(tags: ['konserve']);
      expect(c.main, CanonicalCategoryMapper.kSosKonserve);
      expect(c.sub, CanonicalCategoryMapper.kKonserve);
    });
  });

  group('CanonicalCategoryMapper — deli meat tags', () {
    for (final tag in [
      'sucuk',
      'sosis',
      'salam',
      'jambon',
      'pastirma',
      'fume_et',
      'kavurma',
    ]) {
      test('tag=$tag → kEt / kSarkuteri', () {
        final c = _map(tags: [tag]);
        expect(c.main, CanonicalCategoryMapper.kEt);
        expect(c.sub, CanonicalCategoryMapper.kSarkuteri);
      });
    }

    test('tag=beyaz_et → kEt / kTavuk', () {
      final c = _map(tags: ['beyaz_et']);
      expect(c.main, CanonicalCategoryMapper.kEt);
      expect(c.sub, CanonicalCategoryMapper.kTavuk);
    });

    test('tag=kirmizi_et → kEt / kKirmiziEt', () {
      final c = _map(tags: ['kirmizi_et']);
      expect(c.main, CanonicalCategoryMapper.kEt);
      expect(c.sub, CanonicalCategoryMapper.kKirmiziEt);
    });

    test('tag=balik_deniz_urunleri → kEt / kBalik', () {
      final c = _map(tags: ['balik_deniz_urunleri']);
      expect(c.main, CanonicalCategoryMapper.kEt);
      expect(c.sub, CanonicalCategoryMapper.kBalik);
    });
  });

  // ── 12: canonical DB fields take priority over tags ─────────────────────────

  group('CanonicalCategoryMapper — canonical DB field priority', () {
    test('12. canonicalCategory overrides tag when both present', () {
      // tag says "cips" (Atıştırmalık) but DB field says Kahvaltılıklar
      final c = _map(
        tags: ['cips'],
        canonicalCategory: CanonicalCategoryMapper.kKahvaltilik,
        canonicalSubcategory: CanonicalCategoryMapper.kBalRecel,
      );
      expect(c.main, CanonicalCategoryMapper.kKahvaltilik);
      expect(c.sub, CanonicalCategoryMapper.kBalRecel);
    });

    test('13. empty canonicalCategory falls through to tag-based mapping', () {
      final c = _map(tags: ['biskuvi'], canonicalCategory: '');
      expect(c.main, CanonicalCategoryMapper.kAtistirmalik);
      expect(c.sub, CanonicalCategoryMapper.kBiskuvi);
    });

    test('14. null canonicalCategory falls through to tag-based mapping', () {
      final c = _map(tags: ['yogurt'], canonicalCategory: null);
      expect(c.main, CanonicalCategoryMapper.kSut);
      expect(c.sub, CanonicalCategoryMapper.kYogurt);
    });
  });

  // ── 15–16: mainCategoryToTags includes new tags ──────────────────────────────

  group('mainCategoryToTags — includes new Migros tags', () {
    test('15. kSut tags include sut, yogurt, peynir', () {
      final tags = CanonicalCategoryMapper.mainCategoryToTags(
        CanonicalCategoryMapper.kSut,
      );
      expect(tags, containsAll(['sut', 'yogurt', 'peynir']));
    });

    test('16. kAtistirmalik tags include cips, biskuvi, kuruyemis', () {
      final tags = CanonicalCategoryMapper.mainCategoryToTags(
        CanonicalCategoryMapper.kAtistirmalik,
      );
      expect(tags, containsAll(['cips', 'biskuvi', 'kuruyemis']));
    });

    test(
      '17. kEt tags include sucuk, beyaz_et, kirmizi_et, balik_deniz_urunleri',
      () {
        final tags = CanonicalCategoryMapper.mainCategoryToTags(
          CanonicalCategoryMapper.kEt,
        );
        expect(
          tags,
          containsAll([
            'sucuk',
            'beyaz_et',
            'kirmizi_et',
            'balik_deniz_urunleri',
          ]),
        );
      },
    );

    test('18. kIcecekler tags include gazli_icecek, gazsiz_icecek', () {
      final tags = CanonicalCategoryMapper.mainCategoryToTags(
        CanonicalCategoryMapper.kIcecekler,
      );
      expect(tags, containsAll(['gazli_icecek', 'gazsiz_icecek']));
    });

    test('19. kSosKonserve tags include sos, konserve', () {
      final tags = CanonicalCategoryMapper.mainCategoryToTags(
        CanonicalCategoryMapper.kSosKonserve,
      );
      expect(tags, containsAll(['sos', 'konserve']));
    });
  });

  // ── 20: sub-category filter uses canonicalSubcategory when populated ─────────

  group('Sub-category filter — canonicalSubcategory fast path', () {
    test(
      '20. products with canonicalSubcategory=Süt included; Yoğurt excluded',
      () async {
        final sut = _p(
          name: 'Sütaş Tam Yağlı Süt',
          categoryTags: ['sut'],
          canonicalCategory: CanonicalCategoryMapper.kSut,
          canonicalSubcategory: CanonicalCategoryMapper.kSutSub,
        );
        final yogurt = _p(
          name: 'Danone Yoğurt',
          categoryTags: ['yogurt'],
          canonicalCategory: CanonicalCategoryMapper.kSut,
          canonicalSubcategory: CanonicalCategoryMapper.kYogurt,
        );

        final state = await _run(
          [sut, yogurt],
          const ProductSearchFilter(
            mainCategory: CanonicalCategoryMapper.kSut,
            subCategory: CanonicalCategoryMapper.kSutSub,
          ),
        );

        final names = state.products.map((p) => p.name).toList();
        expect(names, contains('Sütaş Tam Yağlı Süt'));
        expect(names, isNot(contains('Danone Yoğurt')));
      },
    );
  });
}
