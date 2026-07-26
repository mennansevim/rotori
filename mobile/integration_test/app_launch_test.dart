import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_harness.dart';

void main() {
  group('P0 Launch & Auth Guard', () {
    testWidgets('logged-out launch /auth yönlendirir', (tester) async {
      final state = launchApp(loggedIn: false);
      expect(state.location, '/auth');
    });

    testWidgets('logged-in launch / üzerinde kalabilir', (tester) async {
      final state = launchApp(loggedIn: true);
      expect(state.location, '/');
    });
  });
}
