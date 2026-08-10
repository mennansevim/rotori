// Bütçe hesaplama birim testleri — toTry çevirisi + computeBudget davranışı
// (karışık para birimleri, kişi başı bölme, planlanan vs gerçekleşen yemek,
// boş-maliyet trip'i).

import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/domain/budget.dart';
import 'package:rotori/domain/types.dart';

TimelineItem _item({
  required String id,
  int? cost,
  String? currency,
  TimelineItemKind? kind,
}) =>
    TimelineItem(
      id: id,
      title: id,
      cost: cost,
      costCurrency: currency,
      kind: kind,
    );

Trip _trip({
  required List<DayPlan> days,
  int? partySize,
  int? mealBudgetPerPerson,
  String? mealBudgetCurrency,
}) =>
    Trip(
      id: 't',
      slug: 't',
      title: 'Test',
      timezone: 'Asia/Tokyo',
      tripStart: '2026-07-01',
      tripEnd: '2026-07-03',
      flights: TripFlights(),
      preferences: TripPreferences(
        travelDates: TravelDates(start: '2026-07-01', end: '2026-07-03'),
        pace: Pace.moderate,
        partySize: partySize,
        mealBudgetPerPerson: mealBudgetPerPerson,
        mealBudgetCurrency: mealBudgetCurrency,
      ),
      days: days,
    );

