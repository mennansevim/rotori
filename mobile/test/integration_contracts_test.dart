import 'package:flutter_test/flutter_test.dart';

import '../integration_test/helpers/test_harness.dart';

void main() {
  group('Integration Contract Suite (CI-friendly)', () {
    testWidgets('launch logged-out -> /auth', (tester) async {
      final state = launchApp(loggedIn: false);
      expect(state.location, '/auth');
    });

    testWidgets('launch logged-in -> /', (tester) async {
      final state = launchApp(loggedIn: true);
      expect(state.location, '/');
    });

    testWidgets('logged-in user /auth -> /plans', (tester) async {
      final route = applyAuthGuard(loggedIn: true, location: '/auth');
      expect(route, '/plans');
    });

    testWidgets('logout closes protected routes', (tester) async {
      final current = FlowState(loggedIn: true, location: '/plans');
      final next = logoutFrom(current);
      expect(next.location, '/auth');
      expect(next.loggedIn, isFalse);
    });

    testWidgets('main flow route contracts preserved', (tester) async {
      expect(applyAuthGuard(loggedIn: true, location: '/plans'), '/plans');
      expect(
        applyAuthGuard(loggedIn: true, location: '/plans/demo/view'),
        '/plans/demo/view',
      );
    });

    testWidgets('error recovery falls back to local plans', (tester) async {
      final source = FakePlansDataSource(
        localPlanIds: const ['plan-1', 'plan-2'],
        remoteFails: true,
      );
      final visible = source.visiblePlans();
      expect(visible, containsAll(const ['plan-1', 'plan-2']));
    });
  });
}
