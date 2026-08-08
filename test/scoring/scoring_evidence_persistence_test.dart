import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/admin/repositories/product_staging_approval_repository.dart';
import 'package:food_analyzer_app/features/admin/repositories/product_submission_approval_repository.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/product_staging/models/product_candidate.dart';
import 'package:food_analyzer_app/features/scoring/adapters/product_scoring_input_adapter.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/composition_percentage_evidence.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/evidence_value.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/presence_evidence.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_category_evidence.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_classification_facts.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_evidence_snapshot.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_nutrition_data.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/scoring_evidence_merger.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/scoring_readiness_evaluator.dart';
import 'package:food_analyzer_app/features/submission/models/product_submission.dart';

void main() {
  final timestamp = DateTime.utc(2026, 8, 8);

  EvidenceValue<double> numeric(
    double value, {
    EvidenceProvenance provenance = EvidenceProvenance.declaredLabel,
    EvidenceVerification verification = EvidenceVerification.verified,
  }) {
    return EvidenceValue<double>(
      value: value,
      provenance: provenance,
      verification: verification,
    );
  }

  ScoringEvidenceSnapshot fullSnapshot({
    EvidenceValue<double>? energyKj,
    EvidenceValue<double>? salt,
    NutritionBasis basis = NutritionBasis.per100ml,
    ScoringCategory category = ScoringCategory.beverage,
  }) {
    return ScoringEvidenceSnapshot(
      nutritionBasis: basis,
      nutritionProductState: NutritionProductState.asSold,
      nutrition: ScoringNutritionData(
        energyKj: energyKj ?? numeric(180),
        energyKcal: numeric(43),
        totalFat: numeric(0),
        saturatedFat: numeric(0),
        sugars: numeric(10.5),
        protein: numeric(0),
        fiber: numeric(0),
        salt: salt ?? numeric(0.1),
        sodium: numeric(0.04),
      ),
      fvlEvidence: const CompositionPercentageEvidence.known(
        0,
        provenance: EvidenceProvenance.adminVerified,
        verification: EvidenceVerification.verified,
      ),
      nnsEvidence: const PresenceEvidence.absent(
        provenance: EvidenceProvenance.adminVerified,
        verification: EvidenceVerification.verified,
        dependency: EvidenceDependency.completeIngredientList,
      ),
      ingredientEvidenceCompleteness: IngredientEvidenceCompleteness.complete,
      categoryEvidence: ScoringCategoryEvidence(
        resolvedCategory: category,
        source: CategoryEvidenceSource.manualAdminVerification,
        evidenceValues: const ['admin-review'],
        reasons: const [CategoryResolutionReason.resolvedFromExplicitMetadata],
      ),
      classificationFacts: const ScoringClassificationFacts(
        isBeverage: EvidenceValue<bool>(
          value: true,
          provenance: EvidenceProvenance.adminVerified,
          verification: EvidenceVerification.verified,
        ),
        isPlainWater: EvidenceValue<bool>(
          value: false,
          provenance: EvidenceProvenance.adminVerified,
          verification: EvidenceVerification.verified,
        ),
      ),
      adminVerification: ScoringEvidenceAdminMetadata(
        verifiedBy: 'admin-id',
        verifiedAt: timestamp,
        note: 'label checked',
      ),
    );
  }

  Product product({
    String name = 'Test Product',
    ScoringEvidenceSnapshot? evidence,
  }) {
    return Product(
      id: 'product-id',
      name: name,
      nutritionText: '{"energy_kcal":43}',
      scoringEvidence: evidence,
      verificationStatus: 'verified',
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }

  ProductSubmission submission({ScoringEvidenceSnapshot? evidence}) {
    return ProductSubmission(
      id: 'submission-id',
      barcode: '8690000000001',
      productName: 'Test Product',
      extractedNutrition: const {'energy_kj': 180, 'energy_kcal': 43},
      scoringEvidence: evidence,
      status: 'pending',
      source: 'barcode_missing',
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }

  ProductCandidate candidate({ScoringEvidenceSnapshot? evidence}) {
    return ProductCandidate(
      id: 'staging-id',
      barcode: '8690000000001',
      name: 'Test Product',
      ingredientsText: 'su, şeker, doğal aroma',
      nutritionJson: const {'energy_kj': 180, 'energy_kcal': 43},
      scoringEvidence: evidence,
      source: 'web_scraper:migros',
      sourceUrl: 'https://www.migros.com.tr/test-p-1',
    );
  }

  group('versioned evidence serialization', () {
    test('full snapshot round-trips without losing evidence', () {
      final original = fullSnapshot();
      final decoded = ScoringEvidenceSnapshot.tryFromJson(original.toJson());

      expect(decoded, isNotNull);
      expect(decoded!.toJson(), original.toJson());
      expect(decoded.schemaVersion, 1);
      expect(decoded.adminVerification?.verifiedAt, timestamp);
    });

    test('empty unknown snapshot round-trips', () {
      final original = ScoringEvidenceSnapshot();
      final decoded = ScoringEvidenceSnapshot.tryFromJson(original.toJson());

      expect(decoded, isNotNull);
      expect(decoded!.nutritionBasis, NutritionBasis.unknown);
      expect(decoded.nutrition.energyKj.value, isNull);
      expect(decoded.fvlEvidence.state, CompositionPercentageState.unknown);
      expect(decoded.nnsEvidence.state, PresenceEvidenceState.unknown);
    });

    test('unknown enum values degrade safely to unknown', () {
      final json = fullSnapshot().toJson()
        ..['nutrition_basis'] = 'future_basis';
      final nutrition = json['nutrition'] as Map<String, dynamic>;
      nutrition['energy_kj'] = {
        'value': 180,
        'provenance': 'future_provenance',
        'verification': 'verified',
      };

      final decoded = ScoringEvidenceSnapshot.tryFromJson(json)!;
      expect(decoded.nutritionBasis, NutritionBasis.unknown);
      expect(decoded.nutrition.energyKj.provenance, EvidenceProvenance.unknown);
      expect(
        decoded.nutrition.energyKj.verification,
        EvidenceVerification.unknown,
      );
      expect(decoded.nutrition.energyKj.isTrusted, isFalse);
    });

    test('malformed map keys do not throw', () {
      expect(
        () => ScoringEvidenceSnapshot.tryFromJson({1: 'invalid'}),
        returnsNormally,
      );
      expect(ScoringEvidenceSnapshot.tryFromJson({1: 'invalid'}), isNull);
    });

    test('future schema version is unsupported without throwing', () {
      final json = fullSnapshot().toJson()..['schema_version'] = 2;
      expect(ScoringEvidenceSnapshot.tryFromJson(json), isNull);
    });

    test('invalid FVL percentage becomes unknown', () {
      final json = fullSnapshot().toJson();
      json['fvl_evidence'] = {
        'state': 'known',
        'percentage': 101,
        'provenance': 'declared_label',
        'verification': 'verified',
        'dependency': 'none',
      };

      final decoded = ScoringEvidenceSnapshot.tryFromJson(json)!;
      expect(decoded.fvlEvidence.state, CompositionPercentageState.unknown);
      expect(decoded.fvlEvidence.percentage, isNull);
    });

    test('known FVL zero remains known zero', () {
      final decoded = ScoringEvidenceSnapshot.tryFromJson(
        fullSnapshot().toJson(),
      )!;
      expect(decoded.fvlEvidence.state, CompositionPercentageState.known);
      expect(decoded.fvlEvidence.percentage, 0);
    });

    test('proven-absent FVL remains a distinct zero state', () {
      final snapshot = ScoringEvidenceSnapshot(
        fvlEvidence: const CompositionPercentageEvidence.provenAbsent(
          provenance: EvidenceProvenance.declaredLabel,
          verification: EvidenceVerification.verified,
        ),
      );
      final decoded = ScoringEvidenceSnapshot.tryFromJson(snapshot.toJson())!;
      expect(
        decoded.fvlEvidence.state,
        CompositionPercentageState.provenAbsent,
      );
      expect(decoded.fvlEvidence.percentage, 0);
    });

    test('FVL unknown remains distinct from zero', () {
      final decoded = ScoringEvidenceSnapshot.tryFromJson(
        ScoringEvidenceSnapshot().toJson(),
      )!;
      expect(decoded.fvlEvidence.state, CompositionPercentageState.unknown);
      expect(decoded.fvlEvidence.percentage, isNull);
    });

    test('NNS absent remains distinct from unknown', () {
      final absent = ScoringEvidenceSnapshot.tryFromJson(
        fullSnapshot().toJson(),
      )!;
      final unknown = ScoringEvidenceSnapshot.tryFromJson(
        ScoringEvidenceSnapshot().toJson(),
      )!;
      expect(absent.nnsEvidence.state, PresenceEvidenceState.absent);
      expect(unknown.nnsEvidence.state, PresenceEvidenceState.unknown);
    });

    test('NaN and infinity are rejected on read and write', () {
      final json = fullSnapshot().toJson();
      final nutrition = json['nutrition'] as Map<String, dynamic>;
      nutrition['energy_kj'] = {
        'value': double.nan,
        'provenance': 'declared_label',
        'verification': 'verified',
      };
      nutrition['salt'] = {
        'value': double.infinity,
        'provenance': 'declared_label',
        'verification': 'verified',
      };

      final decoded = ScoringEvidenceSnapshot.tryFromJson(json)!;
      expect(decoded.nutrition.energyKj.value, isNull);
      expect(decoded.nutrition.salt.value, isNull);

      final invalid = ScoringEvidenceSnapshot(
        nutrition: const ScoringNutritionData(
          energyKj: EvidenceValue<double>(
            value: double.infinity,
            provenance: EvidenceProvenance.declaredLabel,
            verification: EvidenceVerification.verified,
          ),
        ),
      );
      final serializedNutrition =
          invalid.toJson()['nutrition'] as Map<String, dynamic>;
      expect(
        (serializedNutrition['energy_kj'] as Map<String, dynamic>)['value'],
        isNull,
      );
    });

    test('unknown provenance cannot serialize as verified', () {
      final snapshot = ScoringEvidenceSnapshot(
        nutrition: const ScoringNutritionData(
          energyKj: EvidenceValue<double>(
            value: 180,
            provenance: EvidenceProvenance.unknown,
            verification: EvidenceVerification.verified,
          ),
        ),
      );
      final nutrition = snapshot.toJson()['nutrition'] as Map<String, dynamic>;
      final energy = nutrition['energy_kj'] as Map<String, dynamic>;
      expect(energy['provenance'], 'unknown');
      expect(energy['verification'], 'unknown');
    });

    test('derived salt retains derived provenance', () {
      final original = fullSnapshot(
        salt: numeric(
          0.75,
          provenance: EvidenceProvenance.derivedFromSodium,
          verification: EvidenceVerification.unverified,
        ),
      );
      final decoded = ScoringEvidenceSnapshot.tryFromJson(original.toJson())!;
      expect(
        decoded.nutrition.salt.provenance,
        EvidenceProvenance.derivedFromSodium,
      );
    });

    test(
      'declared value and ingredient completeness retain their evidence',
      () {
        final decoded = ScoringEvidenceSnapshot.tryFromJson(
          fullSnapshot().toJson(),
        )!;
        expect(
          decoded.nutrition.energyKj.provenance,
          EvidenceProvenance.declaredLabel,
        );
        expect(
          decoded.ingredientEvidenceCompleteness,
          IngredientEvidenceCompleteness.complete,
        );
      },
    );
  });

  group('Product adapter', () {
    const adapter = ProductScoringInputAdapter();
    const evaluator = ScoringReadinessEvaluator();

    test('product without persisted evidence remains not scorable', () {
      final result = evaluator.evaluate(adapter.fromProduct(product()));
      expect(result.isScorable, isFalse);
      expect(
        result.blockingReasons,
        contains(ScoringReadinessBlocker.unknownNutritionBasis),
      );
    });

    test('valid persisted evidence populates scoring input', () {
      final input = adapter.fromProduct(product(evidence: fullSnapshot()));
      expect(input.nutrition.energyKj.value, 180);
      expect(input.nutritionBasis, NutritionBasis.per100ml);
      expect(input.productState, NutritionProductState.asSold);
      expect(input.nnsEvidence.state, PresenceEvidenceState.absent);
      expect(evaluator.evaluate(input).isScorable, isTrue);
    });

    test('persisted classification facts are respected', () {
      final input = adapter.fromProduct(product(evidence: fullSnapshot()));
      expect(input.classificationFacts.isBeverage?.trustedValue, isTrue);
      expect(input.categoryEvidence.resolvedCategory, ScoringCategory.beverage);
    });

    test('product name has no effect when persisted evidence is present', () {
      final evidence = fullSnapshot();
      final first = adapter.fromProduct(
        product(name: 'Kola', evidence: evidence),
      );
      final second = adapter.fromProduct(
        product(name: 'Peynir Yazsa Bile', evidence: evidence),
      );
      expect(
        first.categoryEvidence.resolvedCategory,
        second.categoryEvidence.resolvedCategory,
      );
      expect(first.nutritionBasis, second.nutritionBasis);
    });
  });

  group('conservative merge policy', () {
    const merger = ScoringEvidenceMerger();

    test('unknown incoming evidence does not overwrite known evidence', () {
      final result = merger.merge(fullSnapshot(), ScoringEvidenceSnapshot());
      expect(result.evidence!.nutrition.energyKj.value, 180);
      expect(result.evidence!.nutritionBasis, NutritionBasis.per100ml);
      expect(result.changed, isFalse);
    });

    test('unverified OCR does not overwrite admin-verified evidence', () {
      final incoming = fullSnapshot(
        energyKj: numeric(
          220,
          provenance: EvidenceProvenance.ocrDeclaredLabel,
          verification: EvidenceVerification.unverified,
        ),
      );
      final result = merger.merge(fullSnapshot(), incoming);
      expect(result.evidence!.nutrition.energyKj.value, 180);
      expect(
        result.conflicts.map((item) => item.field),
        contains('nutrition.energy_kj'),
      );
    });

    test('higher-trust incoming evidence replaces lower-trust evidence', () {
      final existing = fullSnapshot(
        energyKj: numeric(
          170,
          provenance: EvidenceProvenance.databaseImport,
          verification: EvidenceVerification.unverified,
        ),
      );
      final incoming = fullSnapshot(energyKj: numeric(180));
      final result = merger.merge(existing, incoming);
      expect(result.evidence!.nutrition.energyKj.value, 180);
      expect(result.changed, isTrue);
      expect(result.conflicts.single.incomingSelected, isTrue);
    });

    test('equal-trust contradiction deterministically retains existing', () {
      final result = merger.merge(
        fullSnapshot(energyKj: numeric(170)),
        fullSnapshot(energyKj: numeric(180)),
      );
      expect(result.evidence!.nutrition.energyKj.value, 170);
      expect(result.conflicts.single.incomingSelected, isFalse);
    });
  });

  group('submission and staging persistence', () {
    test('evidence survives product submission JSON and approval mapping', () {
      final evidence = fullSnapshot();
      final decodedSubmission = ProductSubmission.fromJson({
        'id': 'submission-id',
        'barcode': '8690000000001',
        'status': 'pending',
        'source': 'barcode_missing',
        'scoring_evidence': evidence.toJson(),
        'created_at': timestamp.toIso8601String(),
        'updated_at': timestamp.toIso8601String(),
      });
      final insertMap =
          ProductSubmissionApprovalRepository.buildProductInsertMap(
            decodedSubmission,
          );
      final approved = ScoringEvidenceSnapshot.tryFromJson(
        insertMap['scoring_evidence'],
      );
      expect(approved!.toJson(), evidence.toJson());
    });

    test('missing submission evidence remains backward compatible', () {
      final insertMap =
          ProductSubmissionApprovalRepository.buildProductInsertMap(
            submission(),
          );
      expect(insertMap.containsKey('scoring_evidence'), isFalse);
    });

    test('submission approval merges with existing product evidence', () {
      final existing = product(
        evidence: fullSnapshot(
          energyKj: numeric(
            170,
            provenance: EvidenceProvenance.databaseImport,
            verification: EvidenceVerification.unverified,
          ),
        ),
      );
      final reviewed =
          ProductSubmissionApprovalRepository.buildProductInsertMap(
            submission(evidence: fullSnapshot()),
          );
      final patch = ProductSubmissionApprovalRepository.buildProductEnrichPatch(
        existing,
        reviewed,
      );
      final merged = ScoringEvidenceSnapshot.tryFromJson(
        patch['scoring_evidence'],
      );
      expect(merged!.nutrition.energyKj.value, 180);
    });

    test('staging evidence survives row and approval mapping', () {
      final evidence = fullSnapshot();
      final stagingMap = candidate(evidence: evidence).toStagingInsertMap();
      final decodedCandidate = ProductCandidate.fromJson(stagingMap);
      final productMap = ProductStagingApprovalRepository.buildProductInsertMap(
        decodedCandidate,
        const StagingApprovalEdits(),
      );
      final approved = ScoringEvidenceSnapshot.tryFromJson(
        productMap['scoring_evidence'],
      );
      expect(approved!.toJson(), evidence.toJson());
    });

    test('missing staging evidence remains backward compatible', () {
      final stagingMap = candidate().toStagingInsertMap();
      final productMap = ProductStagingApprovalRepository.buildProductInsertMap(
        candidate(),
        const StagingApprovalEdits(),
      );
      expect(stagingMap.containsKey('scoring_evidence'), isFalse);
      expect(productMap.containsKey('scoring_evidence'), isFalse);
    });

    test('Product JSON receives optional persisted evidence', () {
      final evidence = fullSnapshot();
      final decoded = Product.fromJson({
        'id': 'product-id',
        'name': 'Test Product',
        'verification_status': 'verified',
        'scoring_evidence': evidence.toJson(),
        'created_at': timestamp.toIso8601String(),
        'updated_at': timestamp.toIso8601String(),
      });
      expect(decoded.scoringEvidence!.toJson(), evidence.toJson());
      expect(decoded.toJson()['scoring_evidence'], evidence.toJson());
    });
  });
}
