// WeatherScreen widget smoke testi — weatherFetcherProvider sahte bir
// fonksiyonla override edilir; böylece yüklenmiş durum AĞ OLMADAN render edilir.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:japan_trip/data/plans_repository.dart';
import 'package:japan_trip/data/weather_service.dart';
import 'package:japan_trip/domain/types.dart';
import 'package:japan_trip/features/viewer/weather_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Trip _sampleTrip() => Trip(
      id: 'trip-w',
      slug: 'weather-trip',
      title: 'Hava Test',
      timezone: 'Asia/Tokyo',
      tripStart: '2026-07-17',
      tripEnd: '2026-07-19',
      flights: TripFlights(),
      preferences: TripPreferences(
        travelDates: TravelDates(start: '2026-07-17', end: '2026-07-19'),
        pace: Pace.moderate,
        destinations: [
          TripDestination(
            id: 'd1',
            countryCode: 'JP',
            countryName: 'Japonya',
            city: 'Tokyo',
            arrivalDate: '2026-07-17',
            departureDate: '2026-07-19',
            order: 0,
            lat: 35.68,
            lng: 139.65,
          ),
        ],
      ),
    );

List<DayForecast> _fakeForecast() => const [
      DayForecast(
        date: '2026-07-17',
        code: 0,
        tempMax: 31.4,
        tempMin: 24.1,
        precipProb: 10,
      ),
      DayForecast(
        date: '2026-07-18',
        code: 61,
        tempMax: 28.0,
        tempMin: 22.5,
        precipProb: 80,
      ),
    ];

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  void useTallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget harness(Trip trip, {required ForecastFetcher fetch}) {
    return ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWith(
          (ref) async => SharedPreferences.getInstance(),
        ),
        weatherFetcherProvider.overrideWithValue(fetch),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: WeatherScreen(trip: trip),
          ),
        ),
      ),
    );
  }

  testWidgets('sahte tahmin ile yüklenmiş durum render edilir', (tester) async {
    useTallViewport(tester);
    await tester.pumpWidget(
      harness(_sampleTrip(), fetch: (lat, lng) async => _fakeForecast()),
    );
    // FutureProvider'ın çözülmesi için pump.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('🌤️ Hava Durumu'), findsOneWidget);
    expect(find.text('Tokyo'), findsOneWidget);
    // İlk günün etiketi (kod 0 → Açık) ve sıcaklıkları.
    expect(find.text('Açık'), findsOneWidget);
    expect(find.text('↑31°'), findsOneWidget);
    expect(find.text('💧80%'), findsOneWidget);
    expect(find.text('Kaynak: Open-Meteo'), findsOneWidget);
  });

  testWidgets('hata durumunda mesaj + Tekrar dene gösterilir', (tester) async {
    useTallViewport(tester);
    await tester.pumpWidget(
      harness(
        _sampleTrip(),
        fetch: (lat, lng) async => throw const WeatherException('boom'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.text('Hava durumu alınamadı — internet bağlantısını kontrol et'),
      findsOneWidget,
    );
    expect(find.text('Tekrar dene'), findsOneWidget);
  });
}
