import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_harness.dart';

void main() {
  group('P1 Main Flow Contracts', () {
    testWidgets('authenticated akışta plans erişilebilir', (tester) async {
      final route = applyAuthGuard(loggedIn: true, location: '/plans');
      expect(route, '/plans');
    });

    testWidgets('authenticated kullanıcı viewer rotasına erişebilir', (tester) async {
      final route = applyAuthGuard(loggedIn: true, location: '/plans/demo/view');
      expect(route, '/plans/demo/view');
    });
  });
}
