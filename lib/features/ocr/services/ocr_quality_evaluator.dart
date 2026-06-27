import 'package:food_analyzer_app/features/ocr/models/ocr_quality_assessment.dart';
import 'package:food_analyzer_app/features/ocr/models/ocr_result.dart';

/// Evaluates OCR text quality using deterministic heuristics.
///
/// We prefer simple rules here so the app stays MVP-friendly and does not
/// depend on AI or backend availability for basic quality detection.
///
/// SAFETY NOTE: Low quality OCR may indicate unreliable text recognition,
/// which can lead to incorrect ingredient matching. When quality is low,
/// the app offers server-side OCR fallback to improve accuracy before
/// proceeding to health analysis.
class OcrQualityEvaluator {
  const OcrQualityEvaluator();

  OcrQualityAssessment assess(OcrTextResult result) {
    final text = result.cleanedText.trim();
    final issues = <String>[];

    final lineCount = text
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .length;
    final wordCount = text.isEmpty
        ? 0
        : text.split(RegExp(r'\s+')).where((w) => w.trim().isNotEmpty).length;
    final symbolRatio = _symbolRatio(text);
    final gibberishRatio = _gibberishRatio(text);
    final hasTurkishCharacters = _hasTurkishCharacters(text);
    final hasIngredientSeparators = _hasIngredientSeparators(text);
    final hasBrokenECode = _hasBrokenECode(result.rawText, text);

    if (result.confidence < 65) {
      issues.add('Güven düşük');
    }
    if (text.length < 24) {
      issues.add('Metin kısa');
    }
    if (lineCount < 2 && text.length < 80) {
      issues.add('Satır sayısı az');
    }
    if (wordCount < 4) {
      issues.add('Kelime sayısı az');
    }
    if (symbolRatio > 0.35) {
      issues.add('Sembol oranı yüksek');
    }
    if (gibberishRatio > 0.2) {
      issues.add('Anlamsız karakterler fazla');
    }
    if (text.length > 50 && !hasTurkishCharacters) {
      issues.add('Türkçe karakterler zayıf');
    }
    if (text.length > 60 && !hasIngredientSeparators) {
      issues.add('Ayırıcılar zayıf');
    }
    if (hasBrokenECode) {
      issues.add('E-kodları düzgün okunmadı');
    }

    var score = result.confidence;
    if (text.length < 24) score -= 20;
    if (lineCount < 2) score -= 10;
    if (wordCount < 4) score -= 10;
    if (symbolRatio > 0.35) score -= 20;
    if (gibberishRatio > 0.2) score -= 20;
    if (text.length > 50 && !hasTurkishCharacters) score -= 10;
    if (text.length > 60 && !hasIngredientSeparators) score -= 10;
    if (hasBrokenECode) score -= 10;

    score = score.clamp(0, 100).toInt();
    return OcrQualityAssessment(score: score, issues: issues);
  }

  double _symbolRatio(String text) {
    if (text.isEmpty) return 0;
    final disallowedCount = RegExp(
      r'[^A-Za-zÇĞİÖŞÜçğıöşü0-9\s,;:().%\-/\n]',
    ).allMatches(text).length;
    return disallowedCount / text.length;
  }

  double _gibberishRatio(String text) {
    if (text.isEmpty) return 0;
    final weirdRuns = RegExp(r'[^\s,;:().%\-/]{12,}').allMatches(text).length;
    return weirdRuns == 0 ? 0 : weirdRuns / text.length;
  }

  bool _hasTurkishCharacters(String text) {
    return RegExp(r'[çğıöşüÇĞİÖŞÜ]').hasMatch(text);
  }

  bool _hasIngredientSeparators(String text) {
    return text.contains(',') || text.contains(';') || text.contains('\n');
  }

  bool _hasBrokenECode(String rawText, String cleanedText) {
    final hadECode = RegExp(
      r'\be[\s\-–—:]*[0-9]{3}\b',
      caseSensitive: false,
    ).hasMatch(rawText);
    final hasNormalizedECode = RegExp(
      r'\be[0-9]{3}\b',
      caseSensitive: false,
    ).hasMatch(cleanedText);
    return hadECode && !hasNormalizedECode;
  }
}
