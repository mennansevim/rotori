// packages/shared/src/__tests__/fillEmptyDays.test.ts'in birebir Dart eşdeğeri.

import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/domain/fill_empty_days.dart';
import 'package:rotori/domain/types.dart';

DayPlan _day({List<TimelineItem>? items}) => DayPlan(
      dayNumber: 1,
      date: '2026-10-01',
      theme: '',
      tags: [],
      items: items ?? [],
    );

final TripDestination _tokyoDest = TripDestination(
  id: 'd1',
  countryCode: 'JP',
  countryName: 'Japonya',
  city: 'Tokyo',
  arrivalDate: '2026-10-01',
  departureDate: '2026-10-10',
  order: 0,
);

void main() {
  group('fillEmptyDays', () {
    test('tamamen boş günü en az 4 itemla doldurur', () {
      final days = [_day()];
      final filled = fillEmptyDays(days, [_tokyoDest]);
      expect(filled[0].items.length, greaterThanOrEqualTo(4));
    });

    test('yeterince dolu günleri (>=4) değiştirmez', () {
      final days = [
        _day(
          items: List.generate(
            5,
            (i) => TimelineItem(
              id: 'i$i',
              title: 'Item $i',
              kind: TimelineItemKind.activity,
              time: '0${i + 8}:00',
            ),
          ),
        ),
      ];
      final filled = fillEmptyDays(days, [_tokyoDest]);
      expect(filled[0].items, hasLength(5));
    });

    test('az itemli günleri tamamlar, mevcut item korunur', () {
      final existing = TimelineItem(
        id: 'orig',
        title: 'Senso-ji Asakusa',
        kind: TimelineItemKind.activity,
        time: '10:00',
      );
      final days = [_day(items: [existing])];
      final filled = fillEmptyDays(days, [_tokyoDest]);
      expect(filled[0].items.length, greaterThanOrEqualTo(4));
      expect(filled[0].items.where((i) => i.id == 'orig'), isNotEmpty);
    });

    test('item zaman sırasına dizilir', () {
      final existing = TimelineItem(
        id: 'late',
        title: 'Geç aktivite',
        kind: TimelineItemKind.activity,
        time: '18:00',
      );
      final days = [_day(items: [existing])];
      final filled = fillEmptyDays(days, [_tokyoDest]);
      final times = filled[0].items.map((i) => i.time ?? '99:99').toList();
      final sorted = [...times]..sort((a, b) => a.compareTo(b));
      expect(times, sorted);
    });

    test('yemek slot sayısı 2 ile sınırlı', () {
      final days = [_day()];
      final filled = fillEmptyDays(days, [_tokyoDest]);
      final meals =
          filled[0].items.where((i) => i.kind == TimelineItemKind.meal);
      expect(meals.length, lessThanOrEqualTo(2));
    });

    test('mevcut öğle yemeğinin üstüne ikinci öğle EKLENMEZ (dedup)', () {
      // 11:30'da öğle yemeği zaten var → 13:00 slot'una ikinci öğle gelmemeli.
      final lunch = TimelineItem(
        id: 'lunch1',
        title: '🍜 Öğle yemeği molası',
        kind: TimelineItemKind.meal,
        time: '11:30',
        scheduledTime: '11:30',
      );
      final days = [_day(items: [lunch])];
      final filled = fillEmptyDays(days, [_tokyoDest]);
      final mealMins = filled[0].items
          .where((i) => i.kind == TimelineItemKind.meal)
          .map((i) {
        final p = (i.time ?? '99:99').split(':');
        return int.parse(p[0]) * 60 + int.parse(p[1]);
      }).toList();
      // Hiçbir iki yemek 2.5 saatten yakın olmamalı.
      mealMins.sort();
      for (var i = 1; i < mealMins.length; i++) {
        expect(mealMins[i] - mealMins[i - 1] >= 150, isTrue,
            reason: 'iki yemek üst üste gelmemeli (min 2.5 saat ara)');
      }
    });

    test('uzun mevcut aktivitenin üstüne çakışan slot eklenmez', () {
      final existing = TimelineItem(
        id: 'long',
        title: 'Uzun aktivite',
        kind: TimelineItemKind.activity,
        time: '10:00',
        durationMin: 90,
      );
      final filled = fillEmptyDays([
        _day(items: [existing])
      ], [
        _tokyoDest
      ]);
      final times = filled[0].items.map((item) => item.time).toSet();

      // 09:00 slotu 10:00–11:30 aktivitesine çakışır; 11:00 slotu da
      // aktivite bitişi ile 15 dk geçiş payına sığmaz.
      expect(times, isNot(contains('09:00')));
      expect(times, isNot(contains('11:00')));
    });
  });
}
