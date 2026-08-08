import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_evidence_snapshot.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/nns_evidence_detector.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/scoring_evidence_admin_review_service.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/scoring_evidence_merger.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/scoring_evidence_nutrition_consistency.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/scoring_evidence_ocr_candidate_builder.dart';
import 'package:food_analyzer_app/features/product/models/nutrition_data.dart';

void main() {
  const ocrBuilder = ScoringEvidenceOcrCandidateBuilder();
  const adminService = ScoringEvidenceAdminReviewService();
  const nnsDetector = NnsEvidenceDetector();

  ScoringEvidenceAdminDraft adminDraft({
    Map<String, dynamic>? nutrition,
    String ingredients = 'su, şeker',
    NutritionBasis basis = NutritionBasis.per100g,
    NutritionProductState state = NutritionProductState.asSold,
    IngredientEvidenceCompleteness completeness =
        IngredientEvidenceCompleteness.complete,
    CompositionPercentageState fvlState = CompositionPercentageState.known,
    double? fvlPercentage = 0,
    PresenceEvidenceState nnsState = PresenceEvidenceState.absent,
    ScoringCategory category = ScoringCategory.generalFood,
    bool? redMeatPrimary,
    double? redMeatPercentage,
  }) {
    return ScoringEvidenceAdminDraft(
      reviewedNutrition:
          nutrition ??
          const {
            'energy_kj': 840,
            'energy_kcal': 200,
            'fat': 3,
            'saturated_fat': 1,
            'sugars': 5,
            'proteins': 4,
            'fiber': 2,
            'salt': 0.5,
            'sodium': 0.2,
          },
      ingredientText: ingredients,
      nutritionBasis: basis,
      productState: state,
      ingredientCompleteness: completeness,
      fvlState: fvlState,
      fvlPercentage: fvlPercentage,
      nnsState: nnsState,
      category: category,
      redMeatIsPrimaryIngredient: redMeatPrimary,
      redMeatPercentage: redMeatPercentage,
      verifiedAt: DateTime.utc(2026, 8, 8),
    );
  }

  group('OCR evidence candidates', () {
    test('declared energy kJ is preserved independently', () {
      final evidence = ocrBuilder.build(
        nutrition: const {'energy_kj': 840, 'energy_kcal': 200},
      )!;
      expect(evidence.nutrition.energyKj.value, 840);
      expect(
        evidence.nutrition.energyKj.provenance,
        EvidenceProvenance.ocrDeclaredLabel,
      );
    });

    test('kcal-only extraction never fabricates declared kJ', () {
      final evidence = ocrBuilder.build(nutrition: const {'energy_kcal': 200})!;
      expect(evidence.nutrition.energyKcal.value, 200);
      expect(evidence.nutrition.energyKj.value, isNull);
    });

    test('explicit 100 g candidate remains unverified OCR evidence', () {
      final evidence = ocrBuilder.build(
        evidenceCandidates: const {'nutrition_basis': 'per100g'},
      )!;
      expect(evidence.nutritionBasis, NutritionBasis.per100g);
      expect(
        evidence.nutritionBasisEvidence?.verification,
        EvidenceVerification.unverified,
      );
      expect(evidence.toScoringInput().nutritionBasis, NutritionBasis.unknown);
    });

    test('explicit 100 ml candidate is retained', () {
      final evidence = ocrBuilder.build(
        evidenceCandidates: const {'nutrition_basis': 'per100ml'},
      )!;
      expect(evidence.nutritionBasis, NutritionBasis.per100ml);
    });

    test('serving-only candidate is retained without conversion', () {
      final evidence = ocrBuilder.build(
        evidenceCandidates: const {'nutrition_basis': 'perServing'},
      )!;
      expect(evidence.nutritionBasis, NutritionBasis.perServing);
    });

    test('ambiguous or absent basis remains unknown', () {
      final evidence = ocrBuilder.build(
        nutrition: const {'energy_kcal': 200},
        evidenceCandidates: const {'nutrition_basis': 'unknown'},
      )!;
      expect(evidence.nutritionBasis, NutritionBasis.unknown);
      expect(evidence.nutritionBasisEvidence, isNull);
    });

    test('product text cannot influence nutrition basis', () {
      final evidence = ocrBuilder.build(
        nutrition: const {'sugars': 4},
        ingredientsText: 'Sıvı içecek ürünü',
      )!;
      expect(evidence.nutritionBasis, NutritionBasis.unknown);
    });

    test('explicit ingredient percentage candidate is preserved', () {
      final evidence = ocrBuilder.build(
        evidenceCandidates: const {
          'ingredient_percentages': [
            {
              'ingredient_text': 'elma püresi',
              'percentage': 20,
              'evidence_text': 'elma püresi %20',
            },
          ],
        },
      )!;
      expect(evidence.ingredientPercentageCandidates.single.percentage, 20);
      expect(evidence.fvlEvidence.state, CompositionPercentageState.unknown);
    });

    test('ingredient order never estimates a percentage', () {
      final evidence = ocrBuilder.build(
        nutrition: const {'sugars': 4},
        ingredientsText: 'elma püresi, su, şeker',
      )!;
      expect(evidence.ingredientPercentageCandidates, isEmpty);
      expect(evidence.fvlEvidence.percentage, isNull);
    });

    test('explicit product state candidate remains unverified', () {
      final evidence = ocrBuilder.build(
        evidenceCandidates: const {'nutrition_product_state': 'asPrepared'},
      )!;
      expect(evidence.nutritionProductState, NutritionProductState.asPrepared);
      expect(
        evidence.nutritionProductStateEvidence?.verification,
        EvidenceVerification.unverified,
      );
    });
  });

  group('NNS exact detection', () {
    test('exact qualifying E-number creates a present candidate', () {
      final evidence = nnsDetector.ocrCandidate('su, E 950, aroma');
      expect(evidence.state, PresenceEvidenceState.present);
      expect(evidence.verification, EvidenceVerification.unverified);
    });

    test('exact canonical alias creates a present candidate', () {
      expect(
        nnsDetector.detect('su, aspartam, aroma').hasQualifyingMatch,
        isTrue,
      );
    });

    test('excluded polyol does not become qualifying NNS', () {
      expect(
        nnsDetector.detect('sorbitol, eritritol, E 420').hasQualifyingMatch,
        isFalse,
      );
    });

    test('no match with incomplete evidence remains unknown', () {
      final evidence = nnsDetector.adminVerified(
        ingredientText: 'su, şeker',
        completeness: IngredientEvidenceCompleteness.incomplete,
      );
      expect(evidence.state, PresenceEvidenceState.unknown);
    });

    test('complete verified list with no match may become absent', () {
      final evidence = nnsDetector.adminVerified(
        ingredientText: 'su, şeker',
        completeness: IngredientEvidenceCompleteness.complete,
      );
      expect(evidence.state, PresenceEvidenceState.absent);
      expect(evidence.verification, EvidenceVerification.verified);
    });

    test('empty text cannot prove NNS absence', () {
      final evidence = nnsDetector.adminVerified(
        ingredientText: ' ',
        completeness: IngredientEvidenceCompleteness.complete,
      );
      expect(evidence.state, PresenceEvidenceState.unknown);
    });

    test('random substring does not create authoritative NNS', () {
      expect(
        nnsDetector.detect('aspartamlı aroma ifadesi').hasQualifyingMatch,
        isFalse,
      );
    });
  });

  group('admin verification', () {
    test('unknown FVL remains unknown', () {
      final result = adminService.build(
        adminDraft(
          fvlState: CompositionPercentageState.unknown,
          fvlPercentage: null,
        ),
      );
      expect(
        result.evidence.fvlEvidence.state,
        CompositionPercentageState.unknown,
      );
    });

    test('admin known FVL 20 percent persists', () {
      final result = adminService.build(adminDraft(fvlPercentage: 20));
      expect(result.evidence.fvlEvidence.percentage, 20);
      expect(
        result.evidence.fvlEvidence.provenance,
        EvidenceProvenance.adminVerified,
      );
    });

    test('admin proven FVL absence persists with complete ingredients', () {
      final result = adminService.build(
        adminDraft(
          fvlState: CompositionPercentageState.provenAbsent,
          fvlPercentage: null,
        ),
      );
      expect(
        result.evidence.fvlEvidence.state,
        CompositionPercentageState.provenAbsent,
      );
    });

    test('FVL absence with incomplete ingredients is rejected safely', () {
      final result = adminService.build(
        adminDraft(
          completeness: IngredientEvidenceCompleteness.incomplete,
          fvlState: CompositionPercentageState.provenAbsent,
          fvlPercentage: null,
        ),
      );
      expect(result.isValid, isFalse);
      expect(
        result.evidence.fvlEvidence.state,
        CompositionPercentageState.unknown,
      );
    });

    test('invalid FVL percentage is rejected', () {
      final result = adminService.build(adminDraft(fvlPercentage: 101));
      expect(result.isValid, isFalse);
      expect(result.evidence.fvlEvidence.percentage, isNull);
    });

    test('admin verifies basis and product state provenance', () {
      final evidence = adminService.build(adminDraft()).evidence;
      expect(
        evidence.nutritionBasisEvidence?.provenance,
        EvidenceProvenance.adminVerified,
      );
      expect(evidence.toScoringInput().nutritionBasis, NutritionBasis.per100g);
      expect(
        evidence.nutritionProductStateEvidence?.verification,
        EvidenceVerification.verified,
      );
    });

    test('admin-reviewed kJ and sugars become admin verified', () {
      final nutrition = adminService.build(adminDraft()).evidence.nutrition;
      expect(nutrition.energyKj.value, 840);
      expect(nutrition.energyKj.provenance, EvidenceProvenance.adminVerified);
      expect(nutrition.sugars.provenance, EvidenceProvenance.adminVerified);
    });

    test('admin-reviewed printed salt becomes admin verified', () {
      final salt = adminService.build(adminDraft()).evidence.nutrition.salt;
      expect(salt.value, 0.5);
      expect(salt.provenance, EvidenceProvenance.adminVerified);
    });

    test('salt derived only from verified sodium keeps derived provenance', () {
      final result = adminService.build(
        adminDraft(nutrition: const {'energy_kj': 840, 'sodium': 0.2}),
      );
      expect(result.evidence.nutrition.salt.value, 0.5);
      expect(
        result.evidence.nutrition.salt.provenance,
        EvidenceProvenance.derivedFromSodium,
      );
    });

    test('admin ingredient completeness is persisted', () {
      final evidence = adminService.build(adminDraft()).evidence;
      expect(
        evidence.ingredientEvidenceCompleteness,
        IngredientEvidenceCompleteness.complete,
      );
    });

    test('admin NNS absence requires compatible complete evidence', () {
      final result = adminService.build(
        adminDraft(
          completeness: IngredientEvidenceCompleteness.unknown,
          nnsState: PresenceEvidenceState.absent,
        ),
      );
      expect(result.isValid, isFalse);
      expect(result.evidence.nnsEvidence.state, PresenceEvidenceState.unknown);
    });

    test('admin cannot mark an exact qualifying NNS absent', () {
      final result = adminService.build(
        adminDraft(
          ingredients: 'su, sukraloz',
          nnsState: PresenceEvidenceState.absent,
        ),
      );
      expect(result.isValid, isFalse);
      expect(result.evidence.nnsEvidence.state, PresenceEvidenceState.unknown);
    });

    test('admin red-meat category uses resolver facts', () {
      final incomplete = adminService.build(
        adminDraft(category: ScoringCategory.redMeat),
      );
      expect(
        incomplete.evidence.categoryEvidence.resolvedCategory,
        ScoringCategory.unknown,
      );
      final complete = adminService.build(
        adminDraft(
          category: ScoringCategory.redMeat,
          redMeatPercentage: 20,
          redMeatPrimary: true,
        ),
      );
      expect(
        complete.evidence.categoryEvidence.resolvedCategory,
        ScoringCategory.redMeat,
      );
    });

    test('complete general-food review can become ready', () {
      final result = adminService.build(adminDraft());
      expect(result.isValid, isTrue);
      expect(result.readiness.blockingReasons, isEmpty);
      expect(result.readiness.isScorable, isTrue);
    });

    test('missing declared kJ remains a readiness blocker', () {
      final result = adminService.build(
        adminDraft(nutrition: const {'energy_kcal': 200}),
      );
      expect(
        result.readiness.blockingReasons,
        contains(ScoringReadinessBlocker.missingEnergyKj),
      );
    });
  });

  group('persistence consistency', () {
    test('candidate metadata round-trips without becoming verified', () {
      final original = ocrBuilder.build(
        evidenceCandidates: const {'nutrition_basis': 'per100g'},
      )!;
      final decoded = ScoringEvidenceSnapshot.tryFromJson(original.toJson())!;
      expect(decoded.nutritionBasisEvidence?.value, NutritionBasis.per100g);
      expect(
        decoded.nutritionBasisEvidence?.verification,
        EvidenceVerification.unverified,
      );
    });

    test('trusted basis wins over conflicting OCR candidate', () {
      final existing = adminService.build(adminDraft()).evidence;
      final incoming = ocrBuilder.build(
        evidenceCandidates: const {'nutrition_basis': 'per100ml'},
      )!;
      final result = const ScoringEvidenceMerger().merge(existing, incoming);
      expect(result.evidence?.nutritionBasis, NutritionBasis.per100g);
      expect(
        result.conflicts.map((item) => item.field),
        contains('nutrition_basis'),
      );
    });

    test('nutrition mismatch is removed before product merge', () {
      final incoming = adminService.build(adminDraft()).evidence;
      final aligned = const ScoringEvidenceNutritionConsistency().align(
        incoming,
        const NutritionData(energyKj: 900, sugars: 5, salt: 0.5),
      );
      expect(aligned.nutrition.energyKj.value, isNull);
      expect(aligned.nutrition.sugars.value, 5);
    });

    test('unknown incoming evidence does not replace trusted evidence', () {
      final existing = adminService.build(adminDraft()).evidence;
      final merged = const ScoringEvidenceMerger().merge(
        existing,
        ScoringEvidenceSnapshot(),
      );
      expect(merged.evidence?.nutrition.energyKj.value, 840);
      expect(merged.evidence?.nutritionBasis, NutritionBasis.per100g);
    });
  });
}
