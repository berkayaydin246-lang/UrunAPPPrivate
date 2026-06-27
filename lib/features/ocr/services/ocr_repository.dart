import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

import 'package:food_analyzer_app/core/services/storage_service.dart';
import 'package:food_analyzer_app/features/ocr/models/ocr_engine_type.dart';
import 'package:food_analyzer_app/features/ocr/models/ocr_quality_assessment.dart';
import 'package:food_analyzer_app/features/ocr/models/ocr_result.dart';
import 'package:food_analyzer_app/features/ocr/services/ocr_providers.dart';
import 'package:food_analyzer_app/features/ocr/services/ocr_quality_evaluator.dart';
import 'package:food_analyzer_app/features/ocr/services/remote_ocr_client.dart';

class OcrRecognitionResult {
  final OcrTextResult result;
  final OcrQualityAssessment quality;

  const OcrRecognitionResult({required this.result, required this.quality});
}

/// Coordinates local OCR, server OCR fallback and quality checks.
///
/// IMPORTANT: OCR is the main bottleneck in this app. Accuracy here directly
/// affects ingredient matching and health analysis reliability.
///
/// CRITICAL SAFETY RULE: False OCR text should never directly create a
/// confident analysis result. Health and consumability decisions must be
/// based on rule-based ingredient matching, not raw OCR confidence scores.
///
/// User editable correction remains MANDATORY. Always allow users to review
/// and correct OCR output before proceeding to analysis.
class OcrRepository {
  final OcrTextProvider localProvider;
  final RemoteOcrClient remoteClient;
  final OcrQualityEvaluator qualityEvaluator;

  const OcrRepository({
    required this.localProvider,
    required this.remoteClient,
    required this.qualityEvaluator,
  });

  Future<OcrRecognitionResult> recognizeLocally(XFile imageFile) async {
    final result = await localProvider.recognize(imageFile);
    final quality = qualityEvaluator.assess(result);
    return OcrRecognitionResult(
      result: result.copyWith(
        confidenceScore: quality.score / 100.0,
        warnings: quality.issues,
      ),
      quality: quality,
    );
  }

  Future<OcrRecognitionResult> recognizeWithServer(
    XFile imageFile, {
    OcrEngineType engineType = OcrEngineType.paddleOcr,
  }) async {
    final bytes = Uint8List.fromList(await imageFile.readAsBytes());
    final tempPath = 'ocr-temp/${DateTime.now().millisecondsSinceEpoch}.jpg';
    String? uploadedUrl;

    try {
      uploadedUrl = await StorageService.uploadFileBytes(
        'ocr-temp',
        tempPath,
        bytes,
      );

      if (uploadedUrl == null || uploadedUrl.isEmpty) {
        throw StateError('Görsel sunucuya yüklenemedi.');
      }

      final result = await remoteClient.recognizeImage(
        imageUrl: uploadedUrl,
        engineType: engineType,
        languageHint: 'tr',
      );
      final quality = qualityEvaluator.assess(result);
      return OcrRecognitionResult(
        result: result.copyWith(
          confidenceScore: quality.score / 100.0,
          warnings: {...result.warnings, ...quality.issues}.toList(),
        ),
        quality: quality,
      );
    } finally {
      if (uploadedUrl != null) {
        await StorageService.deleteFile('ocr-temp', tempPath);
      }
    }
  }
}
