// JourneyStep widget testi — render + rota veri girişi + Continue koşulu.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:japan_trip/domain/trip_factory.dart';
import 'package:japan_trip/domain/types.dart';
import 'package:japan_trip/features/planner/planner_theme.dart';
import 'package:japan_trip/features/planner/steps/journey_step.dart';

void main() {
  Widget harness(Trip trip) => MaterialApp(
        theme: PT.theme(),
        home: Scaffold(
          body: JourneyStep(trip: trip, onChange: (m) => m(trip)),
        ),
      );

  testWidgets('render + otomatik Tokyo destinasyonu kurulur', (tester) async {
    final trip = createEmptyTrip();
    await tester.pumpWidget(harness(trip));
    await tester.pumpAndSettle(); // postFrame auto-init

    expect(find.text('🇯🇵 Japonya rotası'), findsOneWidget);
    // otomatik Tokyo destinasyonu
    expect(trip.preferences.destinations.length, 1);
    expect(trip.preferences.destinations.first.city, 'Tokyo');
    // Havayolu / kalkış / varış alanları görünür
    expect(find.text('Havayolu'), findsOneWidget);
    expect(find.text('Kalkış (Türkiye)'), findsOneWidget);
    expect(find.text('Varış (Japonya)'), findsOneWidget);
  });

  testWidgets('havaalanı picker modal açılır ve seçim origin\'i doldurur',
      (tester) async {
    final trip = createEmptyTrip();
    await tester.pumpWidget(harness(trip));
    await tester.pumpAndSettle();

    // Kalkış picker'ına dokun (placeholder metniyle bul)
    await tester.tap(find.textContaining('İstanbul (IST)').first);
    await tester.pumpAndSettle();

    // Modal açıldı — arama kutusu + IST listesi
    expect(find.text('Havaalanı seç'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'IST');
    await tester.pumpAndSettle();
    await tester.tap(find.text('İstanbul').first);
    await tester.pumpAndSettle();

    expect(trip.preferences.originAirport, 'IST');
    expect(trip.preferences.originCity, 'İstanbul');
  });

  testWidgets('rota önizleme origin + Tokyo gösterir', (tester) async {
    final trip = createEmptyTrip();
    // origin'i baştan set et
    trip.preferences
      ..originCity = 'İstanbul'
      ..originAirport = 'IST';
    await tester.pumpWidget(harness(trip));
    await tester.pumpAndSettle();

    // origin picker etiketi + arrival picker etiketi
    expect(find.textContaining('İstanbul'), findsWidgets);
    expect(find.textContaining('Tokyo'), findsWidgets);
    // Continue koşulu: origin + Tokyo destinasyonu → true
    expect(trip.preferences.originAirport, 'IST');
    expect(trip.preferences.destinations.first.city, 'Tokyo');
  });

  testWidgets('şehir sayısı promptu render edilir ve 375px\'te overflow olmaz',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 812);
    addTearDown(tester.view.reset);

    final trip = createEmptyTrip();
    await tester.pumpWidget(harness(trip));
    await tester.pumpAndSettle();

    expect(find.text('📍 Kaç şehir gezeceksin?'), findsOneWidget);
    expect(find.text('1 şehir'), findsOneWidget);
    expect(find.text('2 şehir'), findsOneWidget);
    expect(find.text('3 şehir'), findsOneWidget);
    expect(find.text('4+'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('2+ şehir seçilirse Shinkansen hatırlatması görünür',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 812);
    addTearDown(tester.view.reset);

    final trip = createEmptyTrip();
    await tester.pumpWidget(harness(trip));
    await tester.pumpAndSettle();

    // Başlangıçta 1 destinasyon (auto Tokyo) → Shinkansen görünmemeli
    expect(find.textContaining('Şehirler arası Shinkansen'), findsNothing);

    // "2 şehir" chip'ine tıkla → Shinkansen kartı çıkmalı
    await tester.tap(find.text('2 şehir'));
    await tester.pumpAndSettle();

    // ListView içinde aşağıda olabilir — scroll ederek doğrula
    await tester.scrollUntilVisible(
      find.textContaining('Şehirler arası Shinkansen'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('Şehirler arası Shinkansen'), findsOneWidget);
    // Şehir seçici de görünmeli (hint yerine kullanıcı listeden seçer).
    await tester.scrollUntilVisible(
      find.text('🏙️ Gezilecek şehirler'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('🏙️ Gezilecek şehirler'), findsOneWidget);
  });

  testWidgets('destinations.length >= 2 iken Shinkansen otomatik çıkar',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 812);
    addTearDown(tester.view.reset);

    final trip = createEmptyTrip();
    trip.preferences.destinations.addAll([
      TripDestination(
        id: 'd1',
        countryCode: 'JP',
        countryName: 'Japonya',
        city: 'Tokyo',
        airport: 'HND',
        arrivalDate: trip.preferences.travelDates.start,
        departureDate: trip.preferences.travelDates.end,
        order: 0,
      ),
      TripDestination(
        id: 'd2',
        countryCode: 'JP',
        countryName: 'Japonya',
        city: 'Kyoto',
        airport: 'ITM',
        arrivalDate: trip.preferences.travelDates.start,
        departureDate: trip.preferences.travelDates.end,
        order: 1,
      ),
    ]);
    await tester.pumpWidget(harness(trip));
    await tester.pumpAndSettle();

    // ListView'de aşağıda — kaydırarak görünür yap
    await tester.scrollUntilVisible(
      find.textContaining('Şehirler arası Shinkansen'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('Şehirler arası Shinkansen'), findsOneWidget);
  });
}
