// rules.dart (TS packages/shared/src/rules.ts portu) davranış testleri:
// collectTripWarnings + tekil kontroller + moveItemBetweenDays.

import 'package:flutter_test/flutter_test.dart';
import 'package:japan_trip/domain/rules.dart';
import 'package:japan_trip/domain/types.dart';

Trip _trip({
  String title = 'Japonya Turu',
  List<DayPlan>? days,
  List<HotelStay>? hotels,
  List<TripDestination>? destinations,
  List<String>? mustSee,
  Deadlines? deadlines,
}) =>
    Trip(
      id: 't1',
      slug: 'test',
      title: title,
      timezone: 'Asia/Tokyo',
      tripStart: '2026-10-01T08:00:00',
      tripEnd: '2026-10-05T20:00:00',
      flights: TripFlights(),
      preferences: TripPreferences(
        travelDates: TravelDates(start: '2026-10-01', end: '2026-10-05'),
        pace: Pace.moderate,
        destinations: destinations,
        mustSee: mustSee,
      ),
      hotels: hotels,
      days: days,
      deadlines: deadlines,
    );

DayPlan _day(int n, {List<TimelineItem>? items, int? steps, int? stepsMax}) =>
    DayPlan(
      dayNumber: n,
      date: '2026-10-0$n',
      theme: '',
      tags: [],
      stepsEstimate: steps,
      stepsEstimateMax: stepsMax,
      items: items ?? [],
    );

TripDestination _dest() => TripDestination(
      id: 'd1',
      countryCode: 'JP',
      countryName: 'Japonya',
      city: 'Tokyo',
      arrivalDate: '2026-10-01',
      departureDate: '2026-10-05',
      order: 0,
    );

