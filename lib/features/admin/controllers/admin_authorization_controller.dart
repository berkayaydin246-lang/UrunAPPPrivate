import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:food_analyzer_app/features/admin/repositories/admin_auth_repository.dart';
import 'package:food_analyzer_app/features/admin/utils/admin_auth_debug.dart';

enum AdminAuthorizationStatus {
  checking,
  signedOut,
  notAuthorized,
  authorized,
  failure,
}

class AdminAuthorizationState {
  final AdminAuthorizationStatus status;
  final String? errorMessage;

  const AdminAuthorizationState({
    this.status = AdminAuthorizationStatus.checking,
    this.errorMessage,
  });

  bool get canSignOut =>
      status == AdminAuthorizationStatus.authorized ||
      status == AdminAuthorizationStatus.notAuthorized ||
      status == AdminAuthorizationStatus.failure;

  AdminAuthorizationState copyWith({
    AdminAuthorizationStatus? status,
    String? errorMessage,
    bool clearError = false,
  }) {
    return AdminAuthorizationState(
      status: status ?? this.status,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

final adminAuthorizationControllerProvider =
    StateNotifierProvider<
      AdminAuthorizationController,
      AdminAuthorizationState
    >((ref) {
      return AdminAuthorizationController(
        authRepository: ref.watch(adminAuthRepositoryProvider),
      );
    });

class AdminAuthorizationController
    extends StateNotifier<AdminAuthorizationState> {
  AdminAuthorizationController({required AdminAuthRepository authRepository})
    : _authRepository = authRepository,
      super(const AdminAuthorizationState()) {
    _subscription = _authRepository.authStateChanges.listen(
      _handleSessionChanged,
    );
    _initialize();
  }

  final AdminAuthRepository _authRepository;
  StreamSubscription<Session?>? _subscription;

  var _generation = 0;

  Future<void> _initialize() async {
    final generation = ++_generation;
    debugAdminAuth(
      'controller_initialize_started current_session_present='
      '${_authRepository.currentSession != null}',
    );

    if (_authRepository.currentSession == null) {
      _setStateIfCurrent(
        generation,
        const AdminAuthorizationState(
          status: AdminAuthorizationStatus.signedOut,
        ),
      );
      return;
    }

    await _verifyCurrentSession(generation: generation);
  }

  Future<void> signIn({required String email, required String password}) async {
    if (state.status == AdminAuthorizationStatus.checking) return;

    final generation = ++_generation;
    debugAdminAuth('controller_sign_in_started');
    _setStateIfCurrent(
      generation,
      state.copyWith(
        status: AdminAuthorizationStatus.checking,
        clearError: true,
      ),
    );

    try {
      await _authRepository.signIn(email: email.trim(), password: password);
      await _verifyCurrentSession(generation: generation);
    } catch (_) {
      _setStateIfCurrent(
        generation,
        const AdminAuthorizationState(
          status: AdminAuthorizationStatus.signedOut,
          errorMessage:
              'Giriş yapılamadı. E-posta veya şifreyi kontrol edip tekrar deneyin.',
        ),
      );
    }
  }

  Future<void> retry() async {
    final generation = ++_generation;
    if (_authRepository.currentSession == null) {
      _setStateIfCurrent(
        generation,
        const AdminAuthorizationState(
          status: AdminAuthorizationStatus.signedOut,
        ),
      );
      return;
    }

    await _verifyCurrentSession(generation: generation);
  }

  Future<void> signOut() async {
    final generation = ++_generation;
    try {
      await _authRepository.signOut();
    } catch (_) {
      // Sign-out failures should not leave admin data visible.
    }

    _setStateIfCurrent(
      generation,
      const AdminAuthorizationState(status: AdminAuthorizationStatus.signedOut),
    );
  }

  Future<void> _verifyCurrentSession({required int generation}) async {
    if (!_isCurrent(generation)) return;

    final session = _authRepository.currentSession;
    if (session == null) {
      debugAdminAuth('current_session_present=false');
      _setStateIfCurrent(
        generation,
        const AdminAuthorizationState(
          status: AdminAuthorizationStatus.signedOut,
        ),
      );
      return;
    }

    debugAdminAuth('current_session_present=true');
    _setStateIfCurrent(
      generation,
      state.copyWith(
        status: AdminAuthorizationStatus.checking,
        clearError: true,
      ),
    );

    try {
      final isAuthorized = await _authRepository.verifyAdminAuthorization();
      _setStateIfCurrent(
        generation,
        AdminAuthorizationState(
          status: isAuthorized
              ? AdminAuthorizationStatus.authorized
              : AdminAuthorizationStatus.notAuthorized,
        ),
      );
    } catch (_) {
      _setStateIfCurrent(
        generation,
        const AdminAuthorizationState(status: AdminAuthorizationStatus.failure),
      );
    }
  }

  void _handleSessionChanged(Session? session) {
    if (!mounted) return;

    final generation = ++_generation;
    if (session == null) {
      _setStateIfCurrent(
        generation,
        const AdminAuthorizationState(
          status: AdminAuthorizationStatus.signedOut,
        ),
      );
      return;
    }

    unawaited(_verifyCurrentSession(generation: generation));
  }

  bool _isCurrent(int generation) {
    return mounted && generation == _generation;
  }

  void _setStateIfCurrent(int generation, AdminAuthorizationState nextState) {
    if (!_isCurrent(generation)) return;

    state = nextState;
    debugAdminAuth('controller_state=${nextState.status.name}');
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
