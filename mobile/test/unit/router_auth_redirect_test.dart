import 'package:flutter_test/flutter_test.dart';
import 'package:japan_trip/core/router.dart';

void main() {
  group('resolveAuthRedirect', () {
    test('logged-out user is redirected to /auth from protected route', () {
      final redirect = resolveAuthRedirect(
        loggedIn: false,
        matchedLocation: '/plans',
      );

      expect(redirect, '/auth');
    });

    test('logged-out user can stay on /auth', () {
      final redirect = resolveAuthRedirect(
        loggedIn: false,
        matchedLocation: '/auth',
      );

      expect(redirect, isNull);
    });

    test('logged-in user is redirected away from /auth to /plans', () {
      final redirect = resolveAuthRedirect(
        loggedIn: true,
        matchedLocation: '/auth',
      );

      expect(redirect, '/plans');
    });

    test('logged-in user can stay on /plans', () {
      final redirect = resolveAuthRedirect(
        loggedIn: true,
        matchedLocation: '/plans',
      );

      expect(redirect, isNull);
    });

    test('logged-out user from root is redirected to /auth', () {
      final redirect = resolveAuthRedirect(
        loggedIn: false,
        matchedLocation: '/',
      );

      expect(redirect, '/auth');
    });
  });
}
