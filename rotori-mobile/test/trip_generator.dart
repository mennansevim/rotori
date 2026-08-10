// Property-based test yardımcısı — Japonya rotalarının kombinasyonlarını
// üreterek trip generation kurallarını (gün bölme, uçuş sync, aktarma) toplu
// biçimde denetler.
//
// Kullanım (test dosyalarında):
//   for (final tv in tripVariations()) {
//     final trip = makeTrip(tv);
//     // assertions...
//   }
//
// Kombinasyon = (dateWindow × cityCombo). Toplam ~ dateWindows.length ×
// cityCombos.length. Manifest üzerinden iterasyon eder — yani her koşumda
// aynı 50+ trip taranır. Random değil, deterministik.

import 'package:rotori/domain/types.dart';

/// Farklı tarih pencereleri — sakura (Nisan), Golden Week (Mayıs), yaz
/// (Ağustos), sonbahar (Ekim), kış (Aralık/Ocak). Trip start/end ISO.
const dateWindows = <DateWindow>[
  DateWindow('sakura', '2026-04-01', '2026-04-08'), // 7 gün
  DateWindow('goldenweek', '2026-05-03', '2026-05-10'), // 7 gün
  DateWindow('yaz', '2026-08-01', '2026-08-14'), // 13 gün
  DateWindow('sonbahar', '2026-10-15', '2026-10-22'), // 7 gün
  DateWindow('yilbasi', '2026-12-27', '2027-01-05'), // 9 gün
  DateWindow('kis-tokyo', '2026-01-05', '2026-01-11'), // 6 gün
  DateWindow('kisa-kacamak', '2026-06-14', '2026-06-17'), // 3 gün
  DateWindow('uzun-tatil', '2026-07-15', '2026-08-04'), // 20 gün
];

/// Şehir kombinasyonları — 1..5 şehirli çeşitli rotalar. Her biri bir örnek
/// (ör: Tokyo-Kyoto). Airport'lu şehirler uçuş bacağı, olmayanlar tren
/// aktarma olur.
const cityCombos = <List<CitySpec>>[
  // 1 şehir
  [CitySpec('tokyo', 'Tokyo', 'HND')],
  [CitySpec('kyoto', 'Kyoto', null)],
  [CitySpec('osaka', 'Osaka', 'KIX')],
  // 2 şehir — klasik
  [CitySpec('tokyo', 'Tokyo', 'HND'), CitySpec('kyoto', 'Kyoto', null)],
  [CitySpec('tokyo', 'Tokyo', 'HND'), CitySpec('osaka', 'Osaka', 'KIX')],
  [CitySpec('kyoto', 'Kyoto', null), CitySpec('nara', 'Nara', null)],
  // 3 şehir
  [
    CitySpec('tokyo', 'Tokyo', 'HND'),
    CitySpec('kyoto', 'Kyoto', null),
    CitySpec('osaka', 'Osaka', 'KIX'),
  ],
  [
    CitySpec('tokyo', 'Tokyo', 'HND'),
    CitySpec('hakone', 'Hakone', null),
    CitySpec('kyoto', 'Kyoto', null),
  ],
  // 4 şehir
  [
    CitySpec('tokyo', 'Tokyo', 'HND'),
    CitySpec('kyoto', 'Kyoto', null),
    CitySpec('nara', 'Nara', null),
    CitySpec('osaka', 'Osaka', 'KIX'),
  ],
  // 5 şehir — uzun rota
  [
    CitySpec('tokyo', 'Tokyo', 'HND'),
    CitySpec('hakone', 'Hakone', null),
    CitySpec('kyoto', 'Kyoto', null),
    CitySpec('nara', 'Nara', null),
    CitySpec('osaka', 'Osaka', 'KIX'),
  ],
];

class DateWindow {
  const DateWindow(this.label, this.start, this.end);
  final String label;
  final String start;
  final String end;

  int get days {
    final s = DateTime.parse(start);
    final e = DateTime.parse(end);
    return e.difference(s).inDays + 1;
  }
}

class CitySpec {
  const CitySpec(this.id, this.city, this.airport);
  final String id;
  final String city;
  final String? airport;
}

class TripVariation {
  const TripVariation({required this.window, required this.cities, required this.label});
  final DateWindow window;
  final List<CitySpec> cities;
  final String label;
}

Iterable<TripVariation> tripVariations() sync* {
  for (final w in dateWindows) {
    for (final c in cityCombos) {
      yield TripVariation(
        window: w,
        cities: c,
        label: '${w.label} · ${c.map((x) => x.id).join('-')}',
      );
    }
  }
}

/// Bir TripVariation'dan gerçek Trip nesnesi kurar. Uçuşlar: ilk şehir HND
/// veya KIX üzerinden IST-XX gidiş; son şehir üzerinden XX-IST dönüş. Şehir
/// arası aktarmalar ihmal (unit test odak: gün dağılımı, tarihler).
Trip makeTripFromVariation(TripVariation v) {
  final destinations = <TripDestination>[];
  for (var i = 0; i < v.cities.length; i++) {
    final c = v.cities[i];
    destinations.add(TripDestination(
      id: c.id,
      city: c.city,
      countryCode: 'JP',
      countryName: 'Japan',
      arrivalDate: v.window.start,
      departureDate: v.window.end,
      order: i,
      airport: c.airport,
    ));
  }
  final entryAirport = v.cities.firstWhere((c) => c.airport != null,
      orElse: () => v.cities.first);
  final exitAirport = v.cities.lastWhere((c) => c.airport != null,
      orElse: () => entryAirport);
  return Trip(
    id: 'trip-${v.label}',
    slug: v.label,
    title: '${v.window.label.toUpperCase()} · ${v.cities.map((c) => c.city).join(' → ')}',
    timezone: 'Asia/Tokyo',
    tripStart: v.window.start,
    tripEnd: v.window.end,
    flights: TripFlights(
      outbound: [
        FlightLeg(
          city: entryAirport.city,
          airport: entryAirport.airport ?? 'NRT',
          dateTime: '${v.window.start}T10:00:00',
        ),
      ],
      returnLegs: [
        FlightLeg(
          city: exitAirport.city,
          airport: exitAirport.airport ?? 'NRT',
          dateTime: '${v.window.end}T20:00:00',
        ),
      ],
    ),
    preferences: TripPreferences(
      travelDates: TravelDates(start: v.window.start, end: v.window.end),
      pace: Pace.moderate,
      destinations: destinations,
    ),
  );
}
