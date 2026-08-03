import 'package:flutter_test/flutter_test.dart';
import 'package:japan_trip/core/router.dart';

void main() {
  group('resolveAuthRedirect', () {
    test('oturum yok + /auth dışında → /auth', () {
      expect(
        resolveAuthRedirect(loggedIn: false, matchedLocation: '/plans'),
        '/auth',
      );
    });

    test('oturum yok + zaten /auth → yönlendirme yok', () {
      expect(
        resolveAuthRedirect(loggedIn: false, matchedLocation: '/auth'),
        isNull,
      );
    });

    test('oturum var + /auth → /plans (login sonrası)', () {
      expect(
        resolveAuthRedirect(loggedIn: true, matchedLocation: '/auth'),
        '/plans',
      );
    });

    test('oturum var + normal sayfa → yönlendirme yok', () {
      expect(
        resolveAuthRedirect(loggedIn: true, matchedLocation: '/plans'),
        isNull,
      );
    });
  });
}
