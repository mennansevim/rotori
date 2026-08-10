import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/domain/day_schedule.dart';
import 'package:rotori/domain/types.dart';

TimelineItem _item(String id, String time, {int? durationMin, String? title}) =>
    TimelineItem(
      id: id,
      title: title ?? id,
      time: time,
      scheduledTime: time,
      durationMin: durationMin,
    );

void main() {
  group('timeToMinutes / minutesToTime', () {
    test('geçerli saatleri dönüştürür', () {
      expect(timeToMinutes('09:00'), 540);
      expect(timeToMinutes('13:30'), 810);
      expect(timeToMinutes('00:00'), 0);
      expect(timeToMinutes('23:59'), 1439);
    });

    test('geçersiz/boş girdide null', () {
      expect(timeToMinutes(null), isNull);
      expect(timeToMinutes(''), isNull);
      expect(timeToMinutes('abc'), isNull);
      expect(timeToMinutes('9'), isNull);
    });

    test('minutesToTime iki haneli sıfır dolgulu', () {
      expect(minutesToTime(540), '09:00');
      expect(minutesToTime(810), '13:30');
      expect(minutesToTime(0), '00:00');
    });

    test('minutesToTime sınırları kırpar', () {
      expect(minutesToTime(-10), '00:00');
      expect(minutesToTime(24 * 60), '23:59');
    });

    test('gidiş-dönüş tutarlı', () {
      for (final t in ['07:15', '12:00', '18:45', '23:00']) {
        expect(minutesToTime(timeToMinutes(t)!), t);
      }
    });
  });

  group('applyManualTimeEdit — SAAT GÜNCELLEME (kritik)', () {
    test('seçilen saat KORUNUR ve ezilmez', () {
      final items = [
        _item('a', '09:00'),
        _item('b', '11:00'),
        _item('c', '14:00'),
      ];
      // Kullanıcı 3. durağı 16:30 yaptı.
      applyManualTimeEdit(items, 2, 16 * 60 + 30);
      final c = items.firstWhere((e) => e.id == 'c');
      expect(c.time, '16:30', reason: 'kullanıcının girdiği saat korunmalı');
      expect(c.scheduledTime, '16:30');
    });

    test('diğer durakların saatleri DEĞİŞMEZ', () {
      final items = [
        _item('a', '09:00'),
        _item('b', '11:00'),
        _item('c', '14:00'),
      ];
      applyManualTimeEdit(items, 2, 16 * 60 + 30);
      expect(items.firstWhere((e) => e.id == 'a').time, '09:00');
      expect(items.firstWhere((e) => e.id == 'b').time, '11:00');
    });

    test('yeni saate göre yeniden sıralanır', () {
      final items = [
        _item('a', '09:00'),
        _item('b', '11:00'),
        _item('c', '14:00'),
      ];
      // 1. durağı 12:00 yaptık → b'den sonra gelmeli.
      applyManualTimeEdit(items, 0, 12 * 60);
      expect(items.map((e) => e.id).toList(), ['b', 'a', 'c']);
      expect(items.map((e) => e.time).toList(), ['11:00', '12:00', '14:00']);
    });

    test('erken saate çekince başa gelir', () {
      final items = [
        _item('a', '09:00'),
        _item('b', '11:00'),
        _item('c', '14:00'),
      ];
      applyManualTimeEdit(items, 2, 8 * 60);
      expect(items.map((e) => e.id).toList(), ['c', 'a', 'b']);
    });

    test('geçersiz index güvenli (no-op)', () {
      final items = [_item('a', '09:00')];
      applyManualTimeEdit(items, 5, 12 * 60);
      expect(items.single.time, '09:00');
    });
  });

  group('redistributeDayTimes — SÜRÜKLE-BIRAK yeniden saatleme', () {
    test('ilk item çıpa, saatler artan sırada', () {
      final items = [
        _item('a', '09:00', durationMin: 90),
        _item('b', '10:00', durationMin: 90),
        _item('c', '11:00', durationMin: 90),
      ];
      redistributeDayTimes(items);
      final mins = items
          .map((e) => timeToMinutes(e.time)!)
          .toList();
      expect(mins.first, 540, reason: 'ilk item saati çıpa (09:00)');
      for (var i = 1; i < mins.length; i++) {
        expect(mins[i] > mins[i - 1], isTrue, reason: 'saatler artmalı');
      }
    });

    test('süreye göre makul aralık (90dk + geçiş, 15dk yuvarlı)', () {
      final items = [
        _item('a', '09:00', durationMin: 90),
        _item('b', '00:00', durationMin: 90),
      ];
      redistributeDayTimes(items);
      // 90 + 15 = 105 → 15'e yuvarlı 105 → 09:00 + 105dk = 10:45
      expect(items[0].time, '09:00');
      expect(items[1].time, '10:45');
    });

    test('boş listede çökmemeli', () {
      final items = <TimelineItem>[];
      expect(() => redistributeDayTimes(items), returnsNormally);
    });

    test('saat aşımında 23:59 sınırında kalır', () {
      final items = [
        _item('a', '23:00', durationMin: 240),
        _item('b', '00:00', durationMin: 240),
        _item('c', '00:00', durationMin: 240),
      ];
      redistributeDayTimes(items);
      for (final it in items) {
        expect(timeToMinutes(it.time)! <= 1439, isTrue);
      }
    });
  });

  group('insertItemSorted — yeni durak ekleme', () {
    test('doğru konuma sıralı eklenir', () {
      final items = [
        _item('a', '09:00'),
        _item('c', '15:00'),
      ];
      insertItemSorted(items, _item('b', '12:00'));
      expect(items.map((e) => e.id).toList(), ['a', 'b', 'c']);
    });

    test('mevcut saatler korunur', () {
      final items = [_item('a', '09:00')];
      insertItemSorted(items, _item('b', '08:00'));
      expect(items.map((e) => e.time).toList(), ['08:00', '09:00']);
    });
  });
}
