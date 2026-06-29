import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/core/config/app_environment.dart';
import 'package:food_analyzer_app/features/ocr/services/production_ocr_service.dart';

HttpProductionOcrService _service({
  String apiKey = '',
  String baseUrl = 'http://localhost:8000',
}) {
  return HttpProductionOcrService(dio: Dio(), baseUrl: baseUrl, apiKey: apiKey);
}

RequestOptions _fakeRequest() => RequestOptions(path: '/ocr/ingredients');

Response<dynamic> _fakeResponse(
  RequestOptions options, {
  int statusCode = 200,
}) => Response(requestOptions: options, statusCode: statusCode);

DioException _dioException({
  int? statusCode,
  DioExceptionType type = DioExceptionType.badResponse,
}) {
  final opts = _fakeRequest();
  return DioException(
    requestOptions: opts,
    response: statusCode != null
        ? _fakeResponse(opts, statusCode: statusCode)
        : null,
    type: type,
  );
}

void main() {
  // ── Authorization header ────────────────────────────────────────────────────

  group('Authorization header', () {
    test('sends Bearer token when OCR_BACKEND_API_KEY is non-empty', () {
      final headers = _service(apiKey: 'secret-key-123').headersForTest();
      expect(headers['Authorization'], 'Bearer secret-key-123');
    });

    test('trims surrounding whitespace from the key', () {
      final headers = _service(apiKey: '  my-key  ').headersForTest();
      expect(headers['Authorization'], 'Bearer my-key');
    });

    test('omits Authorization header when key is empty', () {
      final headers = _service(apiKey: '').headersForTest();
      expect(headers.containsKey('Authorization'), isFalse);
    });

    test('omits Authorization header when key is only whitespace', () {
      final headers = _service(apiKey: '   ').headersForTest();
      expect(headers.containsKey('Authorization'), isFalse);
    });

    test('always includes Content-Type regardless of key', () {
      expect(
        _service(apiKey: '').headersForTest()['Content-Type'],
        'application/json',
      );
      expect(
        _service(apiKey: 'k').headersForTest()['Content-Type'],
        'application/json',
      );
    });
  });

  // ── HTTP error mapping ──────────────────────────────────────────────────────

  group('HTTP error mapping', () {
    test('401 maps to Turkish auth error', () {
      final msg = HttpProductionOcrService.mapDioError(
        _dioException(statusCode: 401),
      );
      expect(msg, contains('yetkilendirmesi başarısız'));
      expect(msg, contains('OCR yapılandırmasını kontrol et'));
    });

    test('403 maps to Turkish auth error', () {
      final msg = HttpProductionOcrService.mapDioError(
        _dioException(statusCode: 403),
      );
      expect(msg, contains('yetkilendirmesi başarısız'));
    });

    test('500 maps to server unavailable message', () {
      final msg = HttpProductionOcrService.mapDioError(
        _dioException(statusCode: 500),
      );
      expect(msg, contains('şu anda yanıt veremiyor'));
    });

    test('503 maps to server unavailable message', () {
      final msg = HttpProductionOcrService.mapDioError(
        _dioException(statusCode: 503),
      );
      expect(msg, contains('şu anda yanıt veremiyor'));
    });

    test('receiveTimeout maps to Turkish timeout message', () {
      final msg = HttpProductionOcrService.mapDioError(
        _dioException(type: DioExceptionType.receiveTimeout),
      );
      expect(msg, contains('zaman aşımına uğradı'));
    });

    test('sendTimeout maps to Turkish timeout message', () {
      final msg = HttpProductionOcrService.mapDioError(
        _dioException(type: DioExceptionType.sendTimeout),
      );
      expect(msg, contains('zaman aşımına uğradı'));
    });

    test('connectionTimeout maps to Turkish timeout message', () {
      final msg = HttpProductionOcrService.mapDioError(
        _dioException(type: DioExceptionType.connectionTimeout),
      );
      expect(msg, contains('zaman aşımına uğradı'));
    });

    test('connectionError maps to Turkish network error', () {
      final msg = HttpProductionOcrService.mapDioError(
        _dioException(type: DioExceptionType.connectionError),
      );
      expect(msg, contains('ulaşılamadı'));
    });

    test('error messages contain no raw Dio/Mozilla technical text', () {
      for (final type in [
        DioExceptionType.receiveTimeout,
        DioExceptionType.connectionError,
        DioExceptionType.connectionTimeout,
      ]) {
        final msg = HttpProductionOcrService.mapDioError(
          _dioException(type: type),
        );
        expect(msg, isNot(contains('DioException')));
        expect(msg, isNot(contains('Mozilla')));
        expect(msg, isNot(contains('SocketException')));
      }
    });
  });

  // ── Release environment validation ─────────────────────────────────────────

  group('Release environment: OCR_BACKEND_API_KEY must not be embedded', () {
    test('non-empty key produces a Turkish rejection message', () {
      final error = ocrApiKeyReleaseError('some-backend-secret');
      expect(error, isNotNull);
      expect(error, contains('OCR_BACKEND_API_KEY'));
      expect(error, contains('gömülmemelidir'));
    });

    test('empty key is safe for release — returns null', () {
      expect(ocrApiKeyReleaseError(''), isNull);
    });

    test('whitespace-only key is safe for release — returns null', () {
      expect(ocrApiKeyReleaseError('   '), isNull);
    });

    test('rejection message mentions backend-side auth', () {
      final error = ocrApiKeyReleaseError('key');
      expect(error, contains('backend tarafında tutulmalıdır'));
    });
  });
}
