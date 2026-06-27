enum OcrEngineType {
  localMlKit,

  /// Production backend — Claude Vision (Anthropic).
  claudeVision,

  // Kept for backward compatibility with OcrBenchmarkPage.
  // Not used by the active production pipeline.
  googleVision,
  paddleOcr,
  tesseractTr,
}

extension OcrEngineTypeX on OcrEngineType {
  String get apiValue {
    switch (this) {
      case OcrEngineType.localMlKit:
        return 'local_mlkit';
      case OcrEngineType.claudeVision:
        return 'claude_vision';
      case OcrEngineType.googleVision:
        return 'google_vision';
      case OcrEngineType.paddleOcr:
        return 'paddle_ocr';
      case OcrEngineType.tesseractTr:
        return 'tesseract_tr';
    }
  }

  String get label {
    switch (this) {
      case OcrEngineType.localMlKit:
        return 'ML Kit (cihazda)';
      case OcrEngineType.claudeVision:
        return 'Claude Vision';
      case OcrEngineType.googleVision:
        return 'Google Vision';
      case OcrEngineType.paddleOcr:
        return 'PaddleOCR';
      case OcrEngineType.tesseractTr:
        return 'Tesseract TR';
    }
  }
}
