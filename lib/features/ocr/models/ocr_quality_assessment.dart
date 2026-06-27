/// Deterministic quality assessment for OCR output.
///
/// ML Kit remains the default on-device OCR because it is fast and works offline.
/// Server-side OCR is only a fallback for low-quality text, where a heavier
/// engine like PaddleOCR can improve the result.
class OcrQualityAssessment {
  final int score;
  final List<String> issues;

  const OcrQualityAssessment({required this.score, required this.issues});

  bool get isLowQuality => score < 60 || issues.isNotEmpty;

  bool get shouldOfferServerFallback => isLowQuality;
}
