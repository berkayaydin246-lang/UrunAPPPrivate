import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/core/errors/user_message.dart';

// Forbidden raw developer fragments that must never reach users.
const _forbidden = <String>[
  'Bad state',
  'No element',
  'Exception',
  'StackTrace',
  'Instance of',
  'StateError',
  'FormatException',
  'SocketException',
  'TimeoutException',
  'DioException',
  'developer.mozilla.org',
  'status code',
  'RequestOptions',
  'null',
];

void _expectClean(String message) {
  expect(message.trim(), isNotEmpty);
  for (final fragment in _forbidden) {
    expect(
      message,
      isNot(contains(fragment)),
      reason: 'Message leaked forbidden fragment "$fragment": $message',
    );
  }
}

/// The genuine `Bad state: No element` thrown by `.first` on an empty list.
Object _realNoElementError() {
  try {
    // ignore: unnecessary_cast
    (<int>[]).first;
  } catch (e) {
    return e;
  }
  return StateError('unreachable');
}

void main() {
  group('UserMessage.forOcr', () {
    test('real "Bad state: No element" becomes the friendly OCR message', () {
      final msg = UserMessage.forOcr(_realNoElementError());
      expect(msg, UserMessage.ocrUnreadable);
      _expectClean(msg);
    });

    test('StateError("No element") is sanitized', () {
      _expectClean(UserMessage.forOcr(StateError('No element')));
    });

    test('generic Exception never leaks its raw text', () {
      _expectClean(UserMessage.forOcr(Exception('boom internal detail')));
      expect(
        UserMessage.forOcr(Exception('boom internal detail')),
        UserMessage.ocrUnreadable,
      );
    });

    test('TypeError / cast errors fall back cleanly', () {
      Object err = StateError('unreachable');
      try {
        // Force a runtime type error.
        // ignore: avoid_dynamic_calls
        (Object() as dynamic).nonExistentMethod();
      } catch (e) {
        err = e;
      }
      _expectClean(UserMessage.forOcr(err));
    });

    test('our own clean Turkish StateError message is preserved', () {
      final msg = UserMessage.forOcr(
        StateError('Gelişmiş OCR servisine ulaşılamadı.'),
      );
      expect(msg, 'Gelişmiş OCR servisine ulaşılamadı.');
      _expectClean(msg);
    });

    test('TimeoutException maps to the timeout message', () {
      final msg = UserMessage.forOcr(TimeoutException('x'));
      expect(msg, UserMessage.timeout);
      _expectClean(msg);
    });

    test('SocketException maps to the network message', () {
      final msg = UserMessage.forOcr(const SocketException('failed'));
      expect(msg, UserMessage.network);
      _expectClean(msg);
    });

    test('Dio connection error maps to the network message', () {
      final msg = UserMessage.forOcr(
        DioException(
          requestOptions: RequestOptions(path: '/x'),
          type: DioExceptionType.connectionError,
        ),
      );
      expect(msg, UserMessage.network);
      _expectClean(msg);
    });

    test('Dio receive timeout maps to the timeout message', () {
      final msg = UserMessage.forOcr(
        DioException(
          requestOptions: RequestOptions(path: '/x'),
          type: DioExceptionType.receiveTimeout,
        ),
      );
      expect(msg, UserMessage.timeout);
      _expectClean(msg);
    });

    test('FormatException (malformed JSON) is sanitized', () {
      _expectClean(
        UserMessage.forOcr(const FormatException('Unexpected char')),
      );
    });
  });

  group('UserMessage.forAnalysis', () {
    test('unexpected error falls back to the analysis message', () {
      final msg = UserMessage.forAnalysis(_realNoElementError());
      expect(msg, UserMessage.analysisFailed);
      _expectClean(msg);
    });

    test('generic Exception never leaks', () {
      _expectClean(UserMessage.forAnalysis(Exception('db failure xyz')));
    });
  });

  group('UserMessage.forSubmissionOcr', () {
    test('HTTP 401 becomes the clean Turkish auth message', () {
      final options = RequestOptions(path: '/ocr/ingredients');
      final msg = UserMessage.forSubmissionOcr(
        DioException(
          requestOptions: options,
          response: Response(requestOptions: options, statusCode: 401),
          type: DioExceptionType.badResponse,
        ),
      );

      expect(msg, UserMessage.submissionOcrAuth);
      _expectClean(msg);
    });

    test('stored raw Dio 401 text becomes the clean Turkish auth message', () {
      final msg = UserMessage.forSubmissionOcr(
        'DioException [bad response]: status code of 401. '
        'See https://developer.mozilla.org and RequestOptions.',
      );

      expect(msg, UserMessage.submissionOcrAuth);
      _expectClean(msg);
    });

    test('stored unreadable-image message maps to manual review guidance', () {
      final msg = UserMessage.forSubmissionOcr(
        'Görsel işlenemedi. Lütfen daha net bir fotoğraf çekin.',
      );

      expect(msg, UserMessage.submissionOcrUnreadable);
      _expectClean(msg);
    });

    test('stored timeout text maps to the submission OCR network message', () {
      final msg = UserMessage.forSubmissionOcr('connection timeout after 60s');

      expect(msg, UserMessage.submissionOcrUnavailable);
      _expectClean(msg);
    });

    test('unknown raw text maps to the generic extraction message', () {
      final msg = UserMessage.forSubmissionOcr('upstream exploded at line 42');

      expect(msg, UserMessage.submissionOcrGeneric);
      _expectClean(msg);
    });

    test('clean Turkish user guidance may pass through', () {
      const clean =
          'Otomatik okuma başarısız oldu. Lütfen manuel kontrol edin.';

      expect(UserMessage.forSubmissionOcr(clean), clean);
    });
  });

  group('UserMessage.forGeneric', () {
    test('unexpected error falls back to the generic message', () {
      _expectClean(UserMessage.forGeneric(_realNoElementError()));
      _expectClean(UserMessage.forGeneric(Exception('anything')));
    });
  });
}