void main() {
  group('toTry', () {
    test('JPY tutarı kurla çarpılır', () {
      expect(toTry(1000, 'JPY', 0.25), 250.0);
    });

    test('null yerine JPY varsayımı çağıran tarafta yapılır; JPY çevirir', () {
      expect(toTry(400, 'jpy', 0.5), 200.0);
    });

    test('TRY/TL aynen kalır', () {
      expect(toTry(500, 'TRY', 0.25), 500.0);
      expect(toTry(500, 'TL', 0.25), 500.0);
    });

    test('bilinmeyen para birimi aynen kalır (zaten görüntülenecek)', () {
      expect(toTry(100, 'USD', 0.25), 100.0);
    });
  });

  group('computeBudget', () {
    test('karışık para birimleri: JPY çevrilir, TL aynen', () {
      final trip = _trip(
        days: [
          DayPlan(
            dayNumber: 1,
            date: '2026-07-01',
            theme: 'Gün 1',
            items: [
              _item(id: 'a', cost: 1000, kind: TimelineItemKind.activity),
              _item(
                id: 'b',
                cost: 200,
                currency: 'TRY',
                kind: TimelineItemKind.transport,
              ),
              _item(id: 'c'), // maliyetsiz
            ],
          ),
        ],
        partySize: 2,
      );
      final s = computeBudget(trip, jpyToTry: 0.25);

      // 1000 JPY * 0.25 = 250 + 200 TRY = 450
      expect(s.grandTotalTry, 450.0);
      // Yalnızca JPY cinsinden ham toplam
      expect(s.grandTotalJpy, 1000);
      expect(s.itemsWithCost, 2);
      expect(s.itemsTotal, 3);
      expect(s.byCategoryTry[TimelineItemKind.activity], 250.0);
      expect(s.byCategoryTry[TimelineItemKind.transport], 200.0);
    });

    test('kişi başı bölme partySize kullanır (min 1)', () {
      final trip = _trip(
        days: [
          DayPlan(
            dayNumber: 1,
            date: '2026-07-01',
            theme: 'Gün 1',
            items: [_item(id: 'a', cost: 4000)],
          ),
        ],
        partySize: 4,
      );
      final s = computeBudget(trip, jpyToTry: 0.25);
      // 4000 * 0.25 = 1000 / 4 = 250
      expect(s.grandTotalTry, 1000.0);
      expect(s.perPersonTry, 250.0);
    });

    test('partySize null → kişi başı = toplam (min 1)', () {
      final trip = _trip(
        days: [
          DayPlan(
            dayNumber: 1,
            date: '2026-07-01',
            theme: 'Gün 1',
            items: [_item(id: 'a', cost: 100, currency: 'TRY')],
          ),
        ],
      );
      final s = computeBudget(trip, jpyToTry: 0.25);
      expect(s.perPersonTry, 100.0);
    });

    test('null kind aktivite sayılır', () {
      final trip = _trip(
        days: [
          DayPlan(
            dayNumber: 1,
            date: '2026-07-01',
            theme: 'Gün 1',
            items: [_item(id: 'a', cost: 100, currency: 'TRY')],
          ),
        ],
      );
      final s = computeBudget(trip, jpyToTry: 0.25);
      expect(s.byCategoryTry[TimelineItemKind.activity], 100.0);
    });

    test('planlanan vs gerçekleşen yemek bütçesi', () {
      final trip = _trip(
        days: [
          DayPlan(
            dayNumber: 1,
            date: '2026-07-01',
            theme: 'Gün 1',
            items: [
              _item(id: 'm1', cost: 2000, kind: TimelineItemKind.meal),
              _item(id: 'a1', cost: 1000, kind: TimelineItemKind.activity),
            ],
          ),
          DayPlan(
            dayNumber: 2,
            date: '2026-07-02',
            theme: 'Gün 2',
            items: [
              _item(id: 'm2', cost: 3000, kind: TimelineItemKind.meal),
            ],
          ),
        ],
        partySize: 2,
        mealBudgetPerPerson: 3000, // JPY (varsayılan)
      );
      final s = computeBudget(trip, jpyToTry: 0.25);

      // gerçekleşen: (2000 + 3000) * 0.25 = 1250
      expect(s.actualMealTry, 1250.0);
      // planlanan: 3000 * 0.25 = 750 per person/day; * 2 kişi * 2 gün = 3000
      expect(s.plannedMealTry, 3000.0);
      // aktivite yemeğe dahil değil
      expect(s.byCategoryTry[TimelineItemKind.meal], 1250.0);
      expect(s.byCategoryTry[TimelineItemKind.activity], 250.0);
    });

    test('mealBudgetPerPerson null → plannedMealTry 0', () {
      final trip = _trip(
        days: [
          DayPlan(
            dayNumber: 1,
            date: '2026-07-01',
            theme: 'Gün 1',
            items: [_item(id: 'm', cost: 1000, kind: TimelineItemKind.meal)],
          ),
        ],
        partySize: 2,
      );
      final s = computeBudget(trip, jpyToTry: 0.25);
      expect(s.plannedMealTry, 0.0);
      expect(s.actualMealTry, 250.0);
    });

    test('boş-maliyet trip: tüm toplamlar sıfır, byDay yine dolu', () {
      final trip = _trip(
        days: [
          DayPlan(
            dayNumber: 1,
            date: '2026-07-01',
            theme: 'Gün 1',
            items: [_item(id: 'a'), _item(id: 'b')],
          ),
        ],
        partySize: 2,
      );
      final s = computeBudget(trip, jpyToTry: 0.25);
      expect(s.grandTotalTry, 0.0);
      expect(s.grandTotalJpy, 0);
      expect(s.itemsWithCost, 0);
      expect(s.itemsTotal, 2);
      expect(s.perPersonTry, 0.0);
      expect(s.byDay.length, 1);
      expect(s.byDay.first.totalTry, 0.0);
    });

    test('byDay her günün çevrilmiş toplamını verir', () {
      final trip = _trip(
        days: [
          DayPlan(
            dayNumber: 1,
            date: '2026-07-01',
            theme: 'Gün 1',
            items: [_item(id: 'a', cost: 1000)],
          ),
          DayPlan(
            dayNumber: 2,
            date: '2026-07-02',
            theme: 'Gün 2',
            items: [_item(id: 'b', cost: 2000)],
          ),
        ],
        partySize: 1,
      );
      final s = computeBudget(trip, jpyToTry: 0.1);
      expect(s.byDay[0].totalTry, 100.0);
      expect(s.byDay[1].totalTry, 200.0);
      expect(s.byDay[0].dayNumber, 1);
      expect(s.byDay[1].date, '2026-07-02');
    });
  });
}
