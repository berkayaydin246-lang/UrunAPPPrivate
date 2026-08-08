import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/core/theme/app_theme.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_readiness_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/etiketly_score_calculator.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/etiketly_score_readiness_evaluator.dart';
import 'package:food_analyzer_app/features/scoring/presentation/etiketly_score_presentation.dart';
import 'package:food_analyzer_app/features/scoring/widgets/etiketly_score_card.dart';

import 'support/etiketly_score_test_support.dart';

void main() {
  group('EtiketlyScoreCard public presentation', () {
    testWidgets('1. calculated card shows a rounded integer', (tester) async {
      await _pumpCard(tester, _calculatedState(72.2));

      expect(_scoreText(tester), '72');
      expect(find.text('/100'), findsOneWidget);
    });

    testWidgets('2. score 78.4 displays 78', (tester) async {
      await _pumpCard(tester, _calculatedState(78.4));

      expect(_scoreText(tester), '78');
    });

    testWidgets('3. score 78.5 follows Dart round and displays 79', (
      tester,
    ) async {
      await _pumpCard(tester, _calculatedState(78.5));

      expect(_scoreText(tester), '79');
    });

    testWidgets('4. score 80 uses Çok iyi', (tester) async {
      await _pumpCard(tester, _calculatedState(80));

      expect(find.text('Çok iyi içerik profili'), findsOneWidget);
    });

    testWidgets('5. score 79 uses İyi', (tester) async {
      await _pumpCard(tester, _calculatedState(79));

      expect(find.text('İyi içerik profili'), findsOneWidget);
    });

    testWidgets('6. score 60 uses İyi', (tester) async {
      await _pumpCard(tester, _calculatedState(60));

      expect(find.text('İyi içerik profili'), findsOneWidget);
    });

    testWidgets('7. score 59 uses Orta', (tester) async {
      await _pumpCard(tester, _calculatedState(59));

      expect(find.text('Orta içerik profili'), findsOneWidget);
    });

    testWidgets('8. score 40 uses Orta', (tester) async {
      await _pumpCard(tester, _calculatedState(40));

      expect(find.text('Orta içerik profili'), findsOneWidget);
    });

    testWidgets('9. score 39 uses Zayıf', (tester) async {
      await _pumpCard(tester, _calculatedState(39));

      expect(find.text('Zayıf içerik profili'), findsOneWidget);
    });

    testWidgets('10. score 20 uses Zayıf', (tester) async {
      await _pumpCard(tester, _calculatedState(20));

      expect(find.text('Zayıf içerik profili'), findsOneWidget);
    });

    testWidgets('11. score 19 uses Çok zayıf', (tester) async {
      await _pumpCard(tester, _calculatedState(19));

      expect(find.text('Çok zayıf içerik profili'), findsOneWidget);
    });

    testWidgets('12. calculated zero is shown as a real 0/100 score', (
      tester,
    ) async {
      await _pumpCard(tester, _calculatedState(0));

      expect(_scoreText(tester), '0');
      expect(
        find.byKey(const ValueKey('etiketly-score-unavailable')),
        findsNothing,
      );
    });

    testWidgets('13. calculated 100 is shown correctly', (tester) async {
      await _pumpCard(tester, _calculatedState(100));

      expect(_scoreText(tester), '100');
      expect(find.text('Çok iyi içerik profili'), findsOneWidget);
    });

    testWidgets('14. unavailable state contains no fake numeric score', (
      tester,
    ) async {
      await _pumpCard(tester, _unavailableState());

      expect(find.byKey(const ValueKey('etiketly-score-value')), findsNothing);
      expect(find.text('/100'), findsNothing);
      expect(find.text('Etiketly Puanı hesaplanamadı'), findsOneWidget);
    });

    testWidgets('15. loading state contains no fake numeric score', (
      tester,
    ) async {
      await _pumpCard(tester, const ProductEtiketlyScoreState.loading());

      expect(find.byKey(const ValueKey('etiketly-score-value')), findsNothing);
      expect(find.text('/100'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('16. technical blocker enum is not visible', (tester) async {
      await _pumpCard(tester, _unavailableState());

      expect(find.textContaining('unknownNutritionBasis'), findsNothing);
      expect(
        find.text('Besin değerlerinin 100 g / 100 ml temeli doğrulanmamış.'),
        findsOneWidget,
      );
    });

    testWidgets('17. raw exception is not visible in error state', (
      tester,
    ) async {
      await _pumpCard(tester, const ProductEtiketlyScoreState.error());

      expect(find.textContaining('DioException'), findsNothing);
      expect(find.text('Puan şu anda hesaplanamadı.'), findsOneWidget);
    });

    testWidgets('18. nutrition component is visible when calculated', (
      tester,
    ) async {
      await _pumpCard(tester, _calculatedState(78.4));

      expect(find.text('Beslenme kalitesi'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('etiketly-nutrition-component')),
        findsOneWidget,
      );
    });

    testWidgets('19. additive component is visible when calculated', (
      tester,
    ) async {
      await _pumpCard(tester, _calculatedState(78.4));

      expect(find.text('Katkı kalitesi'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('etiketly-additive-component')),
        findsOneWidget,
      );
    });

    testWidgets(
      '20. quality is communicated with text and semantics, not color alone',
      (tester) async {
        await _pumpCard(tester, _calculatedState(78.4));

        expect(find.text('İyi içerik profili'), findsOneWidget);
        final semantics = tester.getSemantics(
          find.byKey(const ValueKey('etiketly-score-calculated')),
        );
        expect(semantics.label, contains('Etiketly Puanı 78 üzerinden 100'));
        expect(semantics.label, contains('İçerik profili: İyi'));
      },
    );

    testWidgets('methodology sheet discloses weights and non-medical scope', (
      tester,
    ) async {
      await _pumpCard(tester, _calculatedState(78.4));

      await tester.tap(
        find.byKey(const ValueKey('etiketly-score-info-button')),
      );
      await tester.pumpAndSettle();

      expect(find.text('%80'), findsOneWidget);
      expect(find.text('%20'), findsOneWidget);
      expect(find.textContaining('tıbbi değerlendirme'), findsOneWidget);
    });

    testWidgets('card remains overflow-free on a small Android width', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 1200);
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });

      await _pumpCard(tester, _calculatedState(78.4));

      expect(tester.takeException(), isNull);
      expect(find.text('İyi içerik profili'), findsOneWidget);
    });

    testWidgets('card remains overflow-free with large text', (tester) async {
      await _pumpCard(
        tester,
        _calculatedState(78.4),
        textScaler: const TextScaler.linear(2),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Beslenme kalitesi'), findsOneWidget);
    });
  });
}

ProductEtiketlyScoreState _calculatedState(double exactScore) {
  final result = calculateSyntheticScore(
    nutritionQuality: exactScore,
    additiveQuality: exactScore,
  );
  return const EtiketlyScorePresentationMapper().fromResult(result);
}

ProductEtiketlyScoreState _unavailableState() {
  final additive = syntheticAdditiveQuality(100);
  final nutritionReadiness = ScoringReadinessResult(
    isScorable: false,
    resolvedCategory: ScoringCategory.generalFood,
    blockingReasons: const [ScoringReadinessBlocker.unknownNutritionBasis],
    missingRequirements: const [ScoringRequirement.nutritionBasis],
    evidenceQuality: ScoringEvidenceQuality.low,
  );
  final readiness = const EtiketlyScoreReadinessEvaluator().evaluate(
    nutritionReadiness: nutritionReadiness,
    ingredientEvidenceCompleteness: IngredientEvidenceCompleteness.complete,
    additiveQuality: additive,
  );
  final result = const EtiketlyScoreCalculator().calculate(
    additiveQuality: additive,
    readiness: readiness,
  );
  return const EtiketlyScorePresentationMapper().fromResult(result);
}

Future<void> _pumpCard(
  WidgetTester tester,
  ProductEtiketlyScoreState state, {
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme(useGoogleFonts: false),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: EtiketlyScoreCard(state: state),
        ),
      ),
    ),
  );
  await tester.pump();
}

String _scoreText(WidgetTester tester) {
  return tester
      .widget<Text>(find.byKey(const ValueKey('etiketly-score-value')))
      .data!;
}
