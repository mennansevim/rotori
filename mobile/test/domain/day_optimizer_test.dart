// packages/shared/src/__tests__/resequenceTimes.test.ts'in birebir Dart eşdeğeri.
// 5 test — TS'te geçen davranış Dart'ta da geçmeli.

import 'package:flutter_test/flutter_test.dart';
import 'package:japan_trip/domain/day_optimizer.dart';
import 'package:japan_trip/domain/types.dart';

TimelineItem _item(
  String id,
  String time, {
  TimelineItemKind kind = TimelineItemKind.activity,
}) =>
    TimelineItem(
      id: id,
      title: id,
      kind: kind,
      time: time.isEmpty ? null : time,
      scheduledTime: time.isEmpty ? null : time,
    );

void main() {
  group('resequenceTimes', () {
    test('mevcut saatleri yeni sıraya göre kronolojik dağıtır', () {
      // Kullanıcı öğle yemeğini (13:00) tapınağın (10:00) üstüne sürükledi.
      final dragged = [_item('lunch', '13:00'), _item('temple', '10:00')];
      final out = resequenceTimes(dragged);
      // Sıra korunur, saatler yukarıdan aşağı artan.
      expect(out.map((i) => i.id).toList(), ['lunch', 'temple']);
      expect(out.map((i) => i.time).toList(), ['10:00', '13:00']);
      expect(out.map((i) => i.scheduledTime).toList(), ['10:00', '13:00']);
    });

    test('üç kalemi yeni sıraya göre yeniden zamanlar', () {
      final items = [
        _item('c', '18:00'),
        _item('a', '09:00'),
        _item('b', '12:30'),
      ];
      final out = resequenceTimes(items);
      expect(out.map((i) => i.id).toList(), ['c', 'a', 'b']);
      expect(out.map((i) => i.time).toList(), ['09:00', '12:30', '18:00']);
    });

    test('zaten sıralıysa aynı referansları döndürür', () {
      final items = [_item('a', '10:00'), _item('b', '14:00')];
      final out = resequenceTimes(items);
      expect(identical(out[0], items[0]), isTrue);
      expect(identical(out[1], items[1]), isTrue);
    });

    test('saatsiz kalemlere dokunmaz, saatlileri kendi arasında sıralar', () {
      final noTime = _item('x', '');
      final items = [_item('late', '16:00'), noTime, _item('early', '08:00')];
      final out = resequenceTimes(items);
      expect(out.map((i) => i.id).toList(), ['late', 'x', 'early']);
      expect(out[0].time, '08:00'); // late pozisyonu en erken saati aldı
      expect(identical(out[1], noTime), isTrue); // saatsiz aynen kaldı
      expect(out[2].time, '16:00');
    });

    test('hiç saat yoksa diziyi olduğu gibi bırakır', () {
      final items = [_item('a', ''), _item('b', '')];
      final out = resequenceTimes(items);
      expect(identical(out, items), isTrue);
    });
  });

  group('timeToMin / minToTime', () {
    test('temel dönüşümler', () {
      expect(timeToMin('09:00'), 540);
      expect(timeToMin('13:30'), 810);
      expect(timeToMin(''), -1);
      expect(timeToMin(null), -1);
      expect(timeToMin('bad'), -1);
      expect(minToTime(540), '09:00');
      expect(minToTime(810), '13:30');
      expect(minToTime(0), '00:00');
    });
  });
}
