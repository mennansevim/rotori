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
}
