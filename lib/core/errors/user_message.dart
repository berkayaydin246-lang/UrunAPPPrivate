import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

/// Converts any thrown error into a clean, user-safe Turkish message.
///
/// Release-safety contract: no raw developer text (Bad state, No element,
/// Exception, SocketException, StackTrace, "Instance of", null, type errors,
/// DioException, etc.) may ever reach the user. Anything that looks technical
/// is replaced with a friendly domain fallback.
///
/// Our own service layer intentionally throws `StateError('<Turkish message>')`
/// with already-clean text; those are preserved. Unexpected Dart errors
/// (e.g. `Bad state: No element` from an empty-list `.first`) are detected and
/// swapped for a generic message.
class UserMessage {
  const UserMessage._();

  static const network =
      'Bağlantı sorunu oluştu. Lütfen internet bağlantınızı kontrol edip tekrar deneyin.';
  static const timeout = 'İşlem beklenenden uzun sürdü. Lütfen tekrar deneyin.';
  static const ocrUnreadable =
      'İçindekiler metni okunamadı. Lütfen etiketi net, aydınlık ve yakın olacak şekilde tekrar çekin.';
  static const ocrNoLabel =
      'Bu görselde analiz edilebilir bir içerik etiketi bulunamadı.';
  static const analysisFailed =
      'Şu anda analiz tamamlanamadı. Lütfen biraz sonra tekrar deneyin.';
  static const generic = 'Bir sorun oluştu. Lütfen biraz sonra tekrar deneyin.';
  static const submissionOcrAuth =
      'OCR servisi doğrulanamadı. Ürün bilgilerini manuel kontrol edebilirsiniz.';
  static const submissionOcrUnreadable =
      'Görselden içerik metni okunamadı. Ürün bilgilerini manuel kontrol edebilirsiniz.';
  static const submissionOcrUnavailable =
      'OCR işlemi tamamlanamadı. Ürün bilgilerini manuel kontrol edebilirsiniz.';
  static const submissionOcrGeneric =
      'Otomatik metin çıkarma tamamlanamadı. Ürün bilgilerini manuel kontrol edebilirsiniz.';

  /// Lowercased fragments that indicate raw developer text leaked through.
  static const _technicalFragments = <String>[
    'bad state',
    'no element',
    'exception',
    'stacktrace',
    'stack trace',
    'instance of',
    'stateerror',
    'formatexception',
    'socketexception',
    'timeoutexception',
    'null check',
    'is null',
    'was null',
    'subtype',
    'os error',
    'errno',
    'dioexception',
    'requestoptions',
    'validatestatus',
    'status code',
    'developer.mozilla.org',
    'server code',
    'client error',
    'upstream',
    'response body',
    'request failed',
    'http error',
    'handshake',
    'unhandled',
    "type '",
    'assertion',
  ];

  static bool _isTechnical(String message) {
    final lower = message.toLowerCase();
    return lower.trim() == 'null' || _technicalFragments.any(lower.contains);
  }

  /// Extract a candidate message ONLY from our own error convention.
  ///
  /// Our service layer throws `StateError('<clean Turkish>')` (and occasionally
  /// `ArgumentError`) for user-safe messages. We deliberately do NOT trust the
  /// `.toString()` of arbitrary errors (generic `Exception`, `TypeError`,
  /// platform errors), because those carry raw developer text. Anything that is
  /// not a StateError/ArgumentError falls through to the domain fallback.
  static String? _ownMessage(Object error) {
    if (error is StateError) return error.message;
    if (error is ArgumentError) {
      final m = error.message;
      return m is String ? m : null;
    }
    return null;
  }

  static String? _byType(Object error) {
    if (error is TimeoutException) return timeout;
    if (error is SocketException) return network;
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return timeout;
        case DioExceptionType.connectionError:
          return network;
        case DioExceptionType.badResponse:
        case DioExceptionType.cancel:
        case DioExceptionType.badCertificate:
        case DioExceptionType.unknown:
          return null;
      }
    }
    return null;
  }

  static String _resolve(Object error, String fallback) {
    final typed = _byType(error);
    if (typed != null) return typed;
    final own = _ownMessage(error);
    if (own != null && own.trim().isNotEmpty && !_isTechnical(own)) {
      return own.trim();
    }
    return fallback;
  }

  /// Friendly message for OCR / image-scanning failures.
  static String forOcr(Object error) => _resolve(error, ocrUnreadable);

  /// Friendly message for product-submission OCR failures, including raw errors
  /// already persisted by older app versions.
  static String forSubmissionOcr(Object? errorOrMessage) {
    if (errorOrMessage == null) return submissionOcrGeneric;

    if (errorOrMessage is DioException) {
      final status = errorOrMessage.response?.statusCode;
      if (status == 401 || status == 403) return submissionOcrAuth;
      if (status == 400 || status == 422) return submissionOcrUnreadable;

      final type = errorOrMessage.type;
      if (type == DioExceptionType.connectionTimeout ||
          type == DioExceptionType.sendTimeout ||
          type == DioExceptionType.receiveTimeout ||
          type == DioExceptionType.connectionError) {
        return submissionOcrUnavailable;
      }
    }

    if (errorOrMessage is TimeoutException ||
        errorOrMessage is SocketException) {
      return submissionOcrUnavailable;
    }

    final candidate = errorOrMessage is String
        ? errorOrMessage.trim()
        : _ownMessage(errorOrMessage)?.trim();
    if (candidate == null || candidate.isEmpty) return submissionOcrGeneric;

    final lower = candidate.toLowerCase();
    if (_containsAny(lower, const [
      '401',
      '403',
      'unauthorized',
      'forbidden',
      'authentication',
      'authorization',
      'apikey',
      'jwt',
      'yetkilendir',
      'doğrulanamadı',
    ])) {
      return submissionOcrAuth;
    }

    if (_containsAny(lower, const [
      'görsel işlenemedi',
      'görselden içerik',
      'metni okunamadı',
      'etiket bulunamadı',
      'okunabilir metin',
      'no label',
      'unreadable image',
    ])) {
      return submissionOcrUnreadable;
    }

    if (_containsAny(lower, const [
      'timeout',
      'time out',
      'zaman aş',
      'connection',
      'network',
      'socket',
      'ulaşılamadı',
      '502',
      '503',
      '504',
    ])) {
      return submissionOcrUnavailable;
    }

    if (_isSafeSubmissionMessage(candidate)) return candidate;
    return submissionOcrGeneric;
  }

  static bool _containsAny(String value, List<String> fragments) =>
      fragments.any(value.contains);

  static bool _isSafeSubmissionMessage(String message) {
    if (message.length > 240 ||
        message.contains('\n') ||
        _isTechnical(message) ||
        RegExp(r'https?://|[\[\]{}]|=>|\b\d{3}\b').hasMatch(message)) {
      return false;
    }

    final lower = message.toLowerCase();
    return _containsAny(lower, const [
      'lütfen',
      'edebilirsiniz',
      'tamamlanamadı',
      'okunamadı',
      'başarısız',
      'ulaşılamadı',
      'bulunamadı',
      'yapılamadı',
      'kontrol edin',
      'tekrar deneyin',
    ]);
  }

  /// Friendly message for rule-based analysis failures.
  static String forAnalysis(Object error) => _resolve(error, analysisFailed);

  /// Friendly message for generic actions (submission, etc.).
  static String forGeneric(Object error) => _resolve(error, generic);
}
