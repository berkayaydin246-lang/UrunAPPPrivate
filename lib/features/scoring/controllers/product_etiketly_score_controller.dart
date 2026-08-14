import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:food_analyzer_app/features/analysis/models/canonical_additive_assessment.dart';
import 'package:food_analyzer_app/features/analysis/services/canonical_ingredient_risk_service.dart';
import 'package:food_analyzer_app/features/product/controllers/product_analysis_controller.dart';
import 'package:food_analyzer_app/features/product/controllers/product_detail_controller.dart';
import 'package:food_analyzer_app/features/scoring/application/product_etiketly_score_orchestrator.dart';
import 'package:food_analyzer_app/features/scoring/data/score_audit_snapshot_repository.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/etiketly_public_score_audit_gate.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/etiketly_score_audit_snapshot_builder.dart';
import 'package:food_analyzer_app/features/scoring/presentation/etiketly_score_presentation.dart';

final productEtiketlyScoreOrchestratorProvider = Provider(
  (_) => const ProductEtiketlyScoreOrchestrator(),
);

final scoreAuditSnapshotRepositoryProvider =
    Provider<ScoreAuditSnapshotRepository>(
      (_) => const SupabaseScoreAuditSnapshotRepository(),
    );

final etiketlyScoreAuditSnapshotBuilderProvider = Provider(
  (_) => const EtiketlyScoreAuditSnapshotBuilder(),
);

final etiketlyPublicScoreAuditGateProvider = Provider(
  (_) => const EtiketlyPublicScoreAuditGate(),
);

final productScoringAdditiveAssessmentProvider =
    FutureProvider.family<CanonicalAdditiveAssessment?, String>((
      ref,
      productId,
    ) async {
      final matchingData = await ref.watch(
        productIngredientMatchingProvider(productId).future,
      );
      if (matchingData == null || matchingData.matchingResult.matches.isEmpty) {
        return null;
      }
      return const CanonicalIngredientRiskService().assessForScoring(
        matchingData.matchingResult,
        scoringCategory: matchingData.scoringCategory,
      );
    });

final productEtiketlyScoreProvider =
    FutureProvider.family<ProductEtiketlyScoreState, String>((
      ref,
      productId,
    ) async {
      final detailFuture = ref.watch(
        productDetailByIdProvider(productId).future,
      );
      final scoringAssessmentFuture = ref.watch(
        productScoringAdditiveAssessmentProvider(productId).future,
      );
      final orchestrator = ref.watch(productEtiketlyScoreOrchestratorProvider);
      final auditRepository = ref.watch(scoreAuditSnapshotRepositoryProvider);
      final snapshotBuilder = ref.watch(
        etiketlyScoreAuditSnapshotBuilderProvider,
      );
      final auditGate = ref.watch(etiketlyPublicScoreAuditGateProvider);
      const presentationMapper = EtiketlyScorePresentationMapper();

      try {
        final detail = await detailFuture;
        final scoringAssessment = await scoringAssessmentFuture;
        final product = detail.product!;
        final evaluation = orchestrator.calculate(
          product: product,
          canonicalAssessment: scoringAssessment,
        );
        if (evaluation == null) {
          return presentationMapper.missingCanonicalAssessment();
        }
        if (!evaluation.isCalculated) {
          return presentationMapper.fromResult(evaluation.result);
        }

        final current = snapshotBuilder.build(
          product: product,
          evaluation: evaluation,
        );
        try {
          final trusted = await auditRepository.fetchMatching(current);
          final decision = auditGate.evaluate(
            current: current,
            trusted: trusted,
          );
          if (decision.mayDisplayNumericScore) {
            return presentationMapper.fromResult(evaluation.result);
          }
          if (kDebugMode) {
            debugPrint(
              '[EtiketlyScoreAudit] product=$productId '
              'status=${decision.status.name}',
            );
          }
          return presentationMapper.auditSnapshotRequired();
        } catch (error, stackTrace) {
          if (kDebugMode) {
            debugPrint(
              '[EtiketlyScoreAudit] product=$productId read_error=$error',
            );
            debugPrintStack(stackTrace: stackTrace);
          }
          return presentationMapper.auditSnapshotRequired();
        }
      } catch (error, stackTrace) {
        if (kDebugMode) {
          debugPrint('[EtiketlyScore] product=$productId error=$error');
          debugPrintStack(stackTrace: stackTrace);
        }
        return const ProductEtiketlyScoreState.error();
      }
    });
