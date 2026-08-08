import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:food_analyzer_app/features/product/controllers/product_analysis_controller.dart';
import 'package:food_analyzer_app/features/product/controllers/product_detail_controller.dart';
import 'package:food_analyzer_app/features/scoring/application/product_etiketly_score_orchestrator.dart';
import 'package:food_analyzer_app/features/scoring/presentation/etiketly_score_presentation.dart';

final productEtiketlyScoreOrchestratorProvider = Provider(
  (_) => const ProductEtiketlyScoreOrchestrator(),
);

final productEtiketlyScoreProvider =
    FutureProvider.family<ProductEtiketlyScoreState, String>((
      ref,
      productId,
    ) async {
      final detailFuture = ref.watch(
        productDetailByIdProvider(productId).future,
      );
      final analysisFuture = ref.watch(
        productAnalysisProvider(productId).future,
      );
      final orchestrator = ref.watch(productEtiketlyScoreOrchestratorProvider);

      try {
        final detail = await detailFuture;
        final analysis = await analysisFuture;
        return orchestrator.evaluate(
          product: detail.product!,
          canonicalAssessment: analysis?.additiveAssessment,
        );
      } catch (error, stackTrace) {
        if (kDebugMode) {
          debugPrint('[EtiketlyScore] product=$productId error=$error');
          debugPrintStack(stackTrace: stackTrace);
        }
        return const ProductEtiketlyScoreState.error();
      }
    });
