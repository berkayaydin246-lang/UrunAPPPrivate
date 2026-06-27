import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:food_analyzer_app/features/ocr/models/ocr_engine_type.dart';
import 'package:food_analyzer_app/features/ocr/models/ocr_result.dart';

/// Service for OCR text extraction from images
class OcrService {
  static final OcrService _instance = OcrService._internal();

  factory OcrService() {
    return _instance;
  }

  OcrService._internal();

  // Initialize TextRecognizer for Latin script to better handle Turkish text.
  //
  // Rationale:
  // - Turkish uses the Latin script with specific characters (ç,ğ,ı,ö,ş,ü).
  // - ML Kit provides script-specific models which improve accuracy for
  //   languages that use the Latin alphabet. Explicitly selecting the Latin
  //   recognition model helps avoid fallback behaviors and improves quality.
  // - We keep ML Kit as the default on-device engine (fast, offline). A server
  //   fallback (PaddleOCR) was added separately for very noisy images.
  //
  // Note: This uses ML Kit v2 text recognition API available via
  // `google_mlkit_text_recognition`. If you upgrade the plugin, ensure the
  // constructor still accepts the `script` named parameter.
  final TextRecognizer _textRecognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );

  static final Map<RegExp, String> _commonFixes = {
    RegExp(r'\bsodym\b', caseSensitive: false): 'sodyum',
    RegExp(r'\bsodyrn\b', caseSensitive: false): 'sodyum',
    RegExp(r'\bpolifosft\b', caseSensitive: false): 'polifosfat',
    RegExp(r'\bascorbic\b', caseSensitive: false): 'askorbik',
    RegExp(r'\baskorbik\s+asit\b', caseSensitive: false): 'askorbik asit',
    RegExp(r'\bglucosc?\b', caseSensitive: false): 'glikoz',
  };

  String _cleanLine(String line) {
    var cleaned = line;

    // Normalize bullet separators but preserve ingredient line structure.
    cleaned = cleaned.replaceAll(RegExp(r'^[\s•·\-*–—]+'), '');

    // Fix common OCR mistakes.
    _commonFixes.forEach((pattern, replacement) {
      cleaned = cleaned.replaceAll(pattern, replacement);
    });

    // Normalize broken E-codes: e-250, E 250, e:250 -> e250
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'\be[\s\-–—:]*([0-9]{3})\b', caseSensitive: false),
      (match) => 'e${match[1]}',
    );

    // Keep ingredient separators but normalize spacing around them.
    cleaned = cleaned.replaceAll(RegExp(r'\s*[,;]\s*'), ', ');
    cleaned = cleaned.replaceAll(RegExp(r'\s*:\s*'), ': ');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');

    return cleaned.trim();
  }

  String _cleanRecognizedText(String text) {
    return text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .map(_cleanLine)
        .where((line) => line.isNotEmpty)
        .join('\n');
  }

  /// Extract text from a selected image file
  /// Returns OcrTextResult with extracted text
  Future<OcrTextResult> extractTextFromImage(XFile imageFile) async {
    try {
      final stopwatch = Stopwatch()..start();

      // Load image from file
      final inputImage = InputImage.fromFilePath(imageFile.path);

      // Perform text recognition
      final recognizedText = await _textRecognizer.processImage(inputImage);

      // Extract text from all blocks
      String extractedText = '';
      for (final textBlock in recognizedText.blocks) {
        for (final textLine in textBlock.lines) {
          extractedText += '${textLine.text}\n';
        }
      }

      // Clean up the text while preserving ingredient separators.
      extractedText = _cleanRecognizedText(extractedText);

      // Estimate confidence based on text richness.
      final lineCount = extractedText
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .length;
      final hasIngredientLikeSeparators =
          extractedText.contains(',') || extractedText.contains(';');
      int confidence = extractedText.isEmpty
          ? 0
          : (70 +
                    (lineCount > 2 ? 10 : 0) +
                    (hasIngredientLikeSeparators ? 8 : 0))
                .clamp(0, 100)
                .toInt();

      stopwatch.stop();

      return OcrTextResult(
        engineType: OcrEngineType.localMlKit,
        rawText: extractedText,
        cleanedText: extractedText,
        confidenceScore: confidence / 100.0,
        processingTimeMs: stopwatch.elapsedMilliseconds,
        warnings: const <String>[],
        languageHint: 'tr',
      );
    } catch (e) {
      throw Exception('ML Kit ile metin tanımlanamadı: $e');
    }
  }

  /// Clean up resources
  Future<void> dispose() async {
    await _textRecognizer.close();
  }
}
