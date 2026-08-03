// computeNextActivity — pure hesaplama birim testleri.
//
// Kurallar (home_widget_hook.dart yorumundan):
//   1) Tüm günlerin tüm item'ları arasında `now`'dan sonraki (>=) ilki.
//   2) Bulunamazsa aktif günün ilk item'ı.
//   3) Yine yoksa null.
//   4) daysUntilTripStart — gezi başladıysa 0, aksi hâlde farkın gün sayısı.

import 'package:flutter_test/flutter_test.dart';
import 'package:japan_trip/domain/types.dart';
import 'package:japan_trip/features/viewer/home_widget_hook.dart';

TimelineItem _item(String id, {String? time, TimelineItemKind? kind}) =>
    TimelineItem(id: id, title: id, time: time, kind: kind);

Trip _trip({
  required List<DayPlan> days,
  String tripStart = '2026-07-01',
  String tripEnd = '2026-07-05',
  String title = 'Tokyo Trip',
}) =>
    Trip(
      id: 't',
      slug: 't',
      title: title,
      timezone: 'Asia/Tokyo',
      tripStart: tripStart,
      tripEnd: tripEnd,
      flights: TripFlights(),
      preferences: TripPreferences(
        travelDates: TravelDates(start: tripStart, end: tripEnd),
        pace: Pace.moderate,
      ),
      days: days,
    );

void main() {
  group('computeNextActivity', () {
    test('past + future karışımı → ilk future item seçilir', () {
      final trip = _trip(days: [
        DayPlan(
          dayNumber: 1,
          date: '2026-07-01',
          theme: 'Tokyo',
          items: [
            _item('breakfast', time: '08:00', kind: TimelineItemKind.meal),
            _item('museum', time: '11:00', kind: TimelineItemKind.activity),
            _item('dinner', time: '19:00', kind: TimelineItemKind.meal),
          ],
        ),
        DayPlan(
          dayNumber: 2,
          date: '2026-07-02',
          theme: 'Kyoto',
          items: [
            _item('shrine', time: '09:00', kind: TimelineItemKind.activity),
          ],
        ),
      ]);

      // now = 2026-07-01 10:00 → breakfast geçmişte, museum ilk future.
      final now = DateTime(2026, 7, 1, 10);
      final n = computeNextActivity(trip, now);
      expect(n, isNotNull);
      expect(n!.title, 'museum');
      expect(n.time, '11:00');
      expect(n.emoji, '📍');
      expect(n.city, 'Tokyo');
      expect(n.tripTitle, 'Tokyo Trip');
      expect(n.daysUntilTripStart, 0); // gezi başladı
    });

    test('gün sınırını aşar → sonraki günün item\'ı seçilir', () {
      final trip = _trip(days: [
        DayPlan(
          dayNumber: 1,
          date: '2026-07-01',
          theme: 'Tokyo',
          items: [_item('lunch', time: '12:00', kind: TimelineItemKind.meal)],
        ),
        DayPlan(
          dayNumber: 2,
          date: '2026-07-02',
          theme: 'Kyoto',
          items: [
            _item('shrine', time: '09:00', kind: TimelineItemKind.activity),
          ],
        ),
      ]);
      // now = 2026-07-01 20:00 → tüm gün 1 geçmiş, ertesi gün ilk item.
      final now = DateTime(2026, 7, 1, 20);
      final n = computeNextActivity(trip, now);
      expect(n?.title, 'shrine');
      expect(n?.city, 'Kyoto');
    });

    test('tümü geçmişte → aktif günün ilk itemına düşer', () {
      final trip = _trip(days: [
        DayPlan(
          dayNumber: 1,
          date: '2026-07-01',
          theme: 'Tokyo',
          items: [
            _item('lunch', time: '12:00', kind: TimelineItemKind.meal),
            _item('dinner', time: '19:00', kind: TimelineItemKind.meal),
          ],
        ),
      ]);
      // now = gezi bitiminden sonra → aktif = son gün → ilk item.
      final now = DateTime(2026, 7, 2, 8);
      final n = computeNextActivity(trip, now);
      expect(n?.title, 'lunch');
      expect(n?.city, 'Tokyo');
      expect(n?.emoji, '🍜');
    });

    test('items boş → null', () {
      final trip = _trip(days: [
        DayPlan(dayNumber: 1, date: '2026-07-01', theme: 'Tokyo', items: []),
      ]);
      final n = computeNextActivity(trip, DateTime(2026, 7, 1, 10));
      expect(n, isNull);
    });

    test('days boş → null', () {
      final trip = _trip(days: []);
      final n = computeNextActivity(trip, DateTime(2026, 6, 1));
      expect(n, isNull);
    });

    test('daysUntilTripStart — gezi öncesi doğru gün farkı', () {
      final trip = _trip(
        tripStart: '2026-07-10',
        tripEnd: '2026-07-15',
        days: [
          DayPlan(
            dayNumber: 1,
            date: '2026-07-10',
            theme: 'Tokyo',
            items: [_item('arrive', time: '10:00')],
          ),
        ],
      );
      // now = 2026-07-01 00:00 → 9 gün var.
      final now = DateTime(2026, 7, 1);
      final n = computeNextActivity(trip, now);
      expect(n?.title, 'arrive');
      expect(n?.daysUntilTripStart, 9);
    });

    test('daysUntilTripStart — gezi başladıysa 0', () {
      final trip = _trip(
        tripStart: '2026-07-01',
        days: [
          DayPlan(
            dayNumber: 1,
            date: '2026-07-01',
            theme: 'Tokyo',
            items: [_item('lunch', time: '13:00')],
          ),
        ],
      );
      final n = computeNextActivity(trip, DateTime(2026, 7, 1, 12));
      expect(n?.daysUntilTripStart, 0);
    });

    test('saatsiz item → günün başı sayılır, geleceği kaçırmaz', () {
      final trip = _trip(days: [
        DayPlan(
          dayNumber: 1,
          date: '2026-07-01',
          theme: 'Tokyo',
          items: [_item('checkin')], // time yok
        ),
      ]);
      // now önce → item bugünün başlangıcı; nowdan sonra kabul edilmez, dolayısıyla
      // aktif gün fallback devreye girer, aynı item döner.
      final n = computeNextActivity(trip, DateTime(2026, 7, 1, 5));
      expect(n?.title, 'checkin');
    });
  });
}
