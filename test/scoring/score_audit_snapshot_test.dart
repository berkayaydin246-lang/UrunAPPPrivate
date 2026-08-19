import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/analysis/services/canonical_ingredient_risk_service.dart';
import 'package:food_analyzer_app/features/product/models/ingredient.dart';
import 'package:food_analyzer_app/features/scoring/application/product_etiketly_score_orchestrator.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/composition_percentage_evidence.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_score_audit_snapshot.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/etiketly_public_score_audit_gate.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/etiketly_score_audit_snapshot_builder.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/etiketly_score_audit_validator.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/score_audit_fingerprint.dart';
import 'package:food_analyzer_app/features/scoring/presentation/etiketly_score_presentation.dart';

import 'scoring_test_fixtures.dart';
import 'support/score_audit_test_support.dart';

void main() {
  const validator = EtiketlyScoreAuditValidator();
  const gate = EtiketlyPublicScoreAuditGate();

  EtiketlyScoreAuditSnapshot ordinarySnapshot({
    String name = 'Audit Product',
    String ingredientsText = 'Su',
  }) {
    return buildAuditSnapshot(
      product: auditProductFromInput(
        completeInput(),
        name: name,
        ingredientsText: ingredientsText,
      ),
      assessment: auditOrdinaryAssessment(),
    );
  }

  EtiketlyScoreAuditSnapshot riskSnapshot(String risk) {
    return buildAuditSnapshot(
      product: auditProductFromInput(
        completeInput(),
        ingredientsText: 'Audit Custom Additive',
      ),
      assessment: auditRiskAssessment(risk),
    );
  }

  group('serialization and validation', () {
    test('1. complete snapshot round-trips', () {
      final original = riskSnapshot('high');
      final decoded = EtiketlyScoreAuditSnapshot.tryFromJson(
        jsonDecode(jsonEncode(original.toJson())),
      );

      expect(decoded, isNotNull);
      expect(decoded!.toJson(), original.toJson());
      expect(validator.validate(decoded).isValid, isTrue);
    });

    test('2. missing optional metadata is safe', () {
      final original = buildAuditSnapshot(
        product: auditProductFromInput(completeInput(), barcode: null),
        assessment: auditOrdinaryAssessment(),
      );
      final decoded = EtiketlyScoreAuditSnapshot.tryFromJson(original.toJson());

      expect(decoded, isNotNull);
      expect(decoded!.barcode, isNull);
      expect(decoded.capturedAt, isNull);
      expect(validator.validate(decoded).isValid, isTrue);
    });

    test('3. unsupported schema is handled conservatively', () {
      final json = ordinarySnapshot().toJson()..['schema_version'] = 2;
      expect(
        () => EtiketlyScoreAuditSnapshot.tryFromJson(json),
        returnsNormally,
      );
      expect(EtiketlyScoreAuditSnapshot.tryFromJson(json), isNull);
    });

    test('4. unknown future enum does not crash and is invalid', () {
      final json = riskSnapshot('high').toJson();
      final additives = json['canonical_additives']! as List;
      (additives.single as Map<String, Object?>)['match_authority'] =
          'future_authority';
      final decoded = EtiketlyScoreAuditSnapshot.tryFromJson(json);

      expect(decoded, isNotNull);
      expect(
        validator.validate(decoded!).issues,
        contains(ScoreAuditValidationIssue.invalidCanonicalAdditive),
      );

      final futureInput = _mutateAndRehash(ordinarySnapshot(), (json) {
        final input = json['resolved_input']! as Map<String, Object?>;
        input['nutrition_basis'] = 'future_basis';
      });
      expect(
        validator.validate(futureInput).issues,
        contains(ScoreAuditValidationIssue.invalidResolvedInput),
      );
    });

    test('5. NaN and infinity are rejected', () {
      final nan = ordinarySnapshot().toJson()..['final_score'] = double.nan;
      final infinity = ordinarySnapshot().toJson()
        ..['nutrition_contribution'] = double.infinity;
      expect(EtiketlyScoreAuditSnapshot.tryFromJson(nan), isNull);
      expect(EtiketlyScoreAuditSnapshot.tryFromJson(infinity), isNull);
    });

    test('6. score outside 0..100 is invalid', () {
      final json = ordinarySnapshot().toJson()..['final_score'] = 101.0;
      final decoded = EtiketlyScoreAuditSnapshot.tryFromJson(json)!;
      expect(
        validator.validate(decoded).issues,
        contains(ScoreAuditValidationIssue.valueOutOfRange),
      );
    });

    test('7. snapshot collections are immutable', () {
      final snapshot = riskSnapshot('high');
      expect(
        () =>
            snapshot.canonicalAdditives.add(snapshot.canonicalAdditives.first),
        throwsUnsupportedError,
      );
      expect(
        () => snapshot.resolvedInput.nutrition['energy_kj'] =
            snapshot.resolvedInput.nutrition['salt']!,
        throwsUnsupportedError,
      );
    });
  });

  group('canonical fingerprint', () {
    test('8. same score-affecting input has the same fingerprint', () {
      expect(
        ordinarySnapshot().inputFingerprint,
        ordinarySnapshot().inputFingerprint,
      );
    });

    test('9. UI-only product metadata does not alter fingerprint', () {
      final first = ordinarySnapshot(name: 'First UI Name');
      final second = ordinarySnapshot(name: 'Changed UI Name');
      expect(first.inputFingerprint, second.inputFingerprint);
    });

    test('10. nutrition change produces a different fingerprint', () {
      final first = buildAuditSnapshot(
        product: auditProductFromInput(completeInput()),
        assessment: auditOrdinaryAssessment(),
      );
      final second = buildAuditSnapshot(
        product: auditProductFromInput(
          completeInput(nutrition: completeNutrition(sugars: verifiedValue(9))),
        ),
        assessment: auditOrdinaryAssessment(),
      );
      expect(first.inputFingerprint, isNot(second.inputFingerprint));
    });

    test('11. nutrition basis change produces a different fingerprint', () {
      final first = ordinarySnapshot();
      final changed = _mutateAndRehash(first, (json) {
        final input = json['resolved_input']! as Map<String, Object?>;
        input['nutrition_basis'] = 'per100ml';
      });
      expect(first.inputFingerprint, isNot(changed.inputFingerprint));
    });

    test('12. FVL change produces a different fingerprint', () {
      final first = buildAuditSnapshot(
        product: auditProductFromInput(completeInput()),
        assessment: auditOrdinaryAssessment(),
      );
      final second = buildAuditSnapshot(
        product: auditProductFromInput(
          completeInput(
            fvlEvidence: const CompositionPercentageEvidence.known(
              40,
              provenance: EvidenceProvenance.adminVerified,
              verification: EvidenceVerification.verified,
            ),
          ),
        ),
        assessment: auditOrdinaryAssessment(),
      );
      expect(first.inputFingerprint, isNot(second.inputFingerprint));
    });

    test('13. ingredient text or canonical assessment change changes hash', () {
      final first = ordinarySnapshot(ingredientsText: 'Su');
      final textChanged = ordinarySnapshot(ingredientsText: 'Su, su');
      final canonicalChanged = riskSnapshot('high');
      expect(first.inputFingerprint, isNot(textChanged.inputFingerprint));
      expect(first.inputFingerprint, isNot(canonicalChanged.inputFingerprint));
    });

    test('14. additive risk-at-time change changes fingerprint', () {
      expect(
        riskSnapshot('high').inputFingerprint,
        isNot(riskSnapshot('medium').inputFingerprint),
      );
    });

    test('15. score version is namespaced and fingerprinted', () {
      final current = ordinarySnapshot();
      final changed = _mutateAndRehash(current, (json) {
        json['score_version'] = 'etiketly_score_v1';
      });
      expect(current.inputFingerprint, isNot(changed.inputFingerprint));
      expect(
        validator.validate(changed).issues,
        contains(ScoreAuditValidationIssue.unsupportedVersion),
      );
    });

    test('16. map key order cannot alter fingerprint', () {
      final first = <String, Object?>{
        'z': 1.0,
        'nested': {'b': true, 'a': 'value'},
        'a': [3, 2, 1],
      };
      final second = <String, Object?>{
        'a': [3, 2, 1],
        'nested': {'a': 'value', 'b': true},
        'z': 1.0,
      };
      expect(
        ScoreAuditFingerprint.create(first),
        ScoreAuditFingerprint.create(second),
      );
    });
  });

  group('historical risk independence', () {
    test('17. historical high risk remains high after live risk changes', () {
      final historical = riskSnapshot('high');
      final current = riskSnapshot('medium');
      expect(
        historical.canonicalAdditives.single.riskLevelAtCalculationTime,
        'high',
      );
      expect(
        current.canonicalAdditives.single.riskLevelAtCalculationTime,
        'medium',
      );
    });

    test('18. current recalculation can use the new catalogue risk', () {
      final historical = riskSnapshot('high');
      final current = riskSnapshot('medium');
      expect(
        current.additiveResult.additiveQuality,
        isNot(historical.additiveResult.additiveQuality),
      );
      expect(current.finalScore, isNot(historical.finalScore));
    });

    test('19. historical validator never replaces stored risk', () {
      final historical = riskSnapshot('high');
      expect(validator.validate(historical).isValid, isTrue);
      expect(
        historical.canonicalAdditives.single.riskLevelAtCalculationTime,
        'high',
      );
    });

    test(
      '20. new score input creates a new immutable snapshot fingerprint',
      () {
        final historical = riskSnapshot('high');
        final current = riskSnapshot('medium');
        expect(current.inputFingerprint, isNot(historical.inputFingerprint));
        expect(
          historical.canonicalAdditives.single.riskLevelAtCalculationTime,
          'high',
        );
      },
    );
  });

  group('public gate and score integrity', () {
    test('21. matching trusted audit permits numeric publication', () {
      final current = ordinarySnapshot();
      expect(
        gate.evaluate(current: current, trusted: current).status,
        PublicScoreAuditStatus.matching,
      );
      expect(
        gate
            .evaluate(current: current, trusted: current)
            .mayDisplayNumericScore,
        isTrue,
      );
    });

    test('22. missing trusted audit blocks numeric publication', () {
      final current = ordinarySnapshot();
      expect(
        gate.evaluate(current: current, trusted: null).status,
        PublicScoreAuditStatus.missing,
      );
    });

    test('23. stale fingerprint blocks numeric publication', () {
      final current = ordinarySnapshot(ingredientsText: 'Su');
      final stale = ordinarySnapshot(ingredientsText: 'Su, su');
      expect(
        gate.evaluate(current: current, trusted: stale).status,
        PublicScoreAuditStatus.stale,
      );
    });

    test('24. invalid audit blocks numeric publication', () {
      final current = ordinarySnapshot();
      final invalidJson = current.toJson()..['final_score'] = 99.0;
      final invalid = EtiketlyScoreAuditSnapshot.tryFromJson(invalidJson)!;
      expect(
        gate.evaluate(current: current, trusted: invalid).status,
        PublicScoreAuditStatus.invalid,
      );
    });

    group('basis remediation Section N: public score safety', () {
      // Models a snapshot whose basis provenance is exactly [provenance]
      // (including null, for a pre-remediation legacy row) as a HISTORICAL
      // audit row — i.e. via [buildHistoricalAuditSnapshotWithBasisProvenance],
      // never via plain [buildAuditSnapshot] directly on an untrusted-basis
      // product. Pre-APPLY trust correction: since
      // ScoringEvidenceSnapshot.toScoringInput now downgrades an
      // untrusted-provenance basis to NutritionBasis.unknown before
      // readiness is ever evaluated, [buildAuditSnapshot] itself can no
      // longer produce ANY calculated evaluation for such a product — but
      // this frozen public gate must still correctly judge a genuinely
      // historical (immutable, never-deleted, pre-correction) row, which
      // is exactly what this helper constructs: self-consistently
      // fingerprinted, never JSON-surgeried.
      EtiketlyScoreAuditSnapshot snapshotWithBasisProvenance(
        EvidenceProvenance? provenance,
      ) {
        return buildHistoricalAuditSnapshotWithBasisProvenance(provenance);
      }

      test(
        'a legacy snapshot with no basis provenance recorded at all cannot '
        'pass the public gate merely because its fingerprint matches — '
        'category-derived legacy basis is never newly trusted',
        () {
          final legacy = snapshotWithBasisProvenance(null);

          expect(
            const EtiketlyScoreAuditValidator().validate(legacy).isValid,
            isTrue,
            reason: 'this snapshot is genuinely self-consistent — only the '
                'basis-trust check should block it, nothing else',
          );
          final decision = gate.evaluate(current: legacy, trusted: legacy);

          expect(decision.status, PublicScoreAuditStatus.basisUnverified);
          expect(decision.mayDisplayNumericScore, isFalse);
        },
      );

      test(
        'databaseImport basis provenance — the exact legacy-invented '
        'signature — is never trusted, even with a perfectly matching '
        'fingerprint',
        () {
          final legacyInvented = snapshotWithBasisProvenance(
            EvidenceProvenance.databaseImport,
          );

          final decision = gate.evaluate(
            current: legacyInvented,
            trusted: legacyInvented,
          );

          expect(decision.status, PublicScoreAuditStatus.basisUnverified);
        },
      );

      test(
        'declaredLabel (source-proven) basis provenance passes normally',
        () {
          final proven = snapshotWithBasisProvenance(
            EvidenceProvenance.declaredLabel,
          );

          final decision = gate.evaluate(current: proven, trusted: proven);

          expect(decision.status, PublicScoreAuditStatus.matching);
          expect(decision.mayDisplayNumericScore, isTrue);
        },
      );

      test('adminVerified basis provenance passes normally', () {
        final adminProven = snapshotWithBasisProvenance(
          EvidenceProvenance.adminVerified,
        );

        final decision = gate.evaluate(
          current: adminProven,
          trusted: adminProven,
        );

        expect(decision.status, PublicScoreAuditStatus.matching);
      });

      test(
        'only ONE side (current) having untrusted basis provenance is '
        'still enough to block — both sides must be trusted',
        () {
          final untrustedCurrent = snapshotWithBasisProvenance(
            EvidenceProvenance.databaseImport,
          );
          final trustedStored = snapshotWithBasisProvenance(
            EvidenceProvenance.declaredLabel,
          );

          final decision = gate.evaluate(
            current: untrustedCurrent,
            trusted: trustedStored,
          );

          expect(decision.status, PublicScoreAuditStatus.basisUnverified);
        },
      );

      test(
        'a second, identical revalidated-basis evaluation is idempotent — '
        'still matching, never flips to stale or basisUnverified',
        () {
          final proven = snapshotWithBasisProvenance(
            EvidenceProvenance.declaredLabel,
          );

          final first = gate.evaluate(current: proven, trusted: proven);
          final second = gate.evaluate(current: proven, trusted: proven);

          expect(first.status, PublicScoreAuditStatus.matching);
          expect(second.status, PublicScoreAuditStatus.matching);
        },
      );

      group(
        'wouldBeCurrentIgnoringBasisTrust: the basis-revalidation '
        'candidate-selection circular-dependency fix',
        () {
          // (A) missing provenance entirely (pre-remediation legacy row):
          // otherwise a perfectly matching, structurally-valid audit — the
          // gate itself still reports basisUnverified (never bypassed) —
          // but this diagnostic helper reports it WOULD be current if
          // basis were trusted.
          test(
            'A: missing basis provenance, otherwise matching -> gate says '
            'basisUnverified, but wouldBeCurrentIgnoringBasisTrust is true',
            () {
              final legacy = snapshotWithBasisProvenance(null);

              expect(
                gate.evaluate(current: legacy, trusted: legacy).status,
                PublicScoreAuditStatus.basisUnverified,
              );
              expect(
                gate.wouldBeCurrentIgnoringBasisTrust(
                  current: legacy,
                  trusted: legacy,
                ),
                isTrue,
              );
            },
          );

          // (B) databaseImport provenance (the exact legacy-invented
          // signature): same shape as (A).
          test(
            'B: databaseImport basis provenance, otherwise matching -> gate '
            'says basisUnverified, but wouldBeCurrentIgnoringBasisTrust is '
            'true',
            () {
              final legacyInvented = snapshotWithBasisProvenance(
                EvidenceProvenance.databaseImport,
              );

              expect(
                gate
                    .evaluate(
                      current: legacyInvented,
                      trusted: legacyInvented,
                    )
                    .status,
                PublicScoreAuditStatus.basisUnverified,
              );
              expect(
                gate.wouldBeCurrentIgnoringBasisTrust(
                  current: legacyInvented,
                  trusted: legacyInvented,
                ),
                isTrue,
              );
            },
          );

          // (C) declaredLabel (already independently trusted): the gate
          // itself already permits display, so the diagnostic distinction
          // this helper exists for is moot — but it still reports true,
          // since the audit genuinely IS current either way.
          test(
            'C: declaredLabel basis provenance -> already gate-trusted, '
            'wouldBeCurrentIgnoringBasisTrust is also true',
            () {
              final proven = snapshotWithBasisProvenance(
                EvidenceProvenance.declaredLabel,
              );

              expect(
                gate.evaluate(current: proven, trusted: proven).status,
                PublicScoreAuditStatus.matching,
              );
              expect(
                gate.wouldBeCurrentIgnoringBasisTrust(
                  current: proven,
                  trusted: proven,
                ),
                isTrue,
              );
            },
          );

          // (D) adminVerified: same shape as (C).
          test(
            'D: adminVerified basis provenance -> already gate-trusted, '
            'wouldBeCurrentIgnoringBasisTrust is also true',
            () {
              final adminProven = snapshotWithBasisProvenance(
                EvidenceProvenance.adminVerified,
              );

              expect(
                gate
                    .evaluate(current: adminProven, trusted: adminProven)
                    .status,
                PublicScoreAuditStatus.matching,
              );
              expect(
                gate.wouldBeCurrentIgnoringBasisTrust(
                  current: adminProven,
                  trusted: adminProven,
                ),
                isTrue,
              );
            },
          );

          // (E) stale for an UNRELATED reason (ingredients changed, hence
          // a different fingerprint) on top of missing basis provenance:
          // must not be reported as "would be current" — the underlying
          // audit genuinely disagrees, basis aside.
          test(
            'E: stale fingerprint for an unrelated reason PLUS missing '
            'basis provenance -> wouldBeCurrentIgnoringBasisTrust is false, '
            'never falsely promoted to "otherwise current except basis"',
            () {
              final currentLegacy = snapshotWithBasisProvenance(null);
              final staleTrustedLegacy = buildAuditSnapshot(
                product: auditProductFromInput(
                  completeInput(),
                  ingredientsText: 'Su, su',
                ),
                assessment: auditOrdinaryAssessment(),
              );

              expect(
                gate
                    .evaluate(
                      current: currentLegacy,
                      trusted: staleTrustedLegacy,
                    )
                    .status,
                PublicScoreAuditStatus.basisUnverified,
                reason: 'basis-trust is checked before the fingerprint '
                    'comparison, so the gate itself still reports '
                    'basisUnverified here — but that must not be conflated '
                    'with "otherwise current"',
              );
              expect(
                gate.wouldBeCurrentIgnoringBasisTrust(
                  current: currentLegacy,
                  trusted: staleTrustedLegacy,
                ),
                isFalse,
              );
            },
          );

          // (F) no persisted trusted snapshot at all.
          test(
            'F: no persisted trusted snapshot -> wouldBeCurrentIgnoringBasisTrust '
            'is false',
            () {
              final legacy = snapshotWithBasisProvenance(null);

              expect(
                gate.wouldBeCurrentIgnoringBasisTrust(
                  current: legacy,
                  trusted: null,
                ),
                isFalse,
              );
            },
          );
        },
      );
    });

    test('25. legacy product remains an ordinary unavailable state', () {
      final state = const ProductEtiketlyScoreOrchestrator().evaluate(
        product: auditProductFromInput(completeInput()),
        canonicalAssessment: null,
      );
      expect(state.isCalculated, isFalse);
      expect(state.displayScore, isNull);
    });

    test('26. real calculated 0 with valid audit remains publishable', () {
      final input = completeInput(
        nutrition: completeNutrition(
          energyKj: verifiedValue(10000),
          totalFat: verifiedValue(100),
          saturatedFat: verifiedValue(100),
          sugars: verifiedValue(100),
          salt: verifiedValue(100),
          protein: verifiedValue(0),
          fiber: verifiedValue(0),
        ),
      );
      final ingredients = <Ingredient>[
        for (final risk in ['high', 'medium', 'low'])
          for (var index = 0; index < 40; index += 1)
            Ingredient(
              id: 'zero-$risk-$index',
              name: 'Zero $risk additive $index',
              normalizedName: 'zero $risk additive $index',
              additiveGroup: 'preservative',
              riskLevel: risk,
              createdAt: DateTime.utc(2026),
              updatedAt: DateTime.utc(2026),
            ),
      ];
      final assessment = const CanonicalIngredientRiskService()
          .assessIngredients(ingredients);
      final product = auditProductFromInput(
        input,
        ingredientsText: 'Synthetic audited additives',
      );
      final evaluation = const ProductEtiketlyScoreOrchestrator().calculate(
        product: product,
        canonicalAssessment: assessment,
      )!;
      final snapshot = const EtiketlyScoreAuditSnapshotBuilder().build(
        product: product,
        evaluation: evaluation,
      );
      final state = const EtiketlyScorePresentationMapper().fromResult(
        evaluation.result,
      );

      expect(snapshot.finalScore, 0);
      expect(validator.validate(snapshot).isValid, isTrue);
      expect(
        gate
            .evaluate(current: snapshot, trusted: snapshot)
            .mayDisplayNumericScore,
        isTrue,
      );
      expect(state.displayScore, 0);
    });

    test('27. missing audit never degrades into a numeric zero', () {
      final current = ordinarySnapshot();
      final decision = gate.evaluate(current: current, trusted: null);
      final unavailable = const EtiketlyScorePresentationMapper()
          .auditSnapshotRequired();
      expect(decision.mayDisplayNumericScore, isFalse);
      expect(unavailable.displayScore, isNull);
      expect(unavailable.isCalculated, isFalse);
    });

    test('33. stored 80/20 result reconciles', () {
      final result = validator.validate(ordinarySnapshot());
      expect(result.isValid, isTrue);
    });

    test('34. altered stored final score invalidates snapshot', () {
      final json = ordinarySnapshot().toJson()..['final_score'] = 42.0;
      final result = validator.validate(
        EtiketlyScoreAuditSnapshot.tryFromJson(json)!,
      );
      expect(
        result.issues,
        contains(ScoreAuditValidationIssue.finalScoreMismatch),
      );
    });

    test('35. all component versions are retained separately', () {
      final snapshot = ordinarySnapshot();
      expect(snapshot.scoreVersion, 'etiketly_score_v2');
      expect(
        snapshot.nutritionMethodologyVersion,
        'updated_nutrition_profile_2023_v1',
      );
      expect(
        snapshot.nutritionTransformVersion,
        'nutrition_quality_transform_v3',
      );
      expect(
        snapshot.additiveTransformVersion,
        'additive_quality_transform_v1',
      );
    });

    test('36. legal and UI metadata cannot alter score or fingerprint', () {
      final first = buildAuditSnapshot(
        product: auditProductFromInput(
          completeInput(),
          name: 'Old UI',
          brand: 'Old Brand',
        ),
        assessment: auditOrdinaryAssessment(),
      );
      final second = buildAuditSnapshot(
        product: auditProductFromInput(
          completeInput(),
          name: 'New UI',
          brand: 'New Brand',
          imageUrl: 'https://example.test/image.png',
        ),
        assessment: auditOrdinaryAssessment(),
      );
      expect(first.finalScore, second.finalScore);
      expect(first.inputFingerprint, second.inputFingerprint);
    });

    test('37. AI output is absent and irrelevant to audit input', () {
      final regular = buildAuditSnapshot(
        product: auditProductFromInput(completeInput()),
        assessment: auditOrdinaryAssessment(),
      );
      final metadataChanged = buildAuditSnapshot(
        product: auditProductFromInput(
          completeInput(),
          source: 'ai_generated_ui_copy',
        ),
        assessment: auditOrdinaryAssessment(),
      );
      expect(regular.finalScore, metadataChanged.finalScore);
      expect(regular.inputFingerprint, metadataChanged.inputFingerprint);
      expect(regular.fingerprintPayload().keys, isNot(contains('ai_output')));
    });

    test('38. community votes are absent and irrelevant to audit input', () {
      final snapshot = ordinarySnapshot();
      final encoded = jsonEncode(snapshot.fingerprintPayload()).toLowerCase();
      expect(encoded, isNot(contains('vote')));
      expect(encoded, isNot(contains('community')));
    });
  });
}

EtiketlyScoreAuditSnapshot _mutateAndRehash(
  EtiketlyScoreAuditSnapshot source,
  void Function(Map<String, Object?> json) mutate,
) {
  final json = (jsonDecode(jsonEncode(source.toJson())) as Map)
      .map<String, Object?>((key, value) => MapEntry(key.toString(), value));
  mutate(json);
  final parsed = EtiketlyScoreAuditSnapshot.tryFromJson(json)!;
  return parsed.withInputFingerprint(
    ScoreAuditFingerprint.create(parsed.fingerprintPayload()),
  );
}