void main() {
  group('checkStepsOverLimit', () {
    test('limit aşımında tr-TR biçimli uyarı üretir', () {
      final w = checkStepsOverLimit(_day(1, steps: 15000), 12000);
      expect(w, isNotNull);
      expect(w!.severity, TripWarningSeverity.warn);
      expect(
        w.message,
        'Gün 1: tahmini 15.000 adım, limit 12.000. Taksi veya aktivite azaltmayı düşünün.',
      );
      expect(w.dayNumber, 1);
      expect(w.step, 'plan');
    });

    test('limit yoksa veya aşım yoksa null', () {
      expect(checkStepsOverLimit(_day(1, steps: 15000), null), isNull);
      expect(checkStepsOverLimit(_day(1, steps: 9000), 12000), isNull);
    });

    test('stepsEstimateMax öncelikli', () {
      final w = checkStepsOverLimit(_day(1, steps: 9000, stepsMax: 13000), 12000);
      expect(w, isNotNull);
    });
  });

  group('checkShinkansenDeadline', () {
    final now = DateTime(2026, 10, 1);

    test('geçmiş deadline → urgent', () {
      final w = checkShinkansenDeadline('2026-09-30', now: now);
      expect(w?.severity, TripWarningSeverity.urgent);
      expect(w?.message,
          'Shinkansen rezervasyon penceresi geçti veya bugün son gün.');
    });

    test('30 gün içindeyse → warn ve gün sayısı', () {
      final w = checkShinkansenDeadline('2026-10-11', now: now);
      expect(w?.severity, TripWarningSeverity.warn);
      expect(w?.message, 'Shinkansen rezervasyonuna 10 gün kaldı.');
    });

    test('uzak deadline veya boş → null', () {
      expect(checkShinkansenDeadline('2026-12-25', now: now), isNull);
      expect(checkShinkansenDeadline(null, now: now), isNull);
    });
  });

  group('collectTripWarnings', () {
    test('boş plan + varsayılan başlık uyarıları', () {
      final trip = _trip(days: [_day(1), _day(2)]);
      final warnings = collectTripWarnings(trip);
      final ids = warnings.map((w) => w.id).toList();
      expect(ids, contains('plan-empty'));
      expect(ids, contains('title-default'));
    });

    test('destinasyon var ama otel yok → hotels-missing', () {
      final trip = _trip(destinations: [_dest()]);
      final ids = collectTripWarnings(trip).map((w) => w.id);
      expect(ids, contains('hotels-missing'));
    });

    test('eksik otel bilgisi → hotels-incomplete', () {
      final trip = _trip(
        destinations: [_dest()],
        hotels: [
          HotelStay(
            id: 'h1',
            city: 'Tokyo',
            name: '',
            checkIn: '2026-10-01',
            checkOut: '2026-10-05',
            address: 'Adres 1',
          ),
        ],
      );
      final w = collectTripWarnings(trip)
          .where((w) => w.id == 'hotels-incomplete')
          .first;
      expect(w.message, '1 otel için şehir, ad veya açık adres eksik.');
      expect(w.step, 'hotels');
    });

    test('plana eklenmemiş mustSee → info uyarısı', () {
      final trip = _trip(
        title: 'Özel Gezim',
        mustSee: ['Fushimi Inari', 'Skytree'],
        days: [
          _day(1, items: [
            TimelineItem(id: 'i1', title: '🗼 Tokyo Skytree'),
          ]),
        ],
      );
      final warnings = collectTripWarnings(trip);
      final mustSeeWarnings =
          warnings.where((w) => w.id.startsWith('mustsee-')).toList();
      expect(mustSeeWarnings, hasLength(1));
      expect(mustSeeWarnings.first.message,
          '"Fushimi Inari" henüz günlük plana eklenmemiş.');
      expect(mustSeeWarnings.first.severity, TripWarningSeverity.info);
    });

    test('özel başlık + dolu plan → bu uyarılar yok', () {
      final trip = _trip(
        title: 'Balayı Rotası',
        days: [
          _day(1, items: [TimelineItem(id: 'i1', title: 'Bir şey')]),
        ],
      );
      final ids = collectTripWarnings(trip).map((w) => w.id).toList();
      expect(ids, isNot(contains('plan-empty')));
      expect(ids, isNot(contains('title-default')));
    });
  });

  group('moveItemBetweenDays', () {
    List<DayPlan> makeDays() => [
          _day(1, items: [
            TimelineItem(id: 'i1', title: 'A'),
            TimelineItem(id: 'i2', title: 'B'),
          ]),
          _day(2, items: [TimelineItem(id: 'i3', title: 'C')]),
        ];

    test('öğeyi taşır ve movedFromDay işaretler', () {
      final days = makeDays();
      final next = moveItemBetweenDays(days, 'i1', 1, 2);
      expect(next[0].items.map((i) => i.id), ['i2']);
      expect(next[1].items.map((i) => i.id), ['i3', 'i1']);
      expect(next[1].items.last.movedFromDay, 1);
      // Orijinal liste değişmedi.
      expect(days[0].items, hasLength(2));
    });

    test('aynı güne taşıma no-op', () {
      final days = makeDays();
      expect(identical(moveItemBetweenDays(days, 'i1', 1, 1), days), isTrue);
    });

    test('öğe bulunamazsa orijinali döndürür', () {
      final days = makeDays();
      expect(identical(moveItemBetweenDays(days, 'yok', 1, 2), days), isTrue);
    });

    test('gün bulunamazsa orijinali döndürür', () {
      final days = makeDays();
      expect(identical(moveItemBetweenDays(days, 'i1', 1, 9), days), isTrue);
    });
  });

  group('suggestTaxiForDay', () {
    test('adım limiti aşımında true', () {
      final prefs = TripPreferences(
        travelDates: TravelDates(start: '2026-10-01', end: '2026-10-05'),
        pace: Pace.moderate,
        maxStepsPerDay: 10000,
      );
      expect(suggestTaxiForDay(_day(1, steps: 12000), prefs), isTrue);
      expect(suggestTaxiForDay(_day(1, steps: 8000), prefs), isFalse);
    });
  });
}
