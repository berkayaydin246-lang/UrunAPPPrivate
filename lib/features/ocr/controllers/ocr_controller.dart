import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:food_analyzer_app/features/ocr/models/ocr_result.dart';
import 'package:food_analyzer_app/features/ocr/services/ocr_providers.dart';
import 'package:food_analyzer_app/features/ocr/services/ocr_quality_evaluator.dart';
import 'package:food_analyzer_app/features/ocr/services/ocr_repository.dart';
import 'package:food_analyzer_app/features/ocr/services/production_ocr_service.dart';
import 'package:food_analyzer_app/features/ocr/models/ocr_quality_assessment.dart';
import 'package:food_analyzer_app/features/ocr/models/structured_ingredient_extraction_result.dart';
import 'package:food_analyzer_app/features/ocr/services/ocr_service.dart';
import 'package:food_analyzer_app/features/ocr/services/remote_ocr_client.dart';

/// Notifier for managing OCR processing state.
class OcrNotifier extends StateNotifier<OcrState> {
  final OcrRepository _repository;
  final ProductionOcrService _productionOcrService;
  final ImagePicker _imagePicker;

  OcrNotifier(this._repository, this._productionOcrService, this._imagePicker)
    : super(OcrState());

  /// Pick an image from gallery.
  Future<void> pickImageFromGallery() async {
    try {
      final pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );

      if (pickedFile == null) {
        return;
      }

      state = OcrState(imageFile: pickedFile);
    } catch (e) {
      state = state.copyWith(error: 'Galeri açılırken hata oluştu: $e');
    }
  }

  /// Capture an image from camera.
  Future<void> captureImageFromCamera() async {
    try {
      final pickedFile = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );

      if (pickedFile == null) {
        return;
      }

      state = OcrState(imageFile: pickedFile);
    } catch (e) {
      state = state.copyWith(error: 'Kamera açılırken hata oluştu: $e');
    }
  }

  /// Start the default OCR flow using local ML Kit.
  Future<void> processCurrentImage() async {
    final imageFile = state.imageFile;
    if (imageFile == null) return;

    state = state.copyWith(
      isProcessing: true,
      clearError: true,
      clearRemoteError: true,
      clearQualityAssessment: true,
      clearStructuredExtractionResult: true,
    );

    try {
      final result = await _repository.recognizeLocally(imageFile);
      state = state.copyWith(
        extractedText: result.result,
        editableText: result.result.text,
        isProcessing: false,
        qualityAssessment: result.quality,
      );
    } catch (e) {
      state = state.copyWith(
        error: 'Metin tanımlanamadı: $e',
        isProcessing: false,
      );
    }
  }

  /// Run the production OCR backend for structured ingredient extraction.
  Future<void> processCurrentImageWithProductionOcr() async {
    final imageFile = state.imageFile;
    if (imageFile == null) return;

    state = state.copyWith(
      isUploading: true,
      isRemoteProcessing: true,
      clearRemoteError: true,
      clearStructuredExtractionResult: true,
    );

    try {
      final structured = await _productionOcrService.extractIngredients(
        imageFile,
      );
      final result = structured.toOcrTextResult();
      state = state.copyWith(
        extractedText: result,
        structuredExtractionResult: structured,
        editableText: _pickProductionDisplayText(structured),
        isUploading: false,
        isRemoteProcessing: false,
        qualityAssessment: OcrQualityAssessment(
          score: (structured.qualityScore * 100).round().clamp(0, 100),
          issues: structured.warnings,
        ),
      );
    } catch (e) {
      state = state.copyWith(
        remoteError: e.toString().replaceFirst('StateError: ', ''),
        isUploading: false,
        isRemoteProcessing: false,
      );
    }
  }

  /// Backward-compatible alias for older callers.
  Future<void> processCurrentImageWithServer() {
    return processCurrentImageWithProductionOcr();
  }

  /// Update the editable text when user makes corrections.
  void updateEditableText(String text) {
    state = state.copyWith(editableText: text);
  }

  /// Reset state to start over.
  void reset() {
    state = OcrState();
  }

  /// Clear error message.
  void clearError() {
    state = state.copyWith(error: null, remoteError: null);
  }

  /// Retry OCR on the current image.
  Future<void> retryOcr() async {
    if (state.imageFile == null) {
      return;
    }
    await processCurrentImage();
  }

  /// Clear the currently selected image and extracted text.
  void retakeImage() {
    state = OcrState();
  }
}

/// Selects the best plain-text display string from a structured OCR result.
///
/// Priority: confirmed high-confidence ingredient text → all ingredient names
/// → cleaned text (if not JSON-like). Never returns JSON or fenced content.
String? _pickProductionDisplayText(
  StructuredIngredientExtractionResult result,
) {
  if (result.confirmedIngredientsText.isNotEmpty) {
    return result.confirmedIngredientsText;
  }
  final allText = result.ingredients
      .map((i) => i.originalText.isNotEmpty ? i.originalText : i.name)
      .where((n) => n.trim().isNotEmpty)
      .join(', ');
  if (allText.isNotEmpty) return allText;
  final ct = result.cleanedText.trim();
  if (ct.isNotEmpty &&
      !ct.startsWith('{') &&
      !ct.startsWith('[') &&
      !ct.startsWith('`')) {
    return ct;
  }
  return null;
}

/// Provide ImagePicker as a singleton.
final imagePickerProvider = Provider((_) => ImagePicker());

/// Default local OCR service.
final ocrServiceProvider = Provider((_) => OcrService());

final productionOcrServiceProvider = Provider<ProductionOcrService>(
  (_) => HttpProductionOcrService.fromEnv(),
);

/// Repository that coordinates local OCR and the PaddleOCR fallback.
final ocrRepositoryProvider = Provider<OcrRepository>((ref) {
  final localProvider = LocalMlKitOcrProvider(ref.watch(ocrServiceProvider));
  final remoteClient = HttpRemoteOcrClient.fromEnv();

  // Keep the repository modular so the local OCR remains the default and the
  // server-side OCR can be swapped out later without touching the UI.
  return OcrRepository(
    localProvider: localProvider,
    remoteClient: remoteClient,
    qualityEvaluator: const OcrQualityEvaluator(),
  );
});

/// Provide OCR notifier.
final ocrProvider = StateNotifierProvider<OcrNotifier, OcrState>(
  (ref) => OcrNotifier(
    ref.watch(ocrRepositoryProvider),
    ref.watch(productionOcrServiceProvider),
    ref.watch(imagePickerProvider),
  ),
);
