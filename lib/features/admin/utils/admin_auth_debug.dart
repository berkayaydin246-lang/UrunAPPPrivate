import 'package:flutter/foundation.dart';

void debugAdminAuth(String message) {
  if (!kDebugMode) return;
  debugPrint('[admin_auth] $message');
}

String sanitizeAdminAuthMessage(String message) {
  return message.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String summarizeAdminRpcValue(Object? raw) {
  if (raw == null) {
    return 'null';
  }

  final value = raw.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  if (value.length <= 240) {
    return value;
  }

  return '${value.substring(0, 237)}...';
}
