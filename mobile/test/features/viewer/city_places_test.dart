// Şehir verisi + trip'ten şehir tespiti testleri (React cityPlaces.ts portu).

import 'package:flutter_test/flutter_test.dart';
import 'package:japan_trip/domain/city_places.dart';
import 'package:japan_trip/domain/geofence.dart';
import 'package:japan_trip/domain/types.dart';

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
  test('CITY_DATA React referansıyla aynı boyutlarda', () {
    expect(kCityData.length, 7);
    final counts = {for (final c in kCityData) c.key: c.places.length};
    expect(counts, {
      'tokyo': 12,
      'kyoto': 10,
      'osaka': 10,
      'nara': 6,
      'hiroshima': 5,
      'sapporo': 5,
      'kanazawa': 5,
    });
  });

  test('cityPlacesToGeofences sabitleri uygular (120 m, 600 sn, 25 XP)', () {
    final fences = cityPlacesToGeofences(kCityData);
    expect(fences.length, 12 + 10 + 10 + 6 + 5 + 5 + 5);
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
