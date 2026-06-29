import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/ocr/controllers/ocr_controller.dart';
import 'package:food_analyzer_app/features/ocr/models/ocr_quality_assessment.dart';
import 'package:food_analyzer_app/features/ocr/models/ocr_result.dart';
import 'package:food_analyzer_app/features/ocr/models/structured_ingredient_extraction_result.dart';
import 'package:food_analyzer_app/features/ocr/ocr_page.dart';
import 'package:food_analyzer_app/features/ocr/services/ocr_providers.dart';
import 'package:food_analyzer_app/features/ocr/services/ocr_quality_evaluator.dart';
import 'package:food_analyzer_app/features/ocr/services/ocr_repository.dart';
import 'package:food_analyzer_app/features/ocr/services/production_ocr_service.dart';
import 'package:food_analyzer_app/features/ocr/services/remote_ocr_client.dart';
import 'package:image_picker/image_picker.dart';

// ── Stubs ─────────────────────────────────────────────────────────────────────

class _NoopTextProvider implements OcrTextProvider {
  @override
  Future<OcrTextResult> recognize(XFile imageFile) async =>
      OcrTextResult(rawText: '');
}

class _NoopProductionOcrService implements ProductionOcrService {
  @override
  Future<StructuredIngredientExtractionResult> extractIngredients(
    XFile imageFile, {
    String languageHint = 'tr',
  }) async => throw UnimplementedError();
}

class _FixedOcrNotifier extends OcrNotifier {
  _FixedOcrNotifier(OcrState fixed)
    : super(
        OcrRepository(
          localProvider: _NoopTextProvider(),
          remoteClient: MockRemoteOcrClient(),
          qualityEvaluator: const OcrQualityEvaluator(),
        ),
        _NoopProductionOcrService(),
        ImagePicker(),
      ) {
    state = fixed;
  }

  @override
  Future<void> processCurrentImage() async {}
  @override
  Future<void> processCurrentImageWithProductionOcr() async {}
  @override
  Future<void> captureImageFromCamera() async {}
  @override
  Future<void> pickImageFromGallery() async {}
}

// ── State helpers ─────────────────────────────────────────────────────────────

// XFile with a synthetic path — hasImage becomes true without needing a real
// file to exist, because Image.file loading failure does not fail widget tests.
XFile get _fakeImageFile => XFile('/tmp/test_ocr_nonexistent.jpg');

OcrTextResult _text([String raw = 'su, şeker, tuz']) =>
    OcrTextResult(rawText: raw, confidenceScore: 0.92);

OcrState _successState({String? raw, bool withStructured = false}) {
  final rawText = raw ?? 'su, şeker, tuz';
  return OcrState(
    imageFile: _fakeImageFile,
    extractedText: _text(rawText),
    editableText: rawText,
    structuredExtractionResult: withStructured
        ? StructuredIngredientExtractionResult(
            rawText: rawText,
            cleanedText: rawText,
            ingredients: const [],
            eCodes: const [],
            uncertainItems: const [],
            warnings: const [],
            qualityScore: 0.9,
          )
        : null,
  );
}

// Advanced OCR success state with low-quality assessment — proves warnings
// and duplicate buttons are suppressed after advanced OCR succeeds.
OcrState _advancedSuccessState({String? raw}) {
  final rawText = raw ?? 'su, şeker, tuz, E471';
  return OcrState(
    imageFile: _fakeImageFile,
    extractedText: _text(rawText),
    editableText: rawText,
    structuredExtractionResult: StructuredIngredientExtractionResult(
      rawText: rawText,
      cleanedText: rawText,
      ingredients: const [],
      eCodes: const [],
      uncertainItems: const [],
      warnings: const ['Güven düşük'],
      qualityScore: 0.5,
    ),
    qualityAssessment: const OcrQualityAssessment(
      score: 45,
      issues: ['Güven düşük'],
    ),
  );
}

// ── Pump helpers ──────────────────────────────────────────────────────────────

