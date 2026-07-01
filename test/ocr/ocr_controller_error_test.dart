import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/core/errors/user_message.dart';
import 'package:food_analyzer_app/features/ocr/controllers/ocr_controller.dart';
import 'package:food_analyzer_app/features/ocr/models/ocr_result.dart';
import 'package:food_analyzer_app/features/ocr/models/structured_ingredient_extraction_result.dart';
import 'package:food_analyzer_app/features/ocr/services/ocr_providers.dart';
import 'package:food_analyzer_app/features/ocr/services/ocr_quality_evaluator.dart';
import 'package:food_analyzer_app/features/ocr/services/ocr_repository.dart';
import 'package:food_analyzer_app/features/ocr/services/production_ocr_service.dart';
import 'package:food_analyzer_app/features/ocr/services/remote_ocr_client.dart';
import 'package:image_picker/image_picker.dart';

// ── Fakes ─────────────────────────────────────────────────────────────────────

class _FakeTextProvider implements OcrTextProvider {
  _FakeTextProvider(this.text);
  final String text;

  @override
  Future<OcrTextResult> recognize(XFile imageFile) async =>
      OcrTextResult(rawText: text, confidenceScore: text.isEmpty ? 0.0 : 0.9);
}

class _FakeProductionOcrService implements ProductionOcrService {
  _FakeProductionOcrService({this.result, this.error, this.delay});
  final StructuredIngredientExtractionResult? result;
  final Object? error;
  final Duration? delay;
  int calls = 0;

  @override
  Future<StructuredIngredientExtractionResult> extractIngredients(
    XFile imageFile, {
    String languageHint = 'tr',
  }) async {
    calls++;
    if (delay != null) await Future<void>.delayed(delay!);
    if (error != null) throw error!;
    return result!;
  }
}

