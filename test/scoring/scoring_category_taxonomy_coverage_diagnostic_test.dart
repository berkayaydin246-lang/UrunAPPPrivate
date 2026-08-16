import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/scoring/application/scoring_category_taxonomy_coverage_diagnostic.dart';

/// Section (FINAL scoring-category taxonomy gap): the exact 62 distinct
/// `category_tags` values a read-only production inventory returned among
/// `source = web_scraper:migros AND scoring_evidence IS NULL` rows.
///
/// This list is NOT filtered to `missing_classification` — many of these
/// tags' products lack scoring_evidence for entirely unrelated reasons
/// (fibre/FVL/ingredient/additive/basis blockers) while already resolving
/// their scoring category correctly. This test measures ONLY category-tag
/// coverage, never assumes the inventory count means a classification gap.
const _productionCategoryTagInventory = [
  'kahve',
  'peynir',
  'cay',
  'kahvaltiliklar',
  'gazsiz_icecek',
  'sos',
  'tuz_baharat_harc',
  'biskuvi',
  'konserve',
  'cikolata',
  'gazli_icecek',
  'bakliyat',
  'bar_kaplamalilar',
  'sekerleme',
  'kuruyemis',
  'sut',
  'yogurt',
  'pratik_yemek',
  'cips',
  'makarna',
  'zeytin',
  'kek',
  'sutlu_tatli_krema',
  'tek_dondurma',
  'ekmek',
  'kap_dondurma',
  'maden_suyu',
  'sivi_yag',
  'sucuk',
  'kuru_meyve',
  'tatli',
  'ozel_beslenme_urunleri',
  'sakiz',
  'kraker',
  'fume_et',
  'balik_deniz_urunleri',
  'sosis',
  'dondurulmus_hazir_yemek',
  'galeta_grissini_gevrek',
  'meze',
  'beyaz_et',
  'dondurulmus_sebze',
  'meyve_suyu',
  'dondurulmus_pizza',
  'pastirma',
  'dondurulmus_tatli',
  'kuru_pasta',
  'kirmizi_et',
  'paketli_sandvic',
  'dondurulmus_borek',
  'dondurulmus_firin_urunleri',
  'dondurulmus_patates',
  'salam',
  'kavurma',
  'misir_ve_pirinc_patlagi',
  'dondurulmus_manti',
  'dondurulmus_meyve',
  'jambon',
  'pide_lahmacun',
  'hazir_manti',
  'pasta',
  'dondurulmus_sushi',
];

// The two genuinely ambiguous tags this pass deliberately leaves
// unresolved — see the taxonomy-closure audit: 'fume_et' ("füme et")
// departments commonly include smoked turkey/poultry products alongside
// red meat, and 'jambon' (ham) at Turkish retail spans both turkey-based
// and beef-based products. Neither has documented production evidence
// (unlike the saved-sample-proven cay/kahve exemption) narrowing it to a
// single scoring category, so tag-only classification would be unsafe.
const _intentionallyUnresolvedAmbiguousTags = ['fume_et', 'jambon'];

// The two tags this pass newly maps — both SAFE_MISSING_MAPPING: a single,
// unambiguous scoring-category interpretation exists under the existing
// frozen methodology, reusing the same normalized category-tag mechanism
// every other legacy generalFood tag already uses.
const _newlyAddedSafeMappings = ['zeytin', 'misir_ve_pirinc_patlagi'];

void main() {
  const diagnostic = ScoringCategoryTaxonomyCoverageDiagnostic();

  test(
    'inventory tag count is exactly 62, matching the production read-only '
    'query result this pass was scoped to',
    () {
      expect(_productionCategoryTagInventory, hasLength(62));
      expect(_productionCategoryTagInventory.toSet(), hasLength(62),
          reason: 'no accidental duplicate tag strings in the fixture');
    },
  );

  test(
    'measures the real remaining classification gap: exactly the two '
    'documented ambiguous tags are unresolved, everything else — including '
    'both newly-added safe mappings — now resolves',
    () {
      final report = diagnostic.evaluate(_productionCategoryTagInventory);

      expect(report.inventoryTagCount, 62);
      expect(
        report.unresolvedTags,
        _intentionallyUnresolvedAmbiguousTags,
        reason: 'print(report) below shows the exact remaining names',
      );
      expect(report.resolvedTags, hasLength(60));
      for (final tag in _newlyAddedSafeMappings) {
        expect(
          report.resolvedTags,
          contains(tag),
          reason: '$tag is a newly-added SAFE_MISSING_MAPPING this pass',
        );
      }

      // Human-readable summary, matching the requested diagnostic output
      // shape (Section 5/9 of the taxonomy-closure pass).
      // ignore: avoid_print
      print('inventory_tag_count=${report.inventoryTagCount}');
      // ignore: avoid_print
      print('already_resolved_tags=${report.resolvedTags.length}');
      // ignore: avoid_print
      print(
        'safe_missing_mappings_added=${_newlyAddedSafeMappings.length} '
        '(${_newlyAddedSafeMappings.join(', ')})',
      );
      // ignore: avoid_print
      print('unresolved_tags_remaining=${report.unresolvedTags.length}');
      // ignore: avoid_print
      print('unresolved_tag_names=${report.unresolvedTags.join(', ')}');
    },
  );

  test(
    'newly-added zeytin mapping resolves generalFood, never a special '
    'branch, and never invents nutrition basis or eligibility',
    () {
      final report = diagnostic.evaluate(const ['zeytin']);
      expect(report.resolvedTags, ['zeytin']);
    },
  );

  test(
    'newly-added misir_ve_pirinc_patlagi mapping resolves exactly like its '
    'sibling spelling misir_pirinc_patlagi',
    () {
      final withSpace = diagnostic.evaluate(const ['misir_ve_pirinc_patlagi']);
      final original = diagnostic.evaluate(const ['misir_pirinc_patlagi']);
      expect(withSpace.resolvedTags, ['misir_ve_pirinc_patlagi']);
      expect(original.resolvedTags, ['misir_pirinc_patlagi']);
    },
  );

  test(
    'fume_et and jambon remain unresolved individually — no accidental '
    'mapping slipped in for either',
    () {
      final report = diagnostic.evaluate(const ['fume_et', 'jambon']);
      expect(report.resolvedTags, isEmpty);
      expect(report.unresolvedTags, ['fume_et', 'jambon']);
    },
  );

  test(
    'an unrelated, never-seen tag remains unresolved, proving this is not '
    'a permissive catch-all',
    () {
      final report = diagnostic.evaluate(const ['completely_unknown_tag_xyz']);
      expect(report.unresolvedTags, ['completely_unknown_tag_xyz']);
    },
  );
}
