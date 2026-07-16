// DayMapScreen smoke testi — örnek bir trip ile hatasız build olur.
// Tile'ların gerçekten yüklenmesi gerekmez; sadece widget ağacı kurulur.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:japan_trip/data/plans_repository.dart';
import 'package:japan_trip/domain/types.dart';
import 'package:japan_trip/features/viewer/day_map_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ağ isteği yapmadan 1x1 saydam PNG döndüren test tile sağlayıcısı.
class _FakeTileProvider extends TileProvider {
  static final Uint8List _pngBytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
    'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
  );

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return MemoryImage(_pngBytes);
  }
}

Trip _sampleTrip() {
  return Trip(
    id: 'trip-1',
    slug: 'test-trip',
    title: 'Japonya Test',
    timezone: 'Asia/Tokyo',
    tripStart: '2026-05-13',
    tripEnd: '2026-05-16',
    flights: TripFlights(),
    preferences: TripPreferences(
      travelDates: TravelDates(start: '2026-05-13', end: '2026-05-16'),
      pace: Pace.moderate,
      destinations: [
        TripDestination(
          id: 'd1',
          countryCode: 'JP',
          countryName: 'Japonya',
          city: 'Tokyo',
          lat: 35.6762,
          lng: 139.6503,
          arrivalDate: '2026-05-13',
          departureDate: '2026-05-16',
          order: 0,
        ),
      ],
    ),
    days: [
      DayPlan(
        dayNumber: 1,
        date: '2026-05-13',
        theme: 'Tokyo keşfi',
        items: [
          TimelineItem(id: 'a', title: 'Tokyo Skytree', time: '10:00'),
          TimelineItem(id: 'b', title: 'Shibuya Crossing', time: '13:00'),
        ],
      ),
    ],
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget harness(Trip trip, int dayNumber) {
    return ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWith(
          (ref) async => SharedPreferences.getInstance(),
        ),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: DayMapScreen(
              trip: trip,
              dayNumber: dayNumber,
              tileProvider: _FakeTileProvider(),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('koordinatlı günde harita + pinlerle hatasız build olur',
      (tester) async {
    await tester.pumpWidget(harness(_sampleTrip(), 1));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(FlutterMap), findsOneWidget);
    // İki durak → iki numaralı pin.
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    // Başlık şehir adını içerir.
    expect(find.textContaining('Tokyo'), findsWidgets);
  });

  testWidgets('konumlu durağı olmayan günde boş mesaj gösterilir',
      (tester) async {
    final trip = _sampleTrip();
    trip.days = [
      DayPlan(
        dayNumber: 2,
        date: '2026-05-14',
        theme: 'Boş gün',
        items: [
          TimelineItem(id: 'z', title: 'Uydurma Yer Xyz'),
        ],
      ),
    ];
    await tester.pumpWidget(harness(trip, 2));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      find.text('Bu güne haritada gösterilecek konumlu durak yok.'),
      findsOneWidget,
    );
  });
}
