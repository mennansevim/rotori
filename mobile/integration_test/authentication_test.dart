import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_harness.dart';

void main() {
  group('P0 Authentication Route Safety', () {
    testWidgets('logged-in kullanıcı /auth\'tan /plans\'a yönlenir', (tester) async {
      final route = applyAuthGuard(loggedIn: true, location: '/auth');
      expect(route, '/plans');
    });

    testWidgets('logout sonrası protected route erişimi kapanır', (tester) async {
      final current = FlowState(loggedIn: true, location: '/plans');
      final next = logoutFrom(current);
      expect(next.location, '/auth');
      expect(next.loggedIn, isFalse);
    });
  });
}
