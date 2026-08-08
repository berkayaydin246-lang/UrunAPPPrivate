import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/analysis/models/canonical_additive_assessment.dart';
import 'package:food_analyzer_app/features/analysis/services/canonical_ingredient_risk_service.dart';
import 'package:food_analyzer_app/features/product/data/ingredient_explanation_catalog.dart';
import 'package:food_analyzer_app/features/product/models/ingredient.dart';
import 'package:food_analyzer_app/features/product/widgets/product_detail_shared.dart';

Ingredient _ingredient(String id, String name, String riskLevel) => Ingredient(
  id: id,
  name: name,
  normalizedName: name.toLowerCase(),
  riskLevel: riskLevel,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

Ingredient _catalogCode(String eCode) => Ingredient(
  id: 'catalog-$eCode',
  name: 'Catalogue fixture $eCode',
  normalizedName: 'catalogue fixture ${eCode.toLowerCase()}',
  eCode: eCode,
  riskLevel: 'unknown',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

const _legacyDisplayCoverage = <({String name, String eCode, String groupId})>[
  (name: 'BHT', eCode: 'E321', groupId: 'bht'),
  (name: 'BHA', eCode: 'E320', groupId: 'bha'),
  (name: 'TBHQ', eCode: 'E319', groupId: 'tbhq'),
  (name: 'Tartrazin', eCode: 'E102', groupId: 'tartrazine'),
  (name: 'Allura Red', eCode: 'E129', groupId: 'allura_red'),
  (name: 'Sunset Yellow', eCode: 'E110', groupId: 'sunset_yellow'),
  (name: 'Brilliant Blue', eCode: 'E133', groupId: 'brilliant_blue'),
  (name: 'Sodyum nitrit', eCode: 'E250', groupId: 'nitrite'),
  (name: 'Sodyum nitrat', eCode: 'E251', groupId: 'nitrite'),
  (name: 'Monosodyum glutamat', eCode: 'E621', groupId: 'msg'),
  (name: 'Karagenan', eCode: 'E407', groupId: 'carrageenan'),
  (name: 'Siklamat', eCode: 'E952', groupId: 'cyclamate'),
  (name: 'Maltitol', eCode: 'E965', groupId: 'maltitol'),
  (name: 'Soya lesitini', eCode: 'E322', groupId: 'soy_lecithin'),
  (name: 'Karmin', eCode: 'E120', groupId: 'carmine'),
];

void main() {
  const service = CanonicalIngredientRiskService();

  group('display-only product specs', () {
    test('BHT aliases retain one display identity', () {
      expect(productRiskSpecForKey('BHT')?.groupId, 'bht');
      expect(productRiskSpecForKey('E321')?.groupId, 'bht');
      expect(productRiskSpecForKey('E-321')?.groupId, 'bht');
      expect(productRiskSpecForKey('Butil hidroksi toluen')?.groupId, 'bht');
    });

    test('display spec retains non-risk presentation metadata', () {
      final spec = productRiskSpecForKey('BHT');

      expect(spec, isNotNull);
      expect(spec!.displayName, contains('BHT'));
      expect(spec.category, ProductRiskCategory.preservative);
      expect(spec.riskSummary, isNotEmpty);
    });

    test('different color additives retain separate display identities', () {
      expect(productRiskSpecForKey('E102')?.groupId, 'tartrazine');
      expect(productRiskSpecForKey('E129')?.groupId, 'allura_red');
      expect(productRiskSpecForKey('E110')?.groupId, 'sunset_yellow');
      expect(productRiskSpecForKey('E133')?.groupId, 'brilliant_blue');
    });

    for (final entry in _legacyDisplayCoverage) {
      test('${entry.name} retains its legacy display identity', () {
        expect(productRiskSpecForKey(entry.name)?.groupId, entry.groupId);
        if (entry.eCode != 'E621' && entry.eCode != 'E965') {
          expect(productRiskSpecForKey(entry.eCode)?.groupId, entry.groupId);
        }
      });
    }

    test('BHT legacy spelling variants retain display identity', () {
      for (final alias in const [
        'E-321',
        'E 321',
        'Butil hidroksi toluen',
        'Butylated Hydroxytoluene',
      ]) {
        expect(productRiskSpecForKey(alias)?.groupId, 'bht', reason: alias);
      }
    });
  });

  group('catalogue source and canonical resolver', () {
    test('educational enrichment does not independently change risk', () {
      final enriched = enrichIngredientKnowledge(
        _ingredient('bht-unknown', 'BHT', 'unknown'),
      );

      expect(enriched.eCode, 'E321');
      expect(enriched.riskLevel, 'unknown');
      expect(enriched.shortPurpose, isNotEmpty);
      expect(enriched.sourceReferenceEntries, isNotEmpty);
    });

    test('canonical service applies reviewed fallback for unknown BHT', () {
      final item = service.assessIngredient(
        _ingredient('bht-reviewed', 'BHT', 'unknown'),
      );

      expect(item.riskLevel, CanonicalRiskLevel.medium);
      expect(item.riskSource, CanonicalRiskSource.reviewedExplanationCatalogue);
    });

    test('catalogue disagreement becomes visible unknown conflict', () {
      final item = service.assessIngredient(
        _ingredient('bht-conflict', 'BHT', 'high'),
      );

      expect(item.riskLevel, CanonicalRiskLevel.unknown);
      expect(item.riskSource, CanonicalRiskSource.unresolvedConflict);
      expect(item.conflicts, hasLength(1));
    });

    test('product detail risk helper delegates to canonical service', () {
      expect(
        canonicalRiskLevelForIngredient(
          _ingredient('bht-helper', 'BHT', 'high'),
        ),
        'unknown',
      );
    });

    test('known catalogue entries retain reviewed explanatory sources', () {
      for (final name in [
        'BHT',
        'BHA',
        'TBHQ',
        'Tartrazin',
        'Brilliant Blue',
        'Sodyum Nitrit',
        'Monosodyum Glutamat',
        'Karmin',
      ]) {
        final enriched = enrichIngredientKnowledge(
          _ingredient('source-$name', name, 'unknown'),
        );
        expect(enriched.shortPurpose, isNotEmpty, reason: name);
        expect(enriched.shortRiskSummary, isNotEmpty, reason: name);
        expect(enriched.sourceReferenceEntries, isNotEmpty, reason: name);
      }
    });

    for (final entry in _legacyDisplayCoverage) {
      test(
        '${entry.name} keeps sourced non-placeholder catalogue metadata',
        () {
          final enriched = enrichIngredientKnowledge(
            _ingredient('metadata-${entry.eCode}', entry.name, 'unknown'),
          );
          final explanation = [
            enriched.shortPurpose ?? '',
            enriched.shortRiskSummary ?? '',
            enriched.processingRole ?? '',
          ].join(' ');

          expect(enriched.eCode, entry.eCode);
          expect(ingredientHasExplanationMetadata(enriched), isTrue);
          expect(enriched.sourceReferenceEntries, isNotEmpty);
          expect(explanation, isNot(contains('TODO')));
          expect(explanation, isNot(contains('TBD')));
          expect(
            explanation,
            isNot(contains('detaylı açıklama henüz eklenmedi')),
          );
        },
      );
    }
  });

  group('reviewed hard-coded rule coverage', () {
    CanonicalRiskLevel riskFor(String eCode) =>
        service.assessIngredient(_catalogCode(eCode)).riskLevel;

    test('BHT E321 retains reviewed medium', () {
      expect(riskFor('E321'), CanonicalRiskLevel.medium);
    });

    test('BHA E320 retains reviewed medium', () {
      expect(riskFor('E320'), CanonicalRiskLevel.medium);
    });

    test('TBHQ E319 retains reviewed medium', () {
      expect(riskFor('E319'), CanonicalRiskLevel.medium);
    });

    test('Tartrazine E102 retains reviewed high', () {
      expect(riskFor('E102'), CanonicalRiskLevel.high);
    });

    test('Sunset Yellow E110 retains reviewed high', () {
      expect(riskFor('E110'), CanonicalRiskLevel.high);
    });

    test('Carmine E120 retains reviewed medium', () {
      expect(riskFor('E120'), CanonicalRiskLevel.medium);
    });

    test('Allura Red E129 retains reviewed high', () {
      expect(riskFor('E129'), CanonicalRiskLevel.high);
    });

    test('Brilliant Blue E133 retains reviewed high', () {
      expect(riskFor('E133'), CanonicalRiskLevel.high);
    });

    test('Sodium nitrite E250 retains reviewed high', () {
      expect(riskFor('E250'), CanonicalRiskLevel.high);
    });

    test('Sodium nitrate E251 retains reviewed high', () {
      expect(riskFor('E251'), CanonicalRiskLevel.high);
    });

    test('Sorbic acid E200 retains reviewed medium', () {
      expect(riskFor('E200'), CanonicalRiskLevel.medium);
    });

    test('Potassium sorbate E202 retains reviewed medium', () {
      expect(riskFor('E202'), CanonicalRiskLevel.medium);
    });

    test('Benzoic acid E210 retains reviewed medium', () {
      expect(riskFor('E210'), CanonicalRiskLevel.medium);
    });

    test('Sodium benzoate E211 retains reviewed medium', () {
      expect(riskFor('E211'), CanonicalRiskLevel.medium);
    });

    test('Acesulfame K E950 retains reviewed medium', () {
      expect(riskFor('E950'), CanonicalRiskLevel.medium);
    });

    test('Aspartame E951 retains reviewed high', () {
      expect(riskFor('E951'), CanonicalRiskLevel.high);
    });

    test('Cyclamate E952 retains reviewed medium', () {
      expect(riskFor('E952'), CanonicalRiskLevel.medium);
    });

    test('Saccharin E954 retains reviewed medium', () {
      expect(riskFor('E954'), CanonicalRiskLevel.medium);
    });

    test('Sucralose E955 retains reviewed medium', () {
      expect(riskFor('E955'), CanonicalRiskLevel.medium);
    });

    test('Maltitol E965 retains reviewed medium', () {
      expect(riskFor('E965'), CanonicalRiskLevel.medium);
    });

    test('uncovered nitrite E249 remains unknown', () {
      expect(riskFor('E249'), CanonicalRiskLevel.unknown);
    });

    test('uncovered NNS E957 remains unknown', () {
      expect(riskFor('E957'), CanonicalRiskLevel.unknown);
    });
  });

  group('display key normalization', () {
    test('normalizes case and surrounding punctuation', () {
      expect(normalizeIngredientDisplayKey(' BHT, '), 'bht');
    });

    test('preserves meaningful E-code separators for display matching', () {
      expect(normalizeIngredientDisplayKey('E-321'), 'e-321');
    });
  });
}
