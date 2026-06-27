class AnalysisRouteArgs {
  final String ocrText;
  final String? category;
  final List<String>? structuredIngredients;

  const AnalysisRouteArgs({
    required this.ocrText,
    this.category,
    this.structuredIngredients,
  });
}
