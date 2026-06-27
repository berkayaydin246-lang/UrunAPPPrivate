import 'package:flutter/material.dart';
import 'package:food_analyzer_app/features/analysis/models/ingredient_match.dart';
import 'package:food_analyzer_app/features/product/models/ingredient.dart';

/// Score labels used internally
enum AnalysisScoreLabel { iyiSecim, orta, dikkatliTuket, sikTuketme }

/// User-friendly mapping
String scoreLabelToTurkish(AnalysisScoreLabel label) {
  switch (label) {
    case AnalysisScoreLabel.iyiSecim:
      return 'İyi Seçim';
    case AnalysisScoreLabel.orta:
      return 'Orta';
    case AnalysisScoreLabel.dikkatliTuket:
      return 'Dikkatli Tüket';
    case AnalysisScoreLabel.sikTuketme:
      return 'Sık Tüketme';
  }
}

Color scoreLabelColor(AnalysisScoreLabel label) {
  switch (label) {
    case AnalysisScoreLabel.iyiSecim:
      return Colors.green;
    case AnalysisScoreLabel.orta:
      return Colors.orange;
    case AnalysisScoreLabel.dikkatliTuket:
      return Colors.deepOrange;
    case AnalysisScoreLabel.sikTuketme:
      return Colors.red;
  }
}

class ProductAnalysisResult {
  final AnalysisScoreLabel scoreLabel;
  final String summary; // short Turkish summary
  final String? warningText; // short warning when applicable
  final List<String> positivePoints; // short bullet points
  final List<String> negativePoints; // short bullet points
  final String consumptionAdvice; // short actionable advice
  final List<Ingredient> detectedRiskIngredients; // confirmed high/medium risk
  final List<Ingredient>
  recognizedIngredients; // all confirmed, including neutral
  final List<Ingredient>
  otherRecognizedIngredients; // confirmed but low/neutral
  final List<IngredientMatch> reviewRequiredMatches; // low confidence items
  final List<String> unknownIngredients; // unmatched tokens
  final Map<String, int> riskSignals; // counts per risk group
  final List<String> processingSignals; // ultra-processed signals
  final List<String> sugarSaltFatSignals; // sugar/salt/fat indicators
  final List<String> allergenTokens; // tokens split from allergen warnings
  final String? productContextNote; // optional context enrichment note
  final dynamic productContext;

  ProductAnalysisResult({
    required this.scoreLabel,
    required this.summary,
    this.warningText,
    this.positivePoints = const [],
    this.negativePoints = const [],
    this.consumptionAdvice = '',
    this.detectedRiskIngredients = const [],
    this.recognizedIngredients = const [],
    this.otherRecognizedIngredients = const [],
    this.reviewRequiredMatches = const [],
    this.unknownIngredients = const [],
    this.riskSignals = const {},
    this.processingSignals = const [],
    this.sugarSaltFatSignals = const [],
    this.allergenTokens = const [],
    this.productContextNote,
    this.productContext,
  });

  ProductAnalysisResult copyWith({
    AnalysisScoreLabel? scoreLabel,
    String? summary,
    String? warningText,
    List<String>? positivePoints,
    List<String>? negativePoints,
    String? consumptionAdvice,
    List<Ingredient>? detectedRiskIngredients,
    List<Ingredient>? recognizedIngredients,
    List<Ingredient>? otherRecognizedIngredients,
    List<IngredientMatch>? reviewRequiredMatches,
    List<String>? unknownIngredients,
    Map<String, int>? riskSignals,
    List<String>? processingSignals,
    List<String>? sugarSaltFatSignals,
    List<String>? allergenTokens,
    String? productContextNote,
    dynamic productContext,
  }) {
    return ProductAnalysisResult(
      scoreLabel: scoreLabel ?? this.scoreLabel,
      summary: summary ?? this.summary,
      warningText: warningText ?? this.warningText,
      positivePoints: positivePoints ?? this.positivePoints,
      negativePoints: negativePoints ?? this.negativePoints,
      consumptionAdvice: consumptionAdvice ?? this.consumptionAdvice,
      detectedRiskIngredients:
          detectedRiskIngredients ?? this.detectedRiskIngredients,
      recognizedIngredients:
          recognizedIngredients ?? this.recognizedIngredients,
      otherRecognizedIngredients:
          otherRecognizedIngredients ?? this.otherRecognizedIngredients,
      reviewRequiredMatches:
          reviewRequiredMatches ?? this.reviewRequiredMatches,
      unknownIngredients: unknownIngredients ?? this.unknownIngredients,
      riskSignals: riskSignals ?? this.riskSignals,
      processingSignals: processingSignals ?? this.processingSignals,
      sugarSaltFatSignals: sugarSaltFatSignals ?? this.sugarSaltFatSignals,
      allergenTokens: allergenTokens ?? this.allergenTokens,
      productContextNote: productContextNote ?? this.productContextNote,
      productContext: productContext ?? this.productContext,
    );
  }
}
