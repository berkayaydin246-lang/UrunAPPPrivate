import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/product/data/ingredient_explanation_catalog.dart';
import 'package:food_analyzer_app/features/product/models/ingredient.dart';
import 'package:food_analyzer_app/features/product/widgets/product_detail_shared.dart';

void main() {
  final now = DateTime(2026, 1, 1);

  Ingredient ing(String id, String name, String riskLevel) => Ingredient(
    id: id,
    name: name,
    normalizedName: name.toLowerCase(),
    riskLevel: riskLevel,
    createdAt: now,
    updatedAt: now,
  );

  // ── BHT / E321 ─────────────────────────────────────────────────────────────

  group('BHT / E321', () {
    test('canonical "BHT" resolves to bht spec with medium risk', () {
      final spec = productRiskSpecForKey('BHT');
      expect(spec, isNotNull);
      expect(spec!.groupId, 'bht');
      expect(spec.riskLevel, 'medium');
    });

    test('E-code alias "E321" resolves to same group as "BHT"', () {
      final specBht = productRiskSpecForKey('BHT');
      final specE321 = productRiskSpecForKey('E321');
      expect(specE321, isNotNull);
      expect(specE321!.groupId, specBht!.groupId);
      expect(specE321.riskLevel, specBht.riskLevel);
    });

    test('hyphenated alias "E-321" resolves to bht', () {
      expect(productRiskSpecForKey('E-321')?.groupId, 'bht');
    });

    test('spaced alias "E 321" resolves to bht', () {
      expect(productRiskSpecForKey('E 321')?.groupId, 'bht');
    });

    test('Turkish name resolves to bht', () {
      expect(productRiskSpecForKey('Butil hidroksi toluen')?.groupId, 'bht');
    });

    test('English name resolves to bht', () {
      expect(productRiskSpecForKey('Butylated Hydroxytoluene')?.groupId, 'bht');
    });

    test('BHT catalog entry enriches ingredient with E321 and references', () {
      final resolved = enrichIngredientKnowledge(ing('1', 'BHT', 'unknown'));
      expect(resolved.eCode, 'E321');
      // For 'unknown' DB riskLevel, catalog's 'medium' kicks in
      expect(resolved.riskLevel, 'medium');
      expect(resolved.ingredientType, 'Yapay antioksidan');
      expect(resolved.shortPurpose, isNotEmpty);
      expect(resolved.shortRiskSummary, isNotEmpty);
      expect(
        resolved.sourceReferenceEntries?.any((r) => r.documentCode == 'E321'),
        isTrue,
      );
    });

    test('BHT catalog wins over bad DB content', () {
      final badDbIngredient = Ingredient(
        id: '1b',
        name: 'BHT',
        normalizedName: 'bht',
        riskLevel: 'high',
        shortPurpose: 'Yağ stabilizesi, rancidizasyonu engel.',
        shortRiskSummary: 'Hayvan araştırmasında organ etkileri.',
        createdAt: now,
        updatedAt: now,
      );
      final resolved = enrichIngredientKnowledge(badDbIngredient);
      expect(
        resolved.shortPurpose,
        isNot(contains('rancidizasyonu')),
        reason: 'Catalog shortPurpose must replace bad DB text',
      );
      expect(
        resolved.shortRiskSummary,
        isNot(contains('organ etkileri')),
        reason: 'Catalog shortRiskSummary must replace bad DB text',
      );
    });

    test('BHT and E321 produce same groupId — no duplicate rows', () {
      final spec1 = productRiskSpecForKey('BHT');
      final spec2 = productRiskSpecForKey('E321');
      expect(
        spec1!.groupId,
        spec2!.groupId,
        reason: 'BHT and E321 must deduplicate to the same group',
      );
    });

    test(
      'canonicalRiskLevelForIngredient uses spec severity, not DB severity',
      () {
        final dbHighBht = ing('1c', 'BHT', 'high');
        final canonical = canonicalRiskLevelForIngredient(dbHighBht);
        expect(
          canonical,
          'medium',
          reason: 'Spec defines medium; DB high must be overridden',
        );
      },
    );
  });

  // ── Brilliant Blue / E133 ───────────────────────────────────────────────────

  group('Brilliant Blue / E133', () {
    test(
      'canonical "Brilliant Blue" resolves to brilliant_blue with high risk',
      () {
        final spec = productRiskSpecForKey('Brilliant Blue');
        expect(spec, isNotNull);
        expect(spec!.groupId, 'brilliant_blue');
        expect(spec.riskLevel, 'high');
      },
    );

    test('E133 alias resolves to brilliant_blue', () {
      expect(productRiskSpecForKey('E133')?.groupId, 'brilliant_blue');
    });

    test('Brilliant Blue catalog entry has non-placeholder content', () {
      final resolved = enrichIngredientKnowledge(
        ing('2', 'Brilliant Blue', 'medium'),
      );
      expect(
        ingredientHasExplanationMetadata(resolved),
        isTrue,
        reason: 'Must not show placeholder text',
      );
      expect(resolved.shortPurpose, isNotEmpty);
      expect(resolved.shortRiskSummary, isNotEmpty);
      expect(
        resolved.shortRiskSummary,
        isNot(contains('Bu içerik için detaylı açıklama henüz eklenmedi.')),
      );
    });

    test(
      'Brilliant Blue catalog with unknown DB riskLevel gets catalog high',
      () {
        final unknownBb = ing('2b', 'Brilliant Blue', 'unknown');
        final resolved = enrichIngredientKnowledge(unknownBb);
        expect(
          resolved.riskLevel,
          'high',
          reason: 'Catalog riskLevel applied when DB has unknown',
        );
      },
    );

    test(
      'canonicalRiskLevelForIngredient for DB-medium Brilliant Blue returns high',
      () {
        final dbMediumBb = ing('2c', 'Brilliant Blue', 'medium');
        final canonical = canonicalRiskLevelForIngredient(dbMediumBb);
        expect(
          canonical,
          'high',
          reason: 'Spec defines high; DB medium must be overridden',
        );
      },
    );

    test('Brilliant Blue catalog has EFSA source', () {
      final resolved = enrichIngredientKnowledge(
        ing('2d', 'Brilliant Blue', 'medium'),
      );
      expect(
        resolved.sourceReferenceEntries?.any((r) => r.authority == 'EFSA'),
        isTrue,
      );
    });
  });

  // ── BHA / E320 ─────────────────────────────────────────────────────────────

  group('BHA / E320', () {
    test('canonical "BHA" resolves to bha spec with medium risk', () {
      final spec = productRiskSpecForKey('BHA');
      expect(spec, isNotNull);
      expect(spec!.groupId, 'bha');
      expect(spec.riskLevel, 'medium');
    });

    test('E-code alias "E320" resolves to same group as "BHA"', () {
      expect(
        productRiskSpecForKey('E320')?.groupId,
        productRiskSpecForKey('BHA')?.groupId,
      );
    });

    test('BHA catalog enriches with E320', () {
      final resolved = enrichIngredientKnowledge(ing('3', 'BHA', 'unknown'));
      expect(resolved.eCode, 'E320');
    });
  });

  // ── TBHQ / E319 ────────────────────────────────────────────────────────────

  group('TBHQ / E319', () {
    test('canonical "TBHQ" resolves to tbhq spec with medium risk', () {
      final spec = productRiskSpecForKey('TBHQ');
      expect(spec, isNotNull);
      expect(spec!.groupId, 'tbhq');
      expect(spec.riskLevel, 'medium');
    });

    test('E319 resolves to tbhq', () {
      expect(productRiskSpecForKey('E319')?.groupId, 'tbhq');
    });

    test('TBHQ catalog enriches with E319', () {
      final resolved = enrichIngredientKnowledge(ing('4', 'TBHQ', 'unknown'));
      expect(resolved.eCode, 'E319');
    });
  });

  // ── Antioxidant risk parity ─────────────────────────────────────────────────

  test('BHT, BHA, TBHQ all have same risk level (medium)', () {
    final risks = [
      'BHT',
      'BHA',
      'TBHQ',
    ].map((k) => productRiskSpecForKey(k)?.riskLevel);
    for (final r in risks) {
      expect(
        r,
        'medium',
        reason: 'All antioxidant preservatives must be medium',
      );
    }
  });

  // ── Artificial colours ──────────────────────────────────────────────────────

  group('Artificial colours (high risk)', () {
    for (final entry in <Map<String, String>>[
      {'name': 'Tartrazin', 'groupId': 'tartrazine', 'eCode': 'E102'},
      {'name': 'Allura Red', 'groupId': 'allura_red', 'eCode': 'E129'},
      {'name': 'Sunset Yellow', 'groupId': 'sunset_yellow', 'eCode': 'E110'},
      {'name': 'Brilliant Blue', 'groupId': 'brilliant_blue', 'eCode': 'E133'},
    ]) {
      test('${entry['name']} resolves to high risk by name and E-code', () {
        final byName = productRiskSpecForKey(entry['name']!);
        final byCode = productRiskSpecForKey(entry['eCode']!);
        expect(
          byName?.groupId,
          entry['groupId'],
          reason: '${entry['name']} name lookup must resolve',
        );
        expect(
          byCode?.groupId,
          entry['groupId'],
          reason: '${entry['eCode']} code lookup must resolve to same group',
        );
        expect(
          byName?.riskLevel,
          'high',
          reason: '${entry['name']} must be high risk',
        );
        expect(
          byCode?.riskLevel,
          'high',
          reason: '${entry['eCode']} must be high risk',
        );
      });

      test('${entry['name']} catalog has non-empty content and source', () {
        final resolved = enrichIngredientKnowledge(
          ing('c_${entry['eCode']}', entry['name']!, 'unknown'),
        );
        expect(
          ingredientHasExplanationMetadata(resolved),
          isTrue,
          reason: '${entry['name']} must have catalog content',
        );
        expect(resolved.shortRiskSummary, isNotEmpty);
        expect(
          resolved.shortRiskSummary,
          isNot(contains('Bu içerik için detaylı açıklama henüz eklenmedi.')),
        );
        expect(
          resolved.sourceReferenceEntries?.isNotEmpty ?? false,
          isTrue,
          reason: '${entry['name']} must have source references',
        );
      });
    }
  });

  // ── Nitrite / Nitrate (E250/E251) ───────────────────────────────────────────

  group('Sodium nitrite / nitrate', () {
    test('sodyum nitrit resolves to nitrite with high risk', () {
      final spec = productRiskSpecForKey('sodyum nitrit');
      expect(spec?.groupId, 'nitrite');
      expect(spec?.riskLevel, 'high');
    });

    test('E250 resolves to nitrite', () {
      expect(productRiskSpecForKey('E250')?.groupId, 'nitrite');
    });

    test('E251 resolves to nitrite', () {
      expect(productRiskSpecForKey('E251')?.groupId, 'nitrite');
    });

    test('sodyum nitrit catalog has EFSA source', () {
      final resolved = enrichIngredientKnowledge(
        ing('n1', 'Sodyum nitrit', 'unknown'),
      );
      expect(resolved.shortRiskSummary, isNotEmpty);
      expect(
        resolved.sourceReferenceEntries?.any(
          (r) => r.authority.contains('EFSA') || r.authority.contains('WHO'),
        ),
        isTrue,
      );
    });
  });

  // ── MSG / E621 ──────────────────────────────────────────────────────────────

  group('MSG / E621', () {
    test('monosodyum glutamat resolves to msg with medium risk', () {
      final spec = productRiskSpecForKey('Monosodyum glutamat');
      expect(spec?.groupId, 'msg');
      expect(spec?.riskLevel, 'medium');
    });

    test('MSG catalog has content and EFSA source', () {
      final resolved = enrichIngredientKnowledge(
        ing('m1', 'Monosodyum glutamat', 'unknown'),
      );
      expect(resolved.shortRiskSummary, isNotEmpty);
      expect(
        resolved.sourceReferenceEntries?.any((r) => r.authority == 'EFSA'),
        isTrue,
      );
    });
  });

  // ── Carrageenan ─────────────────────────────────────────────────────────────

  group('Carrageenan / E407', () {
    test('karagenan (single-r) resolves to carrageenan', () {
      expect(productRiskSpecForKey('karagenan')?.groupId, 'carrageenan');
      expect(productRiskSpecForKey('karagenan')?.riskLevel, 'medium');
    });

    test('E407 resolves to carrageenan', () {
      expect(productRiskSpecForKey('E407')?.groupId, 'carrageenan');
    });
  });

  // ── Cyclamate / E952 ────────────────────────────────────────────────────────

  group('Cyclamate / E952', () {
    test('siklamat resolves to cyclamate spec', () {
      expect(productRiskSpecForKey('siklamat')?.groupId, 'cyclamate');
      expect(productRiskSpecForKey('siklamat')?.riskLevel, 'medium');
    });

    test('E952 resolves to cyclamate', () {
      expect(productRiskSpecForKey('E952')?.groupId, 'cyclamate');
    });

    test('cyclamate catalog has content', () {
      final resolved = enrichIngredientKnowledge(
        ing('cy1', 'siklamat', 'unknown'),
      );
      expect(resolved.shortRiskSummary, isNotEmpty);
    });
  });

  // ── Maltitol / E965 ─────────────────────────────────────────────────────────

  group('Maltitol / E965', () {
    test('maltitol resolves to maltitol spec', () {
      expect(productRiskSpecForKey('maltitol')?.groupId, 'maltitol');
      expect(productRiskSpecForKey('maltitol')?.riskLevel, 'medium');
    });

    test('maltitol catalog has content', () {
      final resolved = enrichIngredientKnowledge(
        ing('ma1', 'maltitol', 'unknown'),
      );
      expect(resolved.shortRiskSummary, isNotEmpty);
    });
  });

  // ── Soy lecithin / E322 ─────────────────────────────────────────────────────

  group('Soy lecithin / E322', () {
    test('soya lesitini resolves to soy_lecithin spec', () {
      expect(productRiskSpecForKey('Soya lesitini')?.groupId, 'soy_lecithin');
      expect(productRiskSpecForKey('Soya lesitini')?.riskLevel, 'low');
    });

    test('E322 resolves to soy_lecithin', () {
      expect(productRiskSpecForKey('E322')?.groupId, 'soy_lecithin');
    });
  });

  // ── Carmine / E120 ─────────────────────────────────────────────────────────

  group('Carmine / E120', () {
    test('karmin resolves to carmine spec', () {
      expect(productRiskSpecForKey('karmin')?.groupId, 'carmine');
      expect(productRiskSpecForKey('karmin')?.riskLevel, 'medium');
    });

    test('E120 resolves to carmine', () {
      expect(productRiskSpecForKey('E120')?.groupId, 'carmine');
    });

    test('carmine catalog has EFSA source', () {
      final resolved = enrichIngredientKnowledge(
        ing('ca1', 'karmin', 'unknown'),
      );
      expect(resolved.shortRiskSummary, isNotEmpty);
      expect(
        resolved.sourceReferenceEntries?.any((r) => r.authority == 'EFSA'),
        isTrue,
      );
    });
  });

  // ── Catalog riskLevel: fallback for 'unknown' ────────────────────────────────

  group('Catalog riskLevel fallback for DB-unknown ingredients', () {
    test('DB-unknown BHT gets catalog medium riskLevel', () {
      final resolved = enrichIngredientKnowledge(ing('r1', 'BHT', 'unknown'));
      expect(resolved.riskLevel, 'medium');
    });

    test('DB-high BHT preserves DB riskLevel (catalog does not override)', () {
      final resolved = enrichIngredientKnowledge(ing('r2', 'BHT', 'high'));
      // DB 'high' is preserved; canonical severity is via canonicalRiskLevelForIngredient()
      expect(resolved.riskLevel, 'high');
    });

    test('DB-medium Brilliant Blue preserves DB riskLevel', () {
      final resolved = enrichIngredientKnowledge(
        ing('r3', 'Brilliant Blue', 'medium'),
      );
      expect(resolved.riskLevel, 'medium');
    });
  });

  // ── canonicalRiskLevelForIngredient ─────────────────────────────────────────

  group('canonicalRiskLevelForIngredient', () {
    test('uses spec riskLevel when spec exists (overrides DB)', () {
      // BHT: spec = medium, DB = high
      final canonical = canonicalRiskLevelForIngredient(
        ing('cr1', 'BHT', 'high'),
      );
      expect(canonical, 'medium');
    });

    test('falls back to DB riskLevel when no spec exists', () {
      final canonical = canonicalRiskLevelForIngredient(
        ing('cr2', 'completely unknown ingredient xyz', 'medium'),
      );
      expect(canonical, 'medium');
    });

    test('Brilliant Blue DB-medium returns high from spec', () {
      final canonical = canonicalRiskLevelForIngredient(
        ing('cr3', 'Brilliant Blue', 'medium'),
      );
      expect(canonical, 'high');
    });
  });

  // ── No placeholder for high/medium entries ──────────────────────────────────

  group('No placeholder text for known high/medium additives', () {
    const highMediumAdditives = [
      'BHT',
      'BHA',
      'TBHQ',
      'Brilliant Blue',
      'Tartrazin',
      'Allura Red',
      'Sunset Yellow',
      'karmin',
      'Sodyum nitrit',
      'Monosodyum glutamat',
      'maltodekstrin',
      'maltitol',
      'siklamat',
    ];

    const forbiddenPhrases = [
      'Bu içerik için detaylı açıklama henüz eklenmedi.',
      'Detaylı açıklama yok.',
      'Açıklama eklenecek.',
      'TODO',
      'TBD',
    ];

    for (final name in highMediumAdditives) {
      test('$name has no placeholder text in catalog', () {
        final resolved = enrichIngredientKnowledge(
          ing('p_$name', name, 'unknown'),
        );
        final text = [
          resolved.shortPurpose ?? '',
          resolved.shortRiskSummary ?? '',
          resolved.processingRole ?? '',
        ].join(' ');

        for (final phrase in forbiddenPhrases) {
          expect(
            text,
            isNot(contains(phrase)),
            reason: '$name must not have placeholder: "$phrase"',
          );
        }
      });
    }
  });

  // ── Alias deduplication ─────────────────────────────────────────────────────

  group('Alias dedupe: same spec groupId for all aliases', () {
    test('BHT and E321 map to same groupId', () {
      expect(
        productRiskSpecForKey('BHT')?.groupId,
        productRiskSpecForKey('E321')?.groupId,
      );
    });

    test('Brilliant Blue and E133 map to same groupId', () {
      expect(
        productRiskSpecForKey('Brilliant Blue')?.groupId,
        productRiskSpecForKey('E133')?.groupId,
      );
    });

    test('Tartrazin and E102 map to same groupId', () {
      expect(
        productRiskSpecForKey('Tartrazin')?.groupId,
        productRiskSpecForKey('E102')?.groupId,
      );
    });

    test('Allura Red and E129 map to same groupId', () {
      expect(
        productRiskSpecForKey('Allura Red')?.groupId,
        productRiskSpecForKey('E129')?.groupId,
      );
    });

    test('Sunset Yellow and E110 map to same groupId', () {
      expect(
        productRiskSpecForKey('Sunset Yellow')?.groupId,
        productRiskSpecForKey('E110')?.groupId,
      );
    });
  });

  // ── normalizeIngredientDisplayKey ──────────────────────────────────────────

  group('normalizeIngredientDisplayKey', () {
    test('uppercased BHT normalizes to bht', () {
      expect(normalizeIngredientDisplayKey('BHT'), 'bht');
    });

    test('E-321 with hyphen normalizes to e-321', () {
      expect(normalizeIngredientDisplayKey('E-321'), 'e-321');
    });

    test('leading/trailing punctuation stripped', () {
      expect(normalizeIngredientDisplayKey(' BHT, '), 'bht');
    });
  });
}
