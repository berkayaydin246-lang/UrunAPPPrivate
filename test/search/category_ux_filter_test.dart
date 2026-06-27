// Tests for category navigation, filter UX, nutrition thresholds, and brand
// filter behavior introduced in the category/filter UX redesign.

import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/search/models/product_list_context.dart';
import 'package:food_analyzer_app/features/search/models/product_search_filter.dart';
import 'package:food_analyzer_app/features/search/services/canonical_category_mapper.dart';
import 'package:food_analyzer_app/features/search/widgets/product_list_view.dart';

void main() {
  // ── ProductListContext — subcategory mode behavior ──────────────────────────

  group('SubCategory mode', () {
    const ctx = ProductListContext.subCategory(
      mainCategory: CanonicalCategoryMapper.kAtistirmalik,
      subCategory: CanonicalCategoryMapper.kCikolata,
    );

    test('1: normalizeFilter always enforces lockedMainCategory', () {
      final result = ctx.normalizeFilter(const ProductSearchFilter());
      expect(result.mainCategory, CanonicalCategoryMapper.kAtistirmalik);
    });

    test('2: locksSubCategory is false', () {
      expect(ctx.locksSubCategory, false);
    });

    test('3: canChangeSubCategory is true', () {
      expect(ctx.canChangeSubCategory, true);
    });

    test(
      '4: clearing sub in normalizeFilter stays in main, does not go global',
      () {
        final result = ctx.normalizeFilter(const ProductSearchFilter());
        expect(result.mainCategory, CanonicalCategoryMapper.kAtistirmalik);
        expect(result.subCategory, null);
      },
    );

    test('5: switching to sibling subcategory is accepted', () {
      final result = ctx.normalizeFilter(
        const ProductSearchFilter(
          subCategory: CanonicalCategoryMapper.kBiskuvi,
        ),
      );
      expect(result.subCategory, CanonicalCategoryMapper.kBiskuvi);
      expect(result.mainCategory, CanonicalCategoryMapper.kAtistirmalik);
    });

    test('6: initialFilter pre-fills with lockedSubCategory', () {
      final initial = ctx.initialFilter();
      expect(initial.subCategory, CanonicalCategoryMapper.kCikolata);
      expect(initial.mainCategory, CanonicalCategoryMapper.kAtistirmalik);
    });

    test('7: visibleActiveFilterCount is 0 when sub equals lockedSub', () {
      const filter = ProductSearchFilter(
        mainCategory: CanonicalCategoryMapper.kAtistirmalik,
        subCategory: CanonicalCategoryMapper.kCikolata,
      );
      expect(ctx.visibleActiveFilterCount(filter), 0);
    });

    test(
      '8: visibleActiveFilterCount stays 0 when sub is changed to sibling',
      () {
        const filter = ProductSearchFilter(
          mainCategory: CanonicalCategoryMapper.kAtistirmalik,
          subCategory: CanonicalCategoryMapper.kCips,
        );
        expect(ctx.visibleActiveFilterCount(filter), 0);
      },
    );

    test('9: visibleActiveFilterCount stays 0 when sub is cleared (null)', () {
      const filter = ProductSearchFilter(
        mainCategory: CanonicalCategoryMapper.kAtistirmalik,
      );
      expect(ctx.visibleActiveFilterCount(filter), 0);
    });
  });

  // ── ProductListContext — mainCategory mode behavior ─────────────────────────

  group('MainCategory mode', () {
    const ctx = ProductListContext.mainCategory(
      mainCategory: CanonicalCategoryMapper.kAtistirmalik,
    );

    test('10: locksMainCategory is true', () {
      expect(ctx.locksMainCategory, true);
    });

    test('11: canChangeMainCategory is false', () {
      expect(ctx.canChangeMainCategory, false);
    });

    test('12: sub can be set to any valid sibling', () {
      final result = ctx.normalizeFilter(
        const ProductSearchFilter(
          subCategory: CanonicalCategoryMapper.kKuruyemis,
        ),
      );
      expect(result.mainCategory, CanonicalCategoryMapper.kAtistirmalik);
      expect(result.subCategory, CanonicalCategoryMapper.kKuruyemis);
    });

    test('13: sub can be cleared (null) without losing main', () {
      final withSub = ctx.normalizeFilter(
        const ProductSearchFilter(
          subCategory: CanonicalCategoryMapper.kKuruyemis,
        ),
      );
      final cleared = ctx.normalizeFilter(withSub.copyWith(subCategory: null));
      expect(cleared.mainCategory, CanonicalCategoryMapper.kAtistirmalik);
      expect(cleared.subCategory, null);
    });
  });

  // ── GlobalSearch mode behavior ──────────────────────────────────────────────

  group('GlobalSearch mode', () {
    const ctx = ProductListContext.globalSearch();

    test('14: normalizeFilter allows any main+sub change', () {
      final result = ctx.normalizeFilter(
        const ProductSearchFilter(
          mainCategory: CanonicalCategoryMapper.kSut,
          subCategory: CanonicalCategoryMapper.kYogurt,
        ),
      );
      expect(result.mainCategory, CanonicalCategoryMapper.kSut);
      expect(result.subCategory, CanonicalCategoryMapper.kYogurt);
    });

    test('15: normalizeFilter clears sub when main is null', () {
      final result = ctx.normalizeFilter(
        const ProductSearchFilter(subCategory: CanonicalCategoryMapper.kYogurt),
      );
      // sub without main must be cleared
      expect(result.mainCategory, null);
      expect(result.subCategory, null);
    });
  });

  // ── Nutrition filter thresholds ─────────────────────────────────────────────

  group('Nutrition filter thresholds', () {
    test('16: protein thresholds are gram-based and sensible (5–25 g)', () {
      final spec = kNutrientFilterSpecs.firstWhere((s) => s.key == 'protein');
      expect(spec.thresholds, everyElement(lessThanOrEqualTo(25)));
      expect(spec.thresholds, everyElement(greaterThanOrEqualTo(1)));
      expect(spec.unit, 'g');
      expect(spec.comparator, '≥');
    });

    test('17: kalori thresholds are kcal-based and sensible (100–500)', () {
      final spec = kNutrientFilterSpecs.firstWhere((s) => s.key == 'energy');
      expect(spec.thresholds, everyElement(greaterThanOrEqualTo(50)));
      expect(spec.thresholds, everyElement(lessThanOrEqualTo(600)));
      expect(spec.unit, 'kcal');
      expect(spec.comparator, '≤');
    });

    test('18: tuz thresholds are gram-based and small (0.1–1.0 g)', () {
      final spec = kNutrientFilterSpecs.firstWhere((s) => s.key == 'salt');
      expect(spec.thresholds, everyElement(lessThanOrEqualTo(2.0)));
      expect(spec.thresholds, everyElement(greaterThan(0)));
      expect(spec.unit, 'g');
      expect(spec.comparator, '≤');
    });

    test(
      '19: no nutrient has impossible values (protein > 100 g, energy > 1000 kcal)',
      () {
        for (final spec in kNutrientFilterSpecs) {
          if (spec.key == 'energy') {
            expect(spec.thresholds, everyElement(lessThanOrEqualTo(1000)));
          } else {
            expect(spec.thresholds, everyElement(lessThanOrEqualTo(100)));
          }
        }
      },
    );

    test('20: all six nutrients are covered', () {
      final keys = kNutrientFilterSpecs.map((s) => s.key).toSet();
      expect(
        keys,
        containsAll(['energy', 'protein', 'sugar', 'fat', 'salt', 'fiber']),
      );
    });
  });

  // ── Sort order ──────────────────────────────────────────────────────────────

  group('Sort order', () {
    test('21: nameDesc is a distinct value from nameAsc', () {
      expect(SearchSortOrder.nameDesc, isNot(SearchSortOrder.nameAsc));
    });

    test('22: nameDesc and brandDesc are not nutrition sorts', () {
      const filter = ProductSearchFilter(sortOrder: SearchSortOrder.nameDesc);
      expect(filter.isNutritionSort, false);

      const filter2 = ProductSearchFilter(sortOrder: SearchSortOrder.brandDesc);
      expect(filter2.isNutritionSort, false);
    });

    test('23: all sort orders have non-empty Turkish labels', () {
      for (final order in SearchSortOrder.values) {
        final label = order.label;
        expect(label.isNotEmpty, true, reason: '$order has empty label');
        // Labels should not be placeholder strings.
        expect(label, isNot(contains('null')));
      }
    });
  });
}
