// Çok şehirli (Tokyo + Kyoto) uçtan uca plan üretimi regresyon testi.
// Bug: seçilen ikinci şehir (Kyoto) plana girmiyor, Tokyo içeriği tekrarlıyor,
// şehirler-arası geçiş eklenmiyordu. Bu test o senaryoyu kilitler.

import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/core/l10n.dart';
import 'package:rotori/domain/city_transfers.dart';
import 'package:rotori/domain/destination_profiles.dart';
import 'package:rotori/domain/fill_empty_days.dart';
import 'package:rotori/domain/itinerary_generator.dart';
import 'package:rotori/domain/trip_factory.dart';
import 'package:rotori/domain/types.dart';

TripDestination _dest(String city, int order, String arr, String dep,
        {String airport = ''}) =>
    TripDestination(
      id: 'd$order',
      countryCode: 'JP',
      countryName: 'Japonya',
      city: city,
      airport: airport,
      arrivalDate: arr,
      departureDate: dep,
      order: order,
    );

const _tokyoPlaceNames = [
  'Senso-ji',
  'Skytree',
  'Shibuya',
  'Meiji',
  'teamLab',
  'Disneyland',
  'Ginza',
  'Akihabara',
  'Ueno',
  'Odaiba',
  'Tsukiji',
];
const _kyotoPlaceNames = [
  'Fushimi',
  'Kinkaku',
  'Arashiyama',
  'Kiyomizu',
  'Gion',
  'Nijo',
  'Ginkaku',
  'Pontocho',
  'Nishiki',
  'Tofuku',
];

bool _mentionsAny(String title, List<String> names) =>
    names.any((n) => title.toLowerCase().contains(n.toLowerCase()));

void main() {
  group('çok şehirli plan (Tokyo → Kyoto)', () {
    late Trip trip;

    setUp(() {
      trip = createEmptyTrip();
      // Tokyo 10-01..10-04, Kyoto 10-04..10-06 (distributeDates çıktısına eş).
      trip.preferences.destinations = [
        _dest('Tokyo', 0, '2026-10-01', '2026-10-04', airport: 'HND'),
        _dest('Kyoto', 1, '2026-10-04', '2026-10-06'),
      ];
      trip.preferences.travelDates =
          TravelDates(start: '2026-10-01', end: '2026-10-06');
      trip.tripStart = '2026-10-01T08:00:00';
      trip.tripEnd = '2026-10-06T20:00:00';
      trip.days = generateDaysBetween('2026-10-01', '2026-10-06');
    });

    List<DayPlan> generate() {
      var days = generateItineraryFromTrip(trip, lang: AppLang.tr);
      days = fillEmptyDays(days, trip.preferences.destinations, lang: AppLang.tr);
      days = applyCityTransitions(days, trip.preferences.destinations);
      return days;
    }

    String cityOf(DayPlan d) =>
        getDestinationForDate(trip.preferences.destinations, d.date)?.city ?? '';

    test('hem Tokyo hem Kyoto günleri üretilir (Kyoto düşmez)', () {
      final days = generate();
      final cities = days.map(cityOf).toSet();
      expect(cities.contains('Tokyo'), isTrue, reason: 'Tokyo günleri olmalı');
      expect(cities.contains('Kyoto'), isTrue,
          reason: 'Kyoto günleri de olmalı — düşmemeli');
    });

    test('Kyoto gününde Tokyo mekanı YOK; Tokyo gününde Kyoto mekanı YOK', () {
      final days = generate();
      for (final d in days) {
        final city = cityOf(d);
        for (final it in d.items) {
          // Geçiş (Shinkansen) item'ı "Tokyo → Kyoto" içerdiğinden hariç.
          if (it.title.contains('→')) continue;
          if (city == 'Kyoto') {
            expect(_mentionsAny(it.title, _tokyoPlaceNames), isFalse,
                reason: 'Kyoto günü Tokyo mekanı içeriyor: ${it.title}');
          }
          if (city == 'Tokyo') {
            expect(_mentionsAny(it.title, _kyotoPlaceNames), isFalse,
                reason: 'Tokyo günü Kyoto mekanı içeriyor: ${it.title}');
          }
        }
      }
    });

    test('Kyoto günü gerçek Kyoto içeriği barındırır', () {
      final days = generate();
      final kyotoDays = days.where((d) => cityOf(d) == 'Kyoto').toList();
      final hasKyotoContent = kyotoDays.any(
          (d) => d.items.any((it) => _mentionsAny(it.title, _kyotoPlaceNames)));
      expect(hasKyotoContent, isTrue,
          reason: 'En az bir Kyoto günü Kyoto mekanı içermeli');
    });

    test('aktivite/yemek item cityId, günün şehriyle eşleşir', () {
      final days = generate();
      for (final d in days) {
        final city = cityOf(d);
        if (city.isEmpty) continue;
        for (final it in d.items) {
          if (it.title.contains('→')) continue; // transfer item hariç
          if (it.cityId == null || it.cityId!.isEmpty) continue;
          expect(it.cityId, city,
              reason: '${d.date} günü item cityId (${it.cityId}) '
                  'şehirle ($city) uyuşmuyor: ${it.title}');
        }
      }
    });

    test('Tokyo → Kyoto geçişi (Shinkansen transfer) eklenir', () {
      final days = generate();
      final transfers = days
          .expand((d) => d.items)
          .where((it) =>
              it.kind == TimelineItemKind.transport && it.title.contains('→'))
          .toList();
      expect(transfers, isNotEmpty,
          reason: 'Şehirler-arası geçiş item’ı bulunmalı');
      expect(transfers.first.title.toLowerCase(), contains('kyoto'));
    });
  });
}
