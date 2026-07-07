// optimizeDayItems (geo + anchor + meal-slot mantığı) davranış testleri.
// TS packages/shared/src/dayOptimizer.ts portunun doğrulaması.

import 'package:flutter_test/flutter_test.dart';
import 'package:japan_trip/domain/day_optimizer.dart';
import 'package:japan_trip/domain/types.dart';

TimelineItem _item(
  String id, {
  String? time,
  TimelineItemKind kind = TimelineItemKind.activity,
  double? lat,
  double? lng,
}) =>
    TimelineItem(
      id: id,
      title: id,
      kind: kind,
      time: time,
      scheduledTime: time,
      lat: lat,
      lng: lng,
    );

void main() {
  group('optimizeDayItems', () {
    test('tek kalem olduğu gibi döner', () {
      final items = [_item('a', time: '10:00')];
      expect(identical(optimizeDayItems(items), items), isTrue);
    });

    test('koordinatlı kalemler en kuzeyden nearest-neighbor sıralanır', () {
      final items = [
        _item('a', lat: 35.0, lng: 139.7),
        _item('b', lat: 35.7, lng: 139.7), // en kuzey — başlangıç
        _item('c', lat: 35.3, lng: 139.7),
      ];
      final out = optimizeDayItems(items);
      expect(out.map((i) => i.id).toList(), ['b', 'c', 'a']);
      // 09:00 başlar; activity 90 dk + 30 dk geçiş = 2 saat aralık.
      expect(out.map((i) => i.time).toList(), ['09:00', '11:00', '13:00']);
      expect(out.map((i) => i.scheduledTime).toList(),
          ['09:00', '11:00', '13:00']);
    });

    test('anchor (transport) kendi saatinde sabit kalır', () {
      final items = [
        _item('act1', time: '10:00'),
        _item('flight', time: '08:00', kind: TimelineItemKind.transport),
        _item('act2', time: '12:00'),
      ];
      final out = optimizeDayItems(items);
      expect(out.map((i) => i.id).toList(), ['flight', 'act1', 'act2']);
      // Uçuş 09:00'dan önce → gün 08:00'de başlar, transport 30 dk sürer.
      expect(out.map((i) => i.time).toList(), ['08:00', '08:30', '10:30']);
    });

    test('geleceğe ait anchor esneklerden sonra kendi saatinde eklenir', () {
      final items = [
        _item('act1', time: '09:00'),
        _item('act2', time: '11:00'),
        _item('flight', time: '14:00', kind: TimelineItemKind.transport),
      ];
      final out = optimizeDayItems(items);
      expect(out.map((i) => i.id).toList(), ['act1', 'act2', 'flight']);
      expect(out.map((i) => i.time).toList(), ['09:00', '11:00', '14:00']);
    });

    test('yemek öğle civarına (12:30+) kaydırılır', () {
      final items = [
        _item('act1', time: '09:00'),
        _item('meal', time: '12:00', kind: TimelineItemKind.meal),
        _item('act2', time: '13:00'),
      ];
      final out = optimizeDayItems(items);
      // Sabah çok erken olduğu için yemek sona itilir, 13:00'te öğle olur.
      expect(out.map((i) => i.id).toList(), ['act1', 'act2', 'meal']);
      expect(out.map((i) => i.time).toList(), ['09:00', '11:00', '13:00']);
    });

    test('item id kümesi korunur (kayıp/kopya yok)', () {
      final items = [
        _item('a', time: '10:00'),
        _item('b', time: '09:00', kind: TimelineItemKind.meal),
        _item('c', time: '15:00', kind: TimelineItemKind.hotel),
        _item('d'),
      ];
      final out = optimizeDayItems(items);
      expect(out.map((i) => i.id).toSet(), {'a', 'b', 'c', 'd'});
      expect(out, hasLength(4));
    });
  });

  group('optimizeDay', () {
    test('yalnızca items alanını günceller', () {
      final day = DayPlan(
        dayNumber: 3,
        date: '2026-10-03',
        theme: 'Tema',
        tags: ['x'],
        items: [
          _item('b', time: '13:00'),
          _item('a', time: '10:00'),
        ],
      );
      final out = optimizeDay(day);
      expect(out.dayNumber, 3);
      expect(out.theme, 'Tema');
      expect(out.items.map((i) => i.time).toList(), ['09:00', '11:00']);
    });
  });
}
