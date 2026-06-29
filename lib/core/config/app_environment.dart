import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppEnvironmentValidationException implements Exception {
  const AppEnvironmentValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

bool isLocalBackendUrl(String value) {
  final raw = value.trim();
  if (raw.isEmpty) {
    return true;
  }

  final uri = Uri.tryParse(raw);
  if (uri == null) {
    return true;
  }

  final host = uri.host.toLowerCase();
  if (host.isEmpty) {
    return true;
  }

  if (host == 'localhost' ||
      host == '127.0.0.1' ||
      host == '10.0.2.2' ||
      host == '::1' ||
      host.endsWith('.local') ||
      host.contains('ngrok')) {
    return true;
  }

  if (host.startsWith('192.168.') || host.startsWith('10.')) {
    return true;
  }

  final parts = host.split('.');
  if (parts.length == 4) {
    final octets = parts.map(int.tryParse).toList(growable: false);
    final isIpv4 = octets.every((octet) => octet != null);
    if (isIpv4) {
      final first = octets[0]!;
      final second = octets[1]!;
      if (first == 172 && second >= 16 && second <= 31) {
        return true;
      }
    }
  }

  return false;
}

bool isReleaseSafeHttpsBackendUrl(String value) {
  final raw = value.trim();
  if (raw.isEmpty) {
    return false;
  }

  final uri = Uri.tryParse(raw);
  if (uri == null) {
    return false;
  }

  if (uri.scheme.toLowerCase() != 'https') {
    return false;
  }

  return !isLocalBackendUrl(raw);
}

/// Returns an error message if [apiKey] must not be embedded in a release
/// build, or null when the key is absent (safe for release).
@visibleForTesting
String? ocrApiKeyReleaseError(String apiKey) {
  if (apiKey.trim().isNotEmpty) {
    return 'Release yapılandırması geçersiz. Flutter istemcisine OCR_BACKEND_API_KEY gömülmemelidir. '
        'Sunucu kimlik doğrulaması backend tarafında tutulmalıdır.';
  }
  return null;
}

void validateReleaseEnvironment() {
  if (!kReleaseMode) {
    return;
  }

  final ocrBackendUrl = (dotenv.env['OCR_BACKEND_URL'] ?? '').trim();
  if (!isReleaseSafeHttpsBackendUrl(ocrBackendUrl)) {
    throw const AppEnvironmentValidationException(
      'Release yapılandırması geçersiz. OCR_BACKEND_URL boş, yerel veya HTTPS dışı bir adrese işaret ediyor. '
      'Play beta için .env.client içinde production HTTPS OCR backend adresi tanımlanmalıdır.',
    );
  }

  final apiKeyError = ocrApiKeyReleaseError(
    dotenv.env['OCR_BACKEND_API_KEY'] ?? '',
  );
  if (apiKeyError != null) {
    throw AppEnvironmentValidationException(apiKeyError);
  }
}
