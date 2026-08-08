import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/submission/missing_product_submission_page.dart';
import 'package:food_analyzer_app/features/submission/repositories/product_submission_repository.dart';

void main() {
  group('MissingProductSubmissionPage', () {
    testWidgets('shows validation message when required photos are missing', (
      tester,
    ) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: MissingProductSubmissionPage(barcode: '8699118005551'),
          ),
        ),
      );

      final submitButton = find.text('İncelemeye Gönder');
      await tester.ensureVisible(submitButton);
      await tester.tap(submitButton);
      await tester.pump();

      expect(
        find.text(
          'Ürünü ekleyebilmemiz için ön yüz ve içindekiler fotoğrafları gereklidir.',
        ),
        findsAtLeastNWidgets(1),
      );
    });

    testWidgets('shows nutrition photo as optional', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: MissingProductSubmissionPage(barcode: '8699118005551'),
          ),
        ),
      );

      expect(find.text('Besin değerleri fotoğrafı'), findsOneWidget);
      expect(find.text('Besin tablosu fotoğrafı çek'), findsOneWidget);
      expect(find.text('İsteğe bağlı'), findsAtLeastNWidgets(1));
    });

    test('required input helper validates barcode and both photos', () {
      expect(
        hasRequiredSubmissionInputs(
          barcode: '8699118005551',
          frontImageBytes: Uint8List.fromList([1]),
          labelImageBytes: Uint8List.fromList([2]),
        ),
        isTrue,
      );

      expect(
        hasRequiredSubmissionInputs(
          barcode: '',
          frontImageBytes: Uint8List.fromList([1]),
          labelImageBytes: Uint8List.fromList([2]),
        ),
        isFalse,
      );

      expect(
        hasRequiredSubmissionInputs(
          barcode: '8699118005551',
          frontImageBytes: null,
          labelImageBytes: Uint8List.fromList([2]),
        ),
        isFalse,
      );

      expect(
        hasRequiredSubmissionInputs(
          barcode: '8699118005551',
          frontImageBytes: Uint8List.fromList([1]),
          labelImageBytes: null,
        ),
        isFalse,
      );
    });
  });
}
