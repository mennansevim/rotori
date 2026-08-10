// packages/shared/src/__tests__/maxTripDays.test.ts'in birebir Dart eşdeğeri.

import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/domain/types.dart';

void main() {
  group('kMaxTripDays', () {
    test('31 sabit (yaklaşık 1 ay)', () {
      expect(kMaxTripDays, 31);
    });

    test('clamp davranışı: end > start+MAX-1 → kısıt', () {
      // Welcome/Journey'de uygulanan clamp formülünün doğruluğu
      final d =
          DateTime.utc(2026, 10, 1).add(const Duration(days: kMaxTripDays - 1));
      final maxEnd = d.toIso8601String().substring(0, 10);
      expect(maxEnd, '2026-10-31');
    });
  });
}
