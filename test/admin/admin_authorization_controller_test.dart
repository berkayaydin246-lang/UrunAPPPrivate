import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/admin/controllers/admin_authorization_controller.dart';
import 'package:food_analyzer_app/features/admin/repositories/admin_auth_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'helpers/admin_product_reports_test_helpers.dart';

void main() {
  group('AdminAuthorizationController', () {
    test('scalar true verification authorizes the current session', () async {
      final repository = _ControlledAdminAuthRepository(
        initialSession: fakeSession(),
        verifyBehavior: () async => true,
      );
      addTearDown(repository.dispose);

      final controller = AdminAuthorizationController(
        authRepository: repository,
      );
      addTearDown(controller.dispose);

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.status, AdminAuthorizationStatus.authorized);
      expect(repository.verifyCallCount, 1);
    });

    test('verification false produces notAuthorized', () async {
      final repository = _ControlledAdminAuthRepository(
        initialSession: fakeSession(appMetadata: const {'role': 'consumer'}),
        verifyBehavior: () async => false,
      );
      addTearDown(repository.dispose);

      final controller = AdminAuthorizationController(
        authRepository: repository,
      );
      addTearDown(controller.dispose);

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.status, AdminAuthorizationStatus.notAuthorized);
    });

    test(
      'verification failure preserves the session and does not sign out',
      () async {
        final repository = _ControlledAdminAuthRepository(
          initialSession: fakeSession(),
          verifyBehavior: () async => throw Exception('network'),
        );
        addTearDown(repository.dispose);

        final controller = AdminAuthorizationController(
          authRepository: repository,
        );
        addTearDown(controller.dispose);

        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(controller.state.status, AdminAuthorizationStatus.failure);
        expect(repository.currentSession, isNotNull);
        expect(repository.signOutCallCount, 0);
      },
    );

    test(
      'stale initialization cannot overwrite a newer authorized state',
      () async {
        final firstVerify = Completer<bool>();
        final secondVerify = Completer<bool>();
        var verifyCallCount = 0;
        final repository = _ControlledAdminAuthRepository(
          initialSession: fakeSession(),
          verifyBehavior: () {
            verifyCallCount++;
            return verifyCallCount == 1
                ? firstVerify.future
                : secondVerify.future;
          },
        );
        addTearDown(repository.dispose);

        final controller = AdminAuthorizationController(
          authRepository: repository,
        );
        addTearDown(controller.dispose);

        await repository.emitSession(fakeSession(userId: 'newer-admin'));
        await Future<void>.delayed(Duration.zero);

        secondVerify.complete(true);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        expect(controller.state.status, AdminAuthorizationStatus.authorized);

        firstVerify.complete(false);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        expect(controller.state.status, AdminAuthorizationStatus.authorized);
      },
    );

    test(
      'stale auth-stream verification cannot overwrite authorized',
      () async {
        final firstVerify = Completer<bool>();
        final secondVerify = Completer<bool>();
        var verifyCallCount = 0;
        final repository = _ControlledAdminAuthRepository(
          verifyBehavior: () {
            verifyCallCount++;
            return verifyCallCount == 1
                ? firstVerify.future
                : secondVerify.future;
          },
        );
        addTearDown(repository.dispose);

        final controller = AdminAuthorizationController(
          authRepository: repository,
        );
        addTearDown(controller.dispose);

        await Future<void>.delayed(Duration.zero);
        expect(controller.state.status, AdminAuthorizationStatus.signedOut);

        await repository.emitSession(fakeSession(userId: 'session-1'));
        await repository.emitSession(fakeSession(userId: 'session-2'));
        await Future<void>.delayed(Duration.zero);

        secondVerify.complete(true);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        expect(controller.state.status, AdminAuthorizationStatus.authorized);

        firstVerify.complete(false);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        expect(controller.state.status, AdminAuthorizationStatus.authorized);
      },
    );
  });
}

class _ControlledAdminAuthRepository implements AdminAuthRepository {
  _ControlledAdminAuthRepository({
    Session? initialSession,
    required this.verifyBehavior,
  }) : _currentSession = initialSession;

  final _controller = StreamController<Session?>.broadcast();
  final Future<bool> Function() verifyBehavior;

  Session? _currentSession;
  var signOutCallCount = 0;
  var verifyCallCount = 0;

  @override
  Session? get currentSession => _currentSession;

  @override
  Stream<Session?> get authStateChanges => _controller.stream;

  @override
  Future<void> signIn({required String email, required String password}) async {
    _currentSession = fakeSession(email: email);
    _controller.add(_currentSession);
  }

  @override
  Future<void> signOut() async {
    signOutCallCount++;
    _currentSession = null;
    _controller.add(null);
  }

  @override
  Future<bool> verifyAdminAuthorization() async {
    verifyCallCount++;
    return verifyBehavior();
  }

  Future<void> emitSession(Session? session) async {
    _currentSession = session;
    _controller.add(session);
  }

  void dispose() {
    unawaited(_controller.close());
  }
}