Future<void> pumpOcrScreen(
  WidgetTester tester,
  OcrState state, {
  bool settle = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [ocrProvider.overrideWith((ref) => _FixedOcrNotifier(state))],
      child: const MaterialApp(home: OcrScreen()),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    // pumpAndSettle times out on infinite animations (e.g. CircularProgressIndicator).
    // Two pump calls suffice to build the widget tree without waiting for settle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── Teknik JSON visibility ─────────────────────────────────────────────────

  group('"Teknik JSON" visibility', () {
    testWidgets('not shown for quick OCR result (no structured extraction)', (
      tester,
    ) async {
      await pumpOcrScreen(tester, _successState());
      expect(find.text('Teknik JSON'), findsNothing);
    });

    testWidgets('not shown on intro/capture screen (no OCR result yet)', (
      tester,
    ) async {
      await pumpOcrScreen(tester, OcrState());
      expect(find.text('Teknik JSON'), findsNothing);
    });

    testWidgets('not shown on error screen', (tester) async {
      await pumpOcrScreen(tester, OcrState(error: 'Metin tanımlanamadı.'));
      expect(find.text('Teknik JSON'), findsNothing);
    });
  });

  // ── CTA label ─────────────────────────────────────────────────────────────

  group('Continue CTA after OCR success', () {
    testWidgets('shows "İçeriği Analiz Et" after quick OCR', (tester) async {
      await pumpOcrScreen(tester, _successState());
      expect(find.text('İçeriği Analiz Et'), findsOneWidget);
    });

    testWidgets('shows "İçeriği Analiz Et" after advanced OCR', (tester) async {
      await pumpOcrScreen(
        tester,
        _successState(raw: 'su, şeker, nişasta', withStructured: true),
      );
      expect(find.text('İçeriği Analiz Et'), findsOneWidget);
    });

    testWidgets('"Devam Et" label no longer exists (replaced)', (tester) async {
      await pumpOcrScreen(tester, _successState());
      expect(find.text('Devam Et'), findsNothing);
    });

    testWidgets('"İçeriği Analiz Et" is an ElevatedButton', (tester) async {
      await pumpOcrScreen(tester, _successState());
      final btn = find.ancestor(
        of: find.text('İçeriği Analiz Et'),
        matching: find.byType(ElevatedButton),
      );
      expect(btn, findsOneWidget);
    });

    testWidgets('edit text button present alongside CTA', (tester) async {
      await pumpOcrScreen(tester, _successState());
      expect(find.text('Metni elle düzenle'), findsOneWidget);
      expect(find.text('İçeriği Analiz Et'), findsOneWidget);
    });
  });

  // ── Error screen ───────────────────────────────────────────────────────────

  group('Error screen', () {
    testWidgets('shows clean Turkish auth error without "StateError:" prefix', (
      tester,
    ) async {
      const msg =
          'Gelişmiş OCR yetkilendirmesi başarısız. Lütfen OCR yapılandırmasını kontrol et.';
      await pumpOcrScreen(tester, OcrState(error: msg));
      expect(find.textContaining('StateError:'), findsNothing);
      expect(find.textContaining('yetkilendirmesi başarısız'), findsOneWidget);
    });

    testWidgets(
      'does not surface DioException, SocketException, or Mozilla text',
      (tester) async {
        const msg = 'Gelişmiş OCR servisine ulaşılamadı.';
        await pumpOcrScreen(tester, OcrState(error: msg));
        expect(find.textContaining('DioException'), findsNothing);
        expect(find.textContaining('SocketException'), findsNothing);
        expect(find.textContaining('Mozilla'), findsNothing);
      },
    );

    testWidgets('shows retry button on error screen', (tester) async {
      await pumpOcrScreen(
        tester,
        OcrState(error: 'Gelişmiş OCR zaman aşımına uğradı.'),
      );
      expect(find.text('Tekrar Dene'), findsOneWidget);
    });
  });

  // ── Loading screen ─────────────────────────────────────────────────────────

  group('Loading screen', () {
    testWidgets('shows spinner while uploading/remote-processing', (
      tester,
    ) async {
      await pumpOcrScreen(
        tester,
        OcrState(isUploading: true, isRemoteProcessing: true),
        settle: false, // CircularProgressIndicator never settles
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.textContaining('Gelişmiş OCR'), findsOneWidget);
      expect(find.text('Teknik JSON'), findsNothing);
    });
  });

  // ── Advanced OCR result: clean MVP screen ────────────────────────────────────

  group('After successful advanced OCR', () {
    testWidgets(
      'Teknik JSON not visible by default (no SHOW_OCR_DEBUG_JSON flag)',
      (tester) async {
        await pumpOcrScreen(tester, _advancedSuccessState());
        expect(find.text('Teknik JSON'), findsNothing);
      },
    );

    testWidgets(
      'Gelişmiş OCR ile Tara button gone after advanced OCR succeeds',
      (tester) async {
        await pumpOcrScreen(tester, _advancedSuccessState());
        expect(find.text('Gelişmiş OCR ile Tara'), findsNothing);
      },
    );

    testWidgets('İçeriği Analiz Et is visible after advanced OCR succeeds', (
      tester,
    ) async {
      await pumpOcrScreen(tester, _advancedSuccessState());
      expect(find.text('İçeriği Analiz Et'), findsOneWidget);
    });

    testWidgets(
      'stale fast-OCR warning Türkçe metin daha iyi okunabilir not shown',
      (tester) async {
        await pumpOcrScreen(tester, _advancedSuccessState());
        expect(
          find.textContaining('Türkçe metin daha iyi okunabilir'),
          findsNothing,
        );
      },
    );

    testWidgets(
      'no suggestion to try advanced OCR when advanced OCR already ran',
      (tester) async {
        await pumpOcrScreen(tester, _advancedSuccessState());
        expect(
          find.textContaining('gelişmiş OCR deneyebilirsin'),
          findsNothing,
        );
      },
    );

    testWidgets('raw JSON keys not visible in user UI', (tester) async {
      await pumpOcrScreen(tester, _advancedSuccessState());
      expect(find.textContaining('"rawText"'), findsNothing);
      expect(find.textContaining('"cleanedText"'), findsNothing);
      expect(find.textContaining('"ingredients"'), findsNothing);
    });
  });

  // ── OCR quality evaluator (unit tests) ────────────────────────────────────

  group('OcrQualityEvaluator', () {
    test('marks short text as low quality', () {
      const evaluator = OcrQualityEvaluator();
      final result = OcrTextResult(rawText: 'su', confidenceScore: 0.9);
      expect(evaluator.assess(result).isLowQuality, isTrue);
    });

    test('marks rich ingredient text as acceptable quality', () {
      const evaluator = OcrQualityEvaluator();
      final result = OcrTextResult(
        rawText: 'su, şeker, buğday unu, tuz, mısır nişastası, E471, E330',
        confidenceScore: 0.92,
      );
      expect(evaluator.assess(result).score, greaterThan(50));
    });
  });
}
