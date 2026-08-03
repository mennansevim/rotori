import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_harness.dart';

void main() {
  group('P1 Error Recovery Contracts', () {
    testWidgets('remote hata durumunda local plan listesi korunur', (tester) async {
      final source = FakePlansDataSource(
        localPlanIds: const ['plan-1', 'plan-2'],
        remoteFails: true,
      );

      final visible = source.visiblePlans();
      expect(visible, isNotEmpty);
      expect(visible, containsAll(const ['plan-1', 'plan-2']));
    });
  });
}
