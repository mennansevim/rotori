// Maliyet tahmincisi birim testleri — INI ayrıştırma, gömülü varsayılan,
// kalem kalem min–max, mevsim/tek-yön çarpanları ve aile senaryosu.

import 'package:flutter_test/flutter_test.dart';
import 'package:japan_trip/domain/cost_estimate.dart';
import 'package:japan_trip/domain/types.dart';

Trip _trip({
  int? partySize,
  int? childrenCount,
  String start = '2026-05-01',
  String end = '2026-05-10',
  int dayCount = 10,
  bool roundTrip = true,
  List<String>? cityIds,
}) {
  final days = [
    for (var i = 1; i <= dayCount; i++)
      DayPlan(dayNumber: i, date: start, theme: 'Gün $i'),
  ];
  return Trip(
    id: 't',
    slug: 't',
    title: 'Test',
    timezone: 'Asia/Tokyo',
    tripStart: start,
    tripEnd: end,
    flights: TripFlights(
      outbound: [],
      returnLegs: roundTrip
          ? [FlightLeg(city: 'Tokyo', airport: 'NRT', dateTime: end)]
          : [],
    ),
    preferences: TripPreferences(
      travelDates: TravelDates(start: start, end: end),
      pace: Pace.moderate,
      partySize: partySize,
      childrenCount: childrenCount,
      selectedCityIds: cityIds,
    ),
    days: days,
  );
}

void main() {
  group('UnitCostTable.parseIni', () {
    test('kısmi INI gömülü varsayılan üstüne yazar', () {
      final t = UnitCostTable.parseIni('''
[flight]
adult_min = 100000
[reference]
ramen = 1200
''');
      expect(t.flightAdultMin, 100000);
      // Belirtilmeyen alan varsayılandan gelir.
      expect(t.flightAdultMax, UnitCostTable.defaults().flightAdultMax);
      expect(t.references.any((r) => r.key == 'ramen' && r.jpy == 1200), isTrue);
    });

    test('yorum satırları ve satır içi yorum yok sayılır', () {
      final t = UnitCostTable.parseIni('''
; yorum
# başka yorum
[season]
high_months = 4,5  ; sadece nisan-mayıs
high_factor = 1,20
''');
      expect(t.highMonths, {4, 5});
      expect(t.highFactor, 1.20);
    });
  });

  group('UnitCostTable.fromSections (Supabase yolu)', () {
    test('section haritasından tablo kurar, eksikler varsayılandan gelir', () {
      final t = UnitCostTable.fromSections({
        'flight': {'adult_min': '100000'},
        'reference': {'ramen': '1300'},
      });
      expect(t.flightAdultMin, 100000);
      expect(t.flightAdultMax, UnitCostTable.defaults().flightAdultMax);
      expect(t.references.any((r) => r.key == 'ramen' && r.jpy == 1300), isTrue);
    });

    test('INI ve fromSections aynı sonucu verir', () {
      const ini = '''
[flight]
adult_min = 90000
[season]
high_months = 5
''';
      final a = UnitCostTable.parseIni(ini);
      final b = UnitCostTable.fromSections({
        'flight': {'adult_min': '90000'},
        'season': {'high_months': '5'},
      });
      expect(a.flightAdultMin, b.flightAdultMin);
      expect(a.highMonths, b.highMonths);
    });
  });

  group('estimateTripCost', () {
    test('sekiz kategori üretir ve toplam = satırların toplamı', () {
      final e = estimateTripCost(_trip(partySize: 2), UnitCostTable.defaults());
      expect(e.lines.length, 8);
      var min = 0;
      var max = 0;
      for (final l in e.lines) {
        expect(l.minJpy <= l.maxJpy, isTrue);
        min += l.minJpy;
        max += l.maxJpy;
      }
      expect(e.totalMinJpy, min);
      expect(e.totalMaxJpy, max);
      expect(e.totalMinJpy <= e.totalMaxJpy, isTrue);
    });

    test('yetişkin/çocuk ayrımı ve gün sayısı doğru', () {
      final e = estimateTripCost(
        _trip(partySize: 3, childrenCount: 1, dayCount: 10),
        UnitCostTable.defaults(),
      );
      expect(e.adults, 2);
      expect(e.children, 1);
      expect(e.days, 10);
      expect(e.nights, 9);
    });

    test('tek yön uçuş gidiş-dönüşten ucuzdur', () {
      final table = UnitCostTable.defaults();
      final round = estimateTripCost(_trip(partySize: 2, roundTrip: true), table);
      final oneWay =
          estimateTripCost(_trip(partySize: 2, roundTrip: false), table);
      final roundFlight = round.lines
          .firstWhere((l) => l.category == CostCategory.flight)
          .minJpy;
      final oneWayFlight = oneWay.lines
          .firstWhere((l) => l.category == CostCategory.flight)
          .minJpy;
      expect(oneWayFlight < roundFlight, isTrue);
      expect(oneWay.oneWay, isTrue);
    });

    test('yüksek sezon (Mayıs) otel/uçağı düşük sezondan pahalılaştırır', () {
      final table = UnitCostTable.defaults();
      final may = estimateTripCost(
        _trip(partySize: 2, start: '2026-05-01', end: '2026-05-10'),
        table,
      );
      final feb = estimateTripCost(
        _trip(partySize: 2, start: '2026-02-01', end: '2026-02-10'),
        table,
      );
      final mayHotel =
          may.lines.firstWhere((l) => l.category == CostCategory.hotel).minJpy;
      final febHotel =
          feb.lines.firstWhere((l) => l.category == CostCategory.hotel).minJpy;
      expect(mayHotel > febHotel, isTrue);
    });

    test('3 kişilik aile 10 gün Mayıs — gerçekçi aralık', () {
      final e = estimateTripCost(
        _trip(partySize: 3, childrenCount: 1, dayCount: 10),
        UnitCostTable.defaults(),
      );
      // Toplam pozitif ve makul bir üst sınırın altında (JPY).
      expect(e.totalMinJpy > 300000, isTrue);
      expect(e.totalMaxJpy < 2000000, isTrue);
    });
  });
}
