import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:food_analyzer_app/core/errors/user_message.dart';
import 'package:food_analyzer_app/features/analysis/engines/analysis_engine.dart';
import 'package:food_analyzer_app/features/analysis/models/ingredient_match.dart';
import 'package:food_analyzer_app/features/analysis/models/analysis_route_args.dart';
import 'package:food_analyzer_app/features/analysis/models/product_analysis_result.dart';
import 'package:food_analyzer_app/features/analysis/services/ingredient_canonicalizer.dart';
import 'package:food_analyzer_app/features/analysis/services/ingredient_matcher_service.dart';
import 'package:food_analyzer_app/features/analysis/controllers/ingredient_matcher_controller.dart';
import 'package:food_analyzer_app/features/product/repositories/product_repository.dart';

class AnalysisState {
  final String? inputText;
  final String? category;
  final List<String>? structuredIngredients;
  final IngredientMatchingResult? matchingResult;
  final ProductAnalysisResult? result;
  final bool isProcessing;
  final String? error;

  AnalysisState({
    this.inputText,
    this.category,
    this.structuredIngredients,
    this.matchingResult,
    this.result,
    this.isProcessing = false,
    this.error,
  });

  AnalysisState copyWith({
    String? inputText,
    String? category,
    List<String>? structuredIngredients,
    IngredientMatchingResult? matchingResult,
    ProductAnalysisResult? result,
    bool? isProcessing,
    String? error,
  }) {
    return AnalysisState(
      inputText: inputText ?? this.inputText,
      category: category ?? this.category,
      structuredIngredients:
          structuredIngredients ?? this.structuredIngredients,
      matchingResult: matchingResult ?? this.matchingResult,
      result: result ?? this.result,
      isProcessing: isProcessing ?? this.isProcessing,
      error: error ?? this.error,
    );
  }

  bool get hasMatchingResult => matchingResult != null;
}

class AnalysisNotifier extends StateNotifier<AnalysisState> {
  final AnalysisEngine _engine;
  final IngredientMatcherService _matcher;
  final ProductRepository _repository;

  AnalysisNotifier(this._engine, this._matcher, this._repository)
    : super(AnalysisState());

  Future<void> analyzeFromOcr(
    String ocrText, {
    String? category,
    List<String>? structuredIngredients,
  }) async {
    if (ocrText.trim().isEmpty) {
      state = state.copyWith(
        error: 'İçindekiler metni boş olamaz. Lütfen metni kontrol et.',
        isProcessing: false,
      );
      return;
    }

    state = state.copyWith(isProcessing: true, result: null, error: null);
    try {
      final allIngredients = await _repository.getAllIngredients();
      final allergenTokens = IngredientCanonicalizer.extractAllergenTokens(
        ocrText,
      );
      final matchingResult =
          (structuredIngredients != null && structuredIngredients.isNotEmpty)
          ? await _matcher.matchIngredientTokens(
              structuredIngredients,
              allIngredients,
            )
          : await _matcher.matchIngredients(ocrText, allIngredients);
      final analysis = _engine
          .analyze(matchingResult, category: category)
          .copyWith(allergenTokens: allergenTokens);
      state = state.copyWith(result: analysis, isProcessing: false);
      state = state.copyWith(
        inputText: ocrText,
        category: category,
        structuredIngredients: structuredIngredients,
        matchingResult: matchingResult,
        result: analysis,
        isProcessing: false,
      );
    } catch (e) {
      state = state.copyWith(
        error: UserMessage.forAnalysis(e),
        isProcessing: false,
      );
    }
  }

  /// Approve or reject a low-confidence match, then re-run analysis.
  void updateLowConfidenceDecision(String originalToken, bool approved) {
    final current = state.matchingResult;
    if (current == null) return;
    final updated = current.updateDecision(originalToken, approved);

    state = state.copyWith(matchingResult: updated, error: null);

    final input = state.inputText;
    if (input == null || input.trim().isEmpty) return;

    final analysis = _engine.analyze(updated, category: state.category);
    state = state.copyWith(result: analysis, matchingResult: updated);
  }

  void reset() {
    state = AnalysisState();
  }
}

final analysisEngineProvider = Provider((_) => const AnalysisEngine());

final analysisNotifierProvider =
    StateNotifierProvider<AnalysisNotifier, AnalysisState>((ref) {
      final engine = ref.watch(analysisEngineProvider);
      final matcher = ref.watch(ingredientMatcherServiceProvider);
      final repo = ref.watch(productRepositoryProvider);
      return AnalysisNotifier(engine, matcher, repo);
    });

final analysisRouteArgsProvider = Provider<AnalysisRouteArgs?>((ref) => null);
