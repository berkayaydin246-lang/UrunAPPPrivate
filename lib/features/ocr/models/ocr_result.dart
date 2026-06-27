import 'package:image_picker/image_picker.dart';

import 'package:food_analyzer_app/features/ocr/models/ocr_engine_type.dart';
import 'package:food_analyzer_app/features/ocr/models/ocr_quality_assessment.dart';
import 'package:food_analyzer_app/features/ocr/models/structured_ingredient_extraction_result.dart';

/// Result of OCR text extraction from an image
class OcrTextResult {
  final OcrEngineType engineType;
  final String rawText;
  final String cleanedText;
  final double confidenceScore; // 0.0-1.0 confidence level
  final int processingTimeMs;
  final List<String> warnings;
  final String languageHint;

  OcrTextResult({
    OcrEngineType? engineType,
    String? rawText,
    String? cleanedText,
    @Deprecated('Use rawText') String? text,
    double? confidenceScore,
    @Deprecated('Use confidenceScore') int? confidence,
    this.processingTimeMs = 0,
    this.warnings = const <String>[],
    this.languageHint = 'tr',
  }) : engineType = engineType ?? OcrEngineType.localMlKit,
       rawText = rawText ?? text ?? '',
       cleanedText = cleanedText ?? rawText ?? text ?? '',
       confidenceScore =
           confidenceScore ?? (((confidence ?? 100).clamp(0, 100)) / 100.0);

  String get text => cleanedText;

  int get confidence => (confidenceScore * 100).round().clamp(0, 100);

  bool get hasWarnings => warnings.isNotEmpty;

  OcrTextResult copyWith({
    OcrEngineType? engineType,
    String? rawText,
    String? cleanedText,
    String? text,
    double? confidenceScore,
    int? confidence,
    int? processingTimeMs,
    List<String>? warnings,
    String? languageHint,
  }) {
    return OcrTextResult(
      engineType: engineType ?? this.engineType,
      rawText: rawText ?? text ?? this.rawText,
      cleanedText: cleanedText ?? text ?? this.cleanedText,
      confidenceScore:
          confidenceScore ??
          (confidence != null
              ? (confidence.clamp(0, 100) / 100.0)
              : this.confidenceScore),
      processingTimeMs: processingTimeMs ?? this.processingTimeMs,
      warnings: warnings ?? this.warnings,
      languageHint: languageHint ?? this.languageHint,
    );
  }

  @override
  String toString() =>
      'OcrTextResult(engine=$engineType, text_length=${cleanedText.length}, confidence=$confidence, processingTimeMs=$processingTimeMs)';
}

/// OCR processing state
class OcrState {
  final XFile? imageFile;
  final OcrTextResult? extractedText;
  final StructuredIngredientExtractionResult? structuredExtractionResult;
  final String? editableText;
  final bool isProcessing;
  final bool isUploading;
  final bool isRemoteProcessing;
  final String? error;
  final String? remoteError;
  final OcrQualityAssessment? qualityAssessment;

  OcrState({
    this.imageFile,
    this.extractedText,
    this.structuredExtractionResult,
    this.editableText,
    this.isProcessing = false,
    this.isUploading = false,
    this.isRemoteProcessing = false,
    this.error,
    this.remoteError,
    this.qualityAssessment,
  });

  OcrState copyWith({
    XFile? imageFile,
    OcrTextResult? extractedText,
    StructuredIngredientExtractionResult? structuredExtractionResult,
    String? editableText,
    bool? isProcessing,
    bool? isUploading,
    bool? isRemoteProcessing,
    String? error,
    String? remoteError,
    OcrQualityAssessment? qualityAssessment,
    bool clearError = false,
    bool clearRemoteError = false,
    bool clearQualityAssessment = false,
    bool clearStructuredExtractionResult = false,
  }) {
    return OcrState(
      imageFile: imageFile ?? this.imageFile,
      extractedText: extractedText ?? this.extractedText,
      structuredExtractionResult: clearStructuredExtractionResult
          ? null
          : (structuredExtractionResult ?? this.structuredExtractionResult),
      editableText: editableText ?? this.editableText,
      isProcessing: isProcessing ?? this.isProcessing,
      isUploading: isUploading ?? this.isUploading,
      isRemoteProcessing: isRemoteProcessing ?? this.isRemoteProcessing,
      error: clearError ? null : (error ?? this.error),
      remoteError: clearRemoteError ? null : (remoteError ?? this.remoteError),
      qualityAssessment: clearQualityAssessment
          ? null
          : (qualityAssessment ?? this.qualityAssessment),
    );
  }

  bool get hasImage => imageFile != null;
  bool get hasExtractedText =>
      extractedText != null && extractedText!.text.isNotEmpty;
  bool get hasStructuredExtractionResult => structuredExtractionResult != null;
  bool get hasError => error != null;
  bool get hasRemoteError => remoteError != null;

  bool get isBusy => isProcessing || isUploading || isRemoteProcessing;

  bool get isLowQualityText {
    return qualityAssessment?.isLowQuality ?? false;
  }

  bool get shouldOfferServerFallback =>
      qualityAssessment?.shouldOfferServerFallback ?? false;
}

extension StructuredResultToOcr on StructuredIngredientExtractionResult {
  OcrTextResult toOcrTextResult() {
    // Prefer cleanedText; fall back to ingredient names if text looks like JSON.
    // This guards against backend fallback responses leaking JSON to the UI.
    String displayText = cleanedText.isNotEmpty ? cleanedText : rawText;
    if (_isJsonLike(displayText)) {
      displayText = ingredients
          .map((i) => i.originalText.isNotEmpty ? i.originalText : i.name)
          .where((n) => n.trim().isNotEmpty)
          .join(', ');
    }
    return OcrTextResult(
      engineType: OcrEngineType.claudeVision,
      rawText: rawText,
      cleanedText: displayText,
      confidenceScore: qualityScore,
      warnings: warnings,
      languageHint: 'tr',
    );
  }

  static bool _isJsonLike(String text) {
    final t = text.trimLeft();
    return t.startsWith('{') || t.startsWith('[') || t.startsWith('`');
  }
}
