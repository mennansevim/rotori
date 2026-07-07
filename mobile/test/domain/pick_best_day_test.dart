// packages/shared/src/__tests__/pickBestDay.test.ts'in birebir Dart eşdeğeri.

import 'package:flutter_test/flutter_test.dart';
import 'package:japan_trip/domain/trip_factory.dart';
import 'package:japan_trip/domain/types.dart';

DayPlan _makeDay(int n, [int activities = 0, int steps = 0]) => DayPlan(
      dayNumber: n,
      date: '2026-10-${n.toString().padLeft(2, '0')}',
      theme: '',
      tags: [],
      stepsEstimate: steps,
      items: List.generate(
        activities,
        (i) => TimelineItem(
          id: '$n-$i',
          title: 'act $i',
          kind: TimelineItemKind.activity,
        ),
      ),
    );

void main() {
  group('pickBestDayForDestination', () {
    test('boş listede null döner', () {
      expect(pickBestDayForDestination([_makeDay(1)], []), isNull);
    });

    test('en az aktiviteli günü seçer', () {
      final days = [_makeDay(1, 3), _makeDay(2, 0), _makeDay(3, 2)];
      expect(pickBestDayForDestination(days, [1, 2, 3]), 2);
    });

    test('eşit aktivitede daha düşük adım tahminini tercih eder', () {
      final days = [_makeDay(1, 2, 12000), _makeDay(2, 2, 8000)];
      expect(pickBestDayForDestination(days, [1, 2]), 2);
    });

    test('eşit metriklerde en erken günü tercih eder', () {
      final days = [_makeDay(2, 1, 9000), _makeDay(1, 1, 9000)];
      expect(pickBestDayForDestination(days, [1, 2]), 1);
    });

    test('sadece izin verilen günler arasından seçer', () {
      final days = [_makeDay(1, 0), _makeDay(2, 5), _makeDay(3, 0)];
      expect(pickBestDayForDestination(days, [2]), 2);
    });
  });
}
