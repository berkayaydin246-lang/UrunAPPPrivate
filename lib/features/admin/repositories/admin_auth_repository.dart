import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:food_analyzer_app/features/admin/utils/admin_auth_debug.dart';

abstract interface class AdminAuthRepository {
  Session? get currentSession;

  Stream<Session?> get authStateChanges;

  Future<void> signIn({required String email, required String password});

  Future<void> signOut();

  Future<bool> verifyAdminAuthorization();
}

final adminAuthRepositoryProvider = Provider<AdminAuthRepository>((ref) {
  return SupabaseAdminAuthRepository();
});

class SupabaseAdminAuthRepository implements AdminAuthRepository {
  SupabaseClient get _client => Supabase.instance.client;

  @override
  Session? get currentSession => _client.auth.currentSession;

  @override
  Stream<Session?> get authStateChanges => _client.auth.onAuthStateChange.map((
    event,
  ) {
    debugAdminAuth(
      'auth_event=${event.event.name} session_present=${event.session != null}',
    );
    return event.session;
  });

  @override
  Future<void> signIn({required String email, required String password}) async {
    debugAdminAuth('repository_sign_in_started');

    try {
      final response = await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );

      debugAdminAuth('sign_in_succeeded');
      debugAdminAuth('response_user_present=${response.user != null}');
      debugAdminAuth('response_session_present=${response.session != null}');
      debugAdminAuth(
        'current_user_present=${_client.auth.currentUser != null}',
      );
      debugAdminAuth(
        'current_session_present=${_client.auth.currentSession != null}',
      );

      final user =
          response.user ?? response.session?.user ?? _client.auth.currentUser;
      if (user != null) {
        final role = user.appMetadata['role']?.toString() ?? 'unknown';
        debugAdminAuth('user_id=${user.id}');
        debugAdminAuth('role=$role');
      }

      if (response.user == null || response.session == null) {
        throw const AuthException('missing_user_or_session');
      }
    } on AuthException catch (error) {
      debugAdminAuth(
        'sign_in_failed code=${error.code ?? 'unknown'} '
        'status=${error.statusCode ?? 'unknown'} '
        'message=${sanitizeAdminAuthMessage(error.message)}',
      );
      rethrow;
    } catch (error) {
      debugAdminAuth(
        'sign_in_failed code=unknown status=unknown '
        'message=${sanitizeAdminAuthMessage(error.toString())}',
      );
      rethrow;
    }
  }

  @override
  Future<void> signOut() {
    return _client.auth.signOut();
  }

  @override
  Future<bool> verifyAdminAuthorization() async {
    debugAdminAuth('admin_rpc_started');
    final response = await _client.rpc('is_freshscan_admin');
    debugAdminAuth('admin_rpc_raw_type=${response.runtimeType}');
    debugAdminAuth('admin_rpc_raw_value=${summarizeAdminRpcValue(response)}');

    final parsed = parseAdminAuthorizationResult(response);
    if (parsed != null) {
      debugAdminAuth('admin_rpc_parsed=$parsed');
      return parsed;
    }

    debugAdminAuth('admin_rpc_parsed=unrecognized');
    throw const FormatException('Unexpected admin authorization response');
  }
}

@visibleForTesting
bool? parseAdminAuthorizationResult(Object? raw) {
  if (raw is bool) {
    return raw;
  }

  if (raw is Map) {
    return _parseNestedAdminAuthorizationValue(
      raw['is_freshscan_admin'] ?? raw['is_admin'] ?? raw['data'],
    );
  }

  if (raw is List && raw.length == 1) {
    final first = raw.first;
    if (first is bool) {
      return first;
    }

    if (first is Map) {
      return _parseNestedAdminAuthorizationValue(
        first['is_freshscan_admin'] ?? first['is_admin'] ?? first['data'],
      );
    }
  }

  final normalized = raw?.toString().trim().toLowerCase();
  if (normalized == 'true') return true;
  if (normalized == 'false') return false;

  return null;
}

bool? _parseNestedAdminAuthorizationValue(Object? value) {
  if (value is bool) {
    return value;
  }

  final normalized = value?.toString().trim().toLowerCase();
  if (normalized == 'true') return true;
  if (normalized == 'false') return false;

  return null;
}
