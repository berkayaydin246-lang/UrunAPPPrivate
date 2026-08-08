import 'dart:convert';

import 'package:crypto/crypto.dart';

class ScoreAuditFingerprint {
  const ScoreAuditFingerprint._();

  static final RegExp _sha256Pattern = RegExp(r'^[a-f0-9]{64}$');

  static String create(Map<String, Object?> payload) {
    final canonicalJson = canonicalJsonEncode(payload);
    return sha256.convert(utf8.encode(canonicalJson)).toString();
  }

  static bool isValid(String value) => _sha256Pattern.hasMatch(value);

  static String canonicalJsonEncode(Object? value) {
    return jsonEncode(_canonicalize(value));
  }

  static Object? _canonicalize(Object? value) {
    if (value == null || value is String || value is bool) return value;
    if (value is num) {
      if (!value.isFinite) {
        throw ArgumentError.value(value, 'value', 'must be finite');
      }
      return value == 0 ? 0 : value;
    }
    if (value is List) {
      return value.map(_canonicalize).toList(growable: false);
    }
    if (value is Map) {
      final entries =
          value.entries
              .map((entry) => MapEntry(entry.key.toString(), entry.value))
              .toList(growable: false)
            ..sort((left, right) => left.key.compareTo(right.key));
      return <String, Object?>{
        for (final entry in entries) entry.key: _canonicalize(entry.value),
      };
    }
    throw ArgumentError.value(
      value,
      'value',
      'must contain only JSON-compatible values',
    );
  }
}