class _TestableOcrNotifier extends OcrNotifier {
  _TestableOcrNotifier(super.repository, super.production, super.picker);
  void seed(OcrState s) => state = s;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

const _forbidden = <String>[
  'Bad state',
  'No element',
  'Exception',
  'StackTrace',
  'Instance of',
  'StateError',
  'null',
];

void _expectClean(String? message) {
  expect(message, isNotNull);
  expect(message!.trim(), isNotEmpty);
  for (final fragment in _forbidden) {
    expect(message, isNot(contains(fragment)), reason: 'leaked "$fragment"');
  }
}

XFile _fakeImage() => XFile('/tmp/test_ocr_nonexistent.jpg');

StructuredIngredientExtractionResult _emptyStructured() =>
    const StructuredIngredientExtractionResult(
      rawText: '',
      cleanedText: '',
      ingredients: [],
      eCodes: [],
      uncertainItems: [],
      warnings: [],
      qualityScore: 0.0,
    );

StructuredIngredientExtractionResult _goodStructured() =>
    const StructuredIngredientExtractionResult(
      rawText: 'su, şeker, tuz',
      cleanedText: 'su, şeker, tuz',
      ingredients: [
        StructuredIngredientItem(
          name: 'su',
          originalText: 'su',
          confidence: 0.95,
        ),
      ],
      eCodes: [],
      uncertainItems: [],
      warnings: [],
      qualityScore: 0.9,
    );

_TestableOcrNotifier _notifierWith(
  _FakeProductionOcrService prod, {
  String localText = 'su, şeker, tuz',
}) {
  final repo = OcrRepository(
    localProvider: _FakeTextProvider(localText),
    remoteClient: MockRemoteOcrClient(),
    qualityEvaluator: const OcrQualityEvaluator(),
  );
  return _TestableOcrNotifier(repo, prod, ImagePicker());
}

_TestableOcrNotifier _notifier({
  String localText = 'su, şeker, tuz',
  StructuredIngredientExtractionResult? prodResult,
  Object? prodError,
  Duration? prodDelay,
}) {
  return _notifierWith(
    _FakeProductionOcrService(
      result: prodResult,
      error: prodError,
      delay: prodDelay,
    ),
    localText: localText,
  );
}

/// The genuine `Bad state: No element` StateError from `.first` on empty list.
Object _realNoElementError() {
  try {
    (<int>[]).first;
  } catch (e) {
    return e;
  }
  return StateError('unreachable');
}

void main() {
  group('Local OCR (processCurrentImage)', () {
    test(
      'empty recognized text yields a friendly error, not empty screen',
      () async {
        final n = _notifier(localText: '');
        n.seed(OcrState(imageFile: _fakeImage()));

        await n.processCurrentImage();

        expect(n.state.error, UserMessage.ocrUnreadable);
        expect(n.state.isProcessing, isFalse);
        _expectClean(n.state.error);
        // Must not advance to a result with usable text.
        expect(n.state.hasExtractedText, isFalse);
      },
    );

    test('valid text produces an extracted-text result', () async {
      final n = _notifier(localText: 'su, şeker, tuz');
      n.seed(OcrState(imageFile: _fakeImage()));

      await n.processCurrentImage();

      expect(n.state.error, isNull);
      expect(n.state.isProcessing, isFalse);
      expect(n.state.hasExtractedText, isTrue);
    });
  });

  group('Production OCR (processCurrentImageWithProductionOcr)', () {
    test(
      'empty text and empty ingredients yield the no-label message',
      () async {
        final n = _notifier(prodResult: _emptyStructured());
        n.seed(OcrState(imageFile: _fakeImage()));

        await n.processCurrentImageWithProductionOcr();

        expect(n.state.remoteError, UserMessage.ocrNoLabel);
        expect(n.state.isUploading, isFalse);
        expect(n.state.isRemoteProcessing, isFalse);
        _expectClean(n.state.remoteError);
      },
    );

    test('real "Bad state: No element" never reaches the user', () async {
      final n = _notifier(prodError: _realNoElementError());
      n.seed(OcrState(imageFile: _fakeImage()));

      await n.processCurrentImageWithProductionOcr();

      _expectClean(n.state.remoteError);
      expect(n.state.remoteError, UserMessage.ocrUnreadable);
      expect(n.state.isBusy, isFalse);
    });

    test(
      'generic State("Bad state: No element") message is sanitized',
      () async {
        final n = _notifier(prodError: StateError('No element'));
        n.seed(OcrState(imageFile: _fakeImage()));

        await n.processCurrentImageWithProductionOcr();

        _expectClean(n.state.remoteError);
        expect(n.state.isBusy, isFalse);
      },
    );

    test(
      'malformed JSON (FormatException) is sanitized, loading stops',
      () async {
        final n = _notifier(prodError: const FormatException('bad json'));
        n.seed(OcrState(imageFile: _fakeImage()));

        await n.processCurrentImageWithProductionOcr();

        _expectClean(n.state.remoteError);
        expect(n.state.isBusy, isFalse);
      },
    );

    test('TimeoutException maps to the timeout message', () async {
      final n = _notifier(prodError: TimeoutException('slow'));
      n.seed(OcrState(imageFile: _fakeImage()));

      await n.processCurrentImageWithProductionOcr();

      expect(n.state.remoteError, UserMessage.timeout);
      expect(n.state.isBusy, isFalse);
    });

    test('our clean Turkish StateError message is preserved', () async {
      final n = _notifier(
        prodError: StateError('Gelişmiş OCR servisi şu anda yanıt veremiyor.'),
      );
      n.seed(OcrState(imageFile: _fakeImage()));

      await n.processCurrentImageWithProductionOcr();

      expect(
        n.state.remoteError,
        'Gelişmiş OCR servisi şu anda yanıt veremiyor.',
      );
      _expectClean(n.state.remoteError);
    });

    test(
      'successful result populates extracted text and clears loading',
      () async {
        final n = _notifier(prodResult: _goodStructured());
        n.seed(OcrState(imageFile: _fakeImage()));

        await n.processCurrentImageWithProductionOcr();

        expect(n.state.hasExtractedText, isTrue);
        expect(n.state.remoteError, isNull);
        expect(n.state.isBusy, isFalse);
      },
    );

    test(
      'duplicate submit while loading calls the backend only once',
      () async {
        final prod = _FakeProductionOcrService(
          result: _goodStructured(),
          delay: const Duration(milliseconds: 40),
        );
        final n = _notifierWith(prod);
        n.seed(OcrState(imageFile: _fakeImage()));

        final f1 = n.processCurrentImageWithProductionOcr();
        final f2 = n
            .processCurrentImageWithProductionOcr(); // must early-return
        await Future.wait([f1, f2]);

        expect(prod.calls, 1);
        expect(n.state.isBusy, isFalse);
      },
    );
  });
}
