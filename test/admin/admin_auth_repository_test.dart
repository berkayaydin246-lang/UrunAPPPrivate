import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/admin/repositories/admin_auth_repository.dart';

void main() {
  group('parseAdminAuthorizationResult', () {
    test('accepts scalar booleans', () {
      expect(parseAdminAuthorizationResult(true), isTrue);
      expect(parseAdminAuthorizationResult(false), isFalse);
    });

    test('accepts map variants', () {
      expect(
        parseAdminAuthorizationResult(const {'is_freshscan_admin': true}),
        isTrue,
      );
      expect(parseAdminAuthorizationResult(const {'is_admin': false}), isFalse);
      expect(parseAdminAuthorizationResult(const {'data': true}), isTrue);
    });

    test('accepts list variants', () {
      expect(
        parseAdminAuthorizationResult(const [
          {'is_freshscan_admin': true},
        ]),
        isTrue,
      );
      expect(parseAdminAuthorizationResult(const [false]), isFalse);
    });

    test('accepts string booleans and rejects unknown shapes', () {
      expect(parseAdminAuthorizationResult('true'), isTrue);
      expect(parseAdminAuthorizationResult('false'), isFalse);
      expect(
        parseAdminAuthorizationResult(const {'unexpected': 'value'}),
        isNull,
      );
      expect(parseAdminAuthorizationResult(const [1, 2]), isNull);
    });
  });
}
