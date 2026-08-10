// Şehir verisi + trip'ten şehir tespiti testleri (React cityPlaces.ts portu).

import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/domain/city_places.dart';
import 'package:rotori/domain/geofence.dart';
import 'package:rotori/domain/types.dart';

Trip _trip({
  String title = 'Japonya',
  List<DayPlan>? days,
  List<HotelStay>? hotels,
}) =>
    Trip(
      id: 't1',
      slug: 't1',
      title: title,
      timezone: 'Asia/Tokyo',
      tripStart: '2026-10-01',
      tripEnd: '2026-10-10',
      flights: TripFlights(),
      preferences: TripPreferences(
        travelDates: TravelDates(start: '2026-10-01', end: '2026-10-10'),
        pace: Pace.moderate,
      ),
      days: days,
      hotels: hotels,
    );

void main() {
  /// React portundan gelen ÇEKİRDEK 7 şehir — bu sayılar port sadakati
  /// sözleşmesidir, değişmemeli. Sonradan eklenen şehirler bu listede yok;
  /// onlar aşağıdaki "yeni şehirler" testiyle korunuyor.
  const reactCounts = {
    'tokyo': 12,
    'kyoto': 10,
    'osaka': 9,
    'nara': 6,
    'hiroshima': 5,
    'sapporo': 5,
    'kanazawa': 5,
  };

  test('çekirdek 7 şehir React referansıyla aynı boyutlarda', () {
    final counts = {
      for (final c in kCityData)
        if (reactCounts.containsKey(c.key)) c.key: c.places.length,
    };
    expect(counts, reactCounts);
  });

  test('sonradan eklenen şehirler de plan üretecek kadar dolu', () {
    final extra =
        kCityData.where((c) => !reactCounts.containsKey(c.key)).toList();
    expect(extra, isNotEmpty, reason: 'test anlamını yitirdi');
    for (final c in extra) {
      expect(c.places.length, greaterThanOrEqualTo(5),
          reason: '${c.label} 5 yerden az — günler zayıf kalır');
      expect(c.aliases, isNotEmpty, reason: '${c.label} alias\'sız');
      // Aynı yer iki kez listelenmesin.
      final ids = c.places.map((p) => p.id).toSet();
      expect(ids.length, c.places.length, reason: '${c.label} yinelenen id');
    }
  });

  test('şehir anahtarları ve yer id\'leri projede tekil', () {
    final keys = kCityData.map((c) => c.key).toList();
    expect(keys.toSet().length, keys.length, reason: 'yinelenen şehir anahtarı');
    final allIds = [for (final c in kCityData) for (final p in c.places) p.id];
    expect(allIds.toSet().length, allIds.length, reason: 'yinelenen yer id');
  });

  test('cityPlacesToGeofences sabitleri uygular (120 m, 600 sn, 25 XP)', () {
    final fences = cityPlacesToGeofences(kCityData);
    // Sabit sayı yerine kaynaktan türet — şehir eklemek bu testi kırmasın.
    final expected =
        kCityData.fold<int>(0, (n, c) => n + c.places.length);
    expect(fences.length, expected);
    for (final f in fences) {
      expect(f.radiusMeters, kPlaceRadiusM);
      expect(f.minDwellSeconds, kDefaultMinDwell);
      expect(f.xp, kPlaceXp);
    }
    // Geofence id'si CityPlace id'siyle aynı (UI eşleşmesi için).
    expect(fences.map((f) => f.id), contains('tk-skytree'));
    expect(fences.map((f) => f.id), contains('kz-21c'));
  });

  test('detectTripCities gün temalarından ilk geçiş sırasına göre bulur', () {
    final trip = _trip(days: [
      DayPlan(dayNumber: 1, date: '2026-10-01', theme: 'Kyoto tapınakları'),
      DayPlan(dayNumber: 2, date: '2026-10-02', theme: 'Tokyo · Asakusa'),
    ]);
    final cities = detectTripCities(trip);
    expect(cities.map((c) => c.key).toList(), ['kyoto', 'tokyo']);
  });

  test('detectTripCities statik sinyalleri (otel/başlık) 999 ile sona koyar',
      () {
    final trip = _trip(
      title: 'Osaka macerası',
      days: [
        DayPlan(dayNumber: 1, date: '2026-10-01', theme: 'Tokyo günü'),
      ],
      hotels: [
        HotelStay(
          id: 'h1',
          city: 'Sapporo',
          name: 'Otel',
          checkIn: '2026-10-01',
          checkOut: '2026-10-03',
          address: '',
        ),
      ],
    );
    final keys = detectTripCities(trip).map((c) => c.key).toList();
    // Gün eşleşmesi önce; statik eşleşmeler (osaka, sapporo) kürasyon
    // sırasıyla sonda.
    expect(keys.first, 'tokyo');
    expect(keys.toSet(), {'tokyo', 'osaka', 'sapporo'});
    expect(keys.indexOf('osaka') < keys.indexOf('sapporo'), isTrue);
  });

  test('detectTripCities eşleşme yoksa boş döner', () {
    final trip = _trip(title: 'Gizemli gezi');
    expect(detectTripCities(trip), isEmpty);
  });

  test('alias eşleşmesi büyük/küçük harf duyarsız', () {
    final trip = _trip(days: [
      DayPlan(dayNumber: 1, date: '2026-10-01', theme: 'HIROSHIMA ve Miyajima'),
    ]);
    expect(detectTripCities(trip).map((c) => c.key), contains('hiroshima'));
  });
}
