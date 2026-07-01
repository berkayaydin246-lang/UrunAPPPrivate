import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/core/config/app_environment.dart';
import 'package:food_analyzer_app/features/ocr/services/production_ocr_service.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

const _directUrl = 'http://localhost:8000';
const _edgeUrl = 'https://dzsmkmwatwvuxigynimq.supabase.co/functions/v1';

HttpProductionOcrService _service({
  String apiKey = '',
  String baseUrl = _directUrl,
  String supabaseAnonKey = '',
}) => HttpProductionOcrService(
  dio: Dio(),
  baseUrl: baseUrl,
  apiKey: apiKey,
  supabaseAnonKey: supabaseAnonKey,
);

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

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── Mode A: direct backend (OCR_BACKEND_API_KEY present) ──────────────────

  group('Mode A — direct backend (OCR_BACKEND_API_KEY)', () {
    test('sends Bearer token when key is non-empty', () {
      final h = _service(apiKey: 'secret-key-123').headersForTest();
      expect(h['Authorization'], 'Bearer secret-key-123');
    });

    test('trims surrounding whitespace from the key', () {
      final h = _service(apiKey: '  my-key  ').headersForTest();
      expect(h['Authorization'], 'Bearer my-key');
    });

    test('does NOT send apikey header in direct mode', () {
      final h = _service(apiKey: 'secret').headersForTest();
      expect(h.containsKey('apikey'), isFalse);
    });

    test(
      'OCR_BACKEND_API_KEY takes precedence — anon key not sent even if present',
      () {
        final h = _service(
          apiKey: 'direct-secret',
          supabaseAnonKey: 'anon-jwt',
        ).headersForTest();
        expect(h['Authorization'], 'Bearer direct-secret');
        expect(h.containsKey('apikey'), isFalse);
      },
    );

    test('omits Authorization header when key is empty', () {
      final h = _service(apiKey: '').headersForTest();
      expect(h.containsKey('Authorization'), isFalse);
    });

    test('omits Authorization header when key is only whitespace', () {
      final h = _service(apiKey: '   ').headersForTest();
      expect(h.containsKey('Authorization'), isFalse);
    });

    test('always includes Content-Type', () {
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

  // ── Mode B: Supabase Edge Function (SUPABASE_ANON_KEY) ────────────────────

  group('Mode B — Supabase Edge Function', () {
    test(
      'isSupabaseFunctionsUrl is true for .supabase.co/functions/v1 URL',
      () {
        expect(
          _service(baseUrl: _edgeUrl).isSupabaseFunctionsUrlForTest,
          isTrue,
        );
      },
    );

    test('isSupabaseFunctionsUrl matches /functions/v1 path segment', () {
      expect(
        _service(
          baseUrl: 'https://example.com/functions/v1',
        ).isSupabaseFunctionsUrlForTest,
        isTrue,
      );
    });

    test('isSupabaseFunctionsUrl is false for direct backend URL', () {
      expect(
        _service(baseUrl: _directUrl).isSupabaseFunctionsUrlForTest,
        isFalse,
      );
    });

    test('sends apikey and Authorization: Bearer <anonKey>', () {
      final h = _service(
        baseUrl: _edgeUrl,
        supabaseAnonKey: 'anon-jwt-value',
      ).headersForTest();
      expect(h['apikey'], 'anon-jwt-value');
      expect(h['Authorization'], 'Bearer anon-jwt-value');
    });

    test(
      'does not require OCR_BACKEND_API_KEY — anon key alone is sufficient',
      () {
        final h = _service(
          baseUrl: _edgeUrl,
          apiKey: '', // no direct key
          supabaseAnonKey: 'anon-jwt',
        ).headersForTest();
        expect(h.containsKey('Authorization'), isTrue);
        expect(h['Authorization'], 'Bearer anon-jwt');
      },
    );

    test('trims whitespace from anon key', () {
      final h = _service(
        baseUrl: _edgeUrl,
        supabaseAnonKey: '  trimmed-key  ',
      ).headersForTest();
      expect(h['apikey'], 'trimmed-key');
      expect(h['Authorization'], 'Bearer trimmed-key');
    });

    test(
      'no apikey or Authorization header when anon key is empty in edge mode',
      () {
        final h = _service(
          baseUrl: _edgeUrl,
          supabaseAnonKey: '',
        ).headersForTest();
        expect(h.containsKey('apikey'), isFalse);
        expect(h.containsKey('Authorization'), isFalse);
      },
    );

    test('Content-Type is always present in edge function mode', () {
      final h = _service(
        baseUrl: _edgeUrl,
        supabaseAnonKey: 'anon',
      ).headersForTest();
      expect(h['Content-Type'], 'application/json');
    });
  });

  // ── Secret hygiene ─────────────────────────────────────────────────────────

  group('Secret hygiene', () {
    test('CLAUDE_API_KEY is never in headers', () {
      for (final h in [
        _service(apiKey: 'backend-key').headersForTest(),
        _service(baseUrl: _edgeUrl, supabaseAnonKey: 'anon').headersForTest(),
      ]) {
        expect(h.containsKey('CLAUDE_API_KEY'), isFalse);
        expect(h.keys.any((k) => k.toLowerCase().contains('claude')), isFalse);
      }
    });

    test('service-role key is never in headers', () {
      for (final h in [
        _service(apiKey: 'backend-key').headersForTest(),
        _service(baseUrl: _edgeUrl, supabaseAnonKey: 'anon').headersForTest(),
      ]) {
        expect(h.keys.any((k) => k.toLowerCase().contains('service')), isFalse);
      }
    });
  });

  // ── HTTP error mapping ─────────────────────────────────────────────────────

  group('HTTP error mapping', () {
    test('401 maps to short Turkish auth error', () {
      final msg = HttpProductionOcrService.mapDioError(
        _dioException(statusCode: 401),
      );
      expect(msg, contains('yetkilendirmesi başarısız'));
    });

    test('403 maps to short Turkish auth error', () {
      final msg = HttpProductionOcrService.mapDioError(
        _dioException(statusCode: 403),
      );
      expect(msg, contains('yetkilendirmesi başarısız'));
    });

    test('404 maps to address-not-found Turkish message', () {
      final msg = HttpProductionOcrService.mapDioError(
        _dioException(statusCode: 404),
      );
      expect(msg, contains('bulunamadı'));
      expect(msg, contains('yapılandırmayı kontrol et'));
    });

    test('429 maps to rate-limit Turkish message', () {
      final msg = HttpProductionOcrService.mapDioError(
        _dioException(statusCode: 429),
      );
      expect(msg, contains('Çok fazla deneme'));
    });

    test('400 maps to unreadable-image Turkish message', () {
      final msg = HttpProductionOcrService.mapDioError(
        _dioException(statusCode: 400),
      );
      expect(msg, contains('Görsel işlenemedi'));
    });

    test('422 maps to unreadable-image Turkish message', () {
      final msg = HttpProductionOcrService.mapDioError(
        _dioException(statusCode: 422),
      );
      expect(msg, contains('Görsel işlenemedi'));
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

    test('connectionError maps to Turkish network-unreachable message', () {
      final msg = HttpProductionOcrService.mapDioError(
        _dioException(type: DioExceptionType.connectionError),
      );
      expect(msg, contains('ulaşılamadı'));
    });

    test('no raw DioException/Mozilla/SocketException text in any error', () {
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

    test('no raw developer text in any HTTP status mapping', () {
      for (final status in [400, 401, 403, 404, 422, 429, 500, 502, 503]) {
        final msg = HttpProductionOcrService.mapDioError(
          _dioException(statusCode: status),
        );
        expect(msg, isNot(contains('DioException')));
        expect(msg, isNot(contains('Bad state')));
        expect(msg, isNot(contains('Exception')));
        expect(msg.trim(), isNotEmpty);
      }
    });
  });

  // ── Release validation ────────────────────────────────────────────────────

  group('Release validation: OCR_BACKEND_API_KEY must not be embedded', () {
    test('non-empty key returns Turkish rejection message', () {
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
      expect(
        ocrApiKeyReleaseError('key'),
        contains('backend tarafında tutulmalıdır'),
      );
    });
  });
}
