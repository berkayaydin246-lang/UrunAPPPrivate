import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/core/config/app_environment.dart';

void main() {
  group('isLocalBackendUrl', () {
    test('treats empty and malformed values as local', () {
      expect(isLocalBackendUrl(''), isTrue);
      expect(isLocalBackendUrl('not a url'), isTrue);
    });

    test('treats local development hosts as local', () {
      expect(isLocalBackendUrl('http://127.0.0.1:8000'), isTrue);
      expect(isLocalBackendUrl('http://localhost:8000'), isTrue);
      expect(isLocalBackendUrl('http://10.0.2.2:8000'), isTrue);
      expect(isLocalBackendUrl('http://192.168.1.15:8000'), isTrue);
      expect(isLocalBackendUrl('https://preview.ngrok.app'), isTrue);
    });

    test('allows public production hosts', () {
      expect(isLocalBackendUrl('https://ocr.freshscan.app'), isFalse);
      expect(isLocalBackendUrl('https://api.example.com/ocr'), isFalse);
    });
  });

  group('isReleaseSafeHttpsBackendUrl', () {
    test('rejects empty, local, and non-https endpoints', () {
      expect(isReleaseSafeHttpsBackendUrl(''), isFalse);
      expect(isReleaseSafeHttpsBackendUrl('http://127.0.0.1:8000'), isFalse);
      expect(isReleaseSafeHttpsBackendUrl('http://ocr.freshscan.app'), isFalse);
    });

    test('accepts public https endpoints', () {
      expect(isReleaseSafeHttpsBackendUrl('https://ocr.freshscan.app'), isTrue);
      expect(
        isReleaseSafeHttpsBackendUrl('https://api.example.com/ocr'),
        isTrue,
      );
    });
  });
}
