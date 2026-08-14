// WeatherScreen widget smoke testi — weatherFetcherProvider sahte bir
// fonksiyonla override edilir; böylece yüklenmiş durum AĞ OLMADAN render edilir.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/data/plans_repository.dart';
import 'package:rotori/data/weather_service.dart';
import 'package:rotori/domain/types.dart';
import 'package:rotori/features/viewer/weather_screen.dart';
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

  testWidgets('çok şehirli rotada her gün kendi şehrinin havasını gösterir',
      (tester) async {
    useTallViewport(tester);

    final trip = Trip(
      id: 'trip-multi',
      slug: 'multi',
      title: 'Tokyo + Kyoto',
      timezone: 'Asia/Tokyo',
      tripStart: '2026-10-15',
      tripEnd: '2026-10-18',
      flights: TripFlights(),
      days: [
        DayPlan(dayNumber: 1, date: '2026-10-15', theme: ''),
        DayPlan(dayNumber: 2, date: '2026-10-16', theme: ''),
        DayPlan(dayNumber: 3, date: '2026-10-17', theme: ''),
        DayPlan(dayNumber: 4, date: '2026-10-18', theme: ''),
      ],
      preferences: TripPreferences(
        travelDates: TravelDates(start: '2026-10-15', end: '2026-10-18'),
        pace: Pace.moderate,
        destinations: [
          TripDestination(
            id: 'd-tokyo',
            countryCode: 'JP',
            countryName: 'Japonya',
            city: 'Tokyo',
            arrivalDate: '2026-10-15',
            departureDate: '2026-10-16',
            order: 0,
            lat: 35.68,
            lng: 139.65,
          ),
          TripDestination(
            id: 'd-kyoto',
            countryCode: 'JP',
            countryName: 'Japonya',
            city: 'Kyoto',
            arrivalDate: '2026-10-17',
            departureDate: '2026-10-18',
            order: 1,
            lat: 35.01,
            lng: 135.76,
          ),
        ],
      ),
    );

    // Koordinata göre ayrışan sahte servis: Tokyo 30°, Kyoto 22°.
    Future<List<DayForecast>> fetch(double lat, double lng) async {
      final isTokyo = lat > 35.3;
      return [
        for (final d in const [
          '2026-10-15',
          '2026-10-16',
          '2026-10-17',
          '2026-10-18',
        ])
          DayForecast(
            date: d,
            code: isTokyo ? 0 : 61,
            tempMax: isTokyo ? 30 : 22,
            tempMin: isTokyo ? 20 : 14,
          ),
      ];
    }

    await tester.pumpWidget(harness(trip, fetch: fetch));
    await tester.pumpAndSettle();

    // Başlık rotanın şehir zincirini gösterir.
    expect(find.text('Tokyo  →  Kyoto'), findsOneWidget);

    // Şehirler blok başlığı olarak çıkar (tarih aralığı + gün sayısıyla).
    expect(find.text('Tokyo'), findsOneWidget);
    expect(find.text('Kyoto'), findsOneWidget);
    expect(find.text('15–16 Eki · 2 gün'), findsOneWidget);
    expect(find.text('17–18 Eki · 2 gün'), findsOneWidget);
    // Tek şehirli gezide başlık tekrar edilmez (aşağıdaki testte kanıtlı).

    // Gün satırları şehri tekrar etmez.
    expect(find.text('1. gün'), findsOneWidget);
    expect(find.text('4. gün'), findsOneWidget);
    expect(find.textContaining('· Tokyo'), findsNothing);

    // Asıl invariant: Kyoto günleri Tokyo sıcaklığını göstermez.
    expect(find.text('↑30°'), findsNWidgets(2));
    expect(find.text('↑22°'), findsNWidgets(2));
  });

  testWidgets('tahmin ufku dışındaki gün "Henüz tahmin yok" gösterir',
      (tester) async {
    useTallViewport(tester);

    final trip = _sampleTrip();
    // Servis yalnız ilk günü döndürüyor; 18 ve 19 veri-yok kalmalı.
    Future<List<DayForecast>> fetch(double lat, double lng) async => const [
          DayForecast(
            date: '2026-07-17',
            code: 0,
            tempMax: 31.4,
            tempMin: 24.1,
          ),
        ];

    await tester.pumpWidget(harness(trip, fetch: fetch));
    await tester.pumpAndSettle();

    expect(find.text('↑31°'), findsOneWidget);
    expect(find.text('Henüz tahmin yok'), findsNWidgets(2));

    // Tek şehirli gezide blok başlığı çizilmez — üstteki başlık yeterli.
    expect(find.text('Tokyo'), findsOneWidget);
    expect(find.textContaining('gün', findRichText: false), findsWidgets);
  });
}
