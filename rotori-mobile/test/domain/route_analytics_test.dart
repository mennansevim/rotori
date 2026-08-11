import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/domain/route_analytics.dart';
import 'package:rotori/domain/trip_factory.dart';
import 'package:rotori/domain/types.dart';

void main() {
  test('request JSON yalnız plan üretim girdilerini taşır', () {
    final json = RouteAnalyticsSnapshot.request(
      cityKeys: const ['tokyo', 'kyoto'],
      startYmd: '2026-10-01',
      endYmd: '2026-10-08',
      datesEstimated: false,
      dayOverrides: const {'tokyo': 4, 'kyoto': 4},
      dietaryTags: const ['halal'],
      mealBudgetJpyPerPerson: 2500,
      language: 'tr',
    );

    expect(json['schemaVersion'], 1);
    expect(json['cityKeys'], ['tokyo', 'kyoto']);
    expect(json['dayOverrides'], {'tokyo': 4, 'kyoto': 4});
    expect(json['dietaryTagCount'], 1);
    expect(json['hasMealBudget'], isTrue);
    expect(json, isNot(contains('dietaryTags')));
    expect(json, isNot(contains('mealBudgetJpyPerPerson')));
  });

  test('route JSON uçuş, otel, bilet ve serbest metni dışarıda bırakır', () {
    final trip = createEmptyTrip();
    trip
      ..title = 'Kişisel gezi başlığı'
      ..subtitle = 'Özel not'
      ..hotels = [
        HotelStay(
          id: 'hotel-1',
          city: 'Tokyo',
          name: 'Özel otel',
          checkIn: trip.tripStart,
          checkOut: trip.tripEnd,
          address: 'Özel adres',
          phone: '+81 00 0000',
        ),
      ]
      ..days = [
        DayPlan(
          dayNumber: 1,
          date: trip.tripStart,
          theme: 'Asakusa',
          items: [
            TimelineItem(
              id: 'sensoji',
              title: 'Sensō-ji',
              description: 'Kullanıcının özel açıklaması',
              tips: 'Kullanıcının özel notu',
              mapUrl: 'https://maps.example/private',
              lat: 35.7148,
              lng: 139.7967,
              durationMin: 90,
            ),
          ],
        ),
      ];

    final json = RouteAnalyticsSnapshot.route(trip);
    final encoded = jsonEncode(json);

    expect(json, isNot(contains('title')));
    expect(json, isNot(contains('subtitle')));
    expect(json, isNot(contains('flights')));
    expect(json, isNot(contains('hotels')));
    expect(json, isNot(contains('tickets')));
    expect(encoded, isNot(contains('Özel adres')));
    expect(encoded, isNot(contains('+81 00 0000')));
    expect(encoded, isNot(contains('Kullanıcının özel')));
    expect(encoded, contains('Sensō-ji'));
    expect(encoded, contains('35.7148'));
  });

  test('metrics gün, aktivite ve rota bacağı sayılarını türetir', () {
    final trip = createEmptyTrip()
      ..days = [
        DayPlan(
          dayNumber: 1,
          date: '2026-10-01',
          theme: 'Tokyo',
          items: [
            TimelineItem(id: 'a', title: 'A'),
            TimelineItem(id: 'b', title: 'B'),
          ],
        ),
      ];

    final metrics = RouteAnalyticsSnapshot.metrics(trip, elapsedMs: 123);

    expect(metrics['elapsedMs'], 123);
    expect(metrics['dayCount'], 1);
    expect(metrics['activityCount'], 2);
    expect(metrics['routeLegCount'], 0);
    expect(metrics['estimatedLegCount'], 0);
    expect(metrics['totalTravelMinutes'], 0);
  });
}
