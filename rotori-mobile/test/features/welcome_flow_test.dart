// Welcome akışı widget testi — tıklanabilirlik + görünüm geçişlerini doğrular.
// "Kartlara tıklayamıyorum" bug'ını kontrollü ortamda yeniden üretir.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:japan_trip/domain/trip_factory.dart';
import 'package:japan_trip/domain/types.dart';
import 'package:japan_trip/features/planner/planner_theme.dart';
import 'package:japan_trip/features/planner/steps/welcome_step.dart';

void main() {
  Widget harness(Trip trip, {VoidCallback? onContinue}) {
    return MaterialApp(
      theme: PT.theme(),
      home: Scaffold(
        body: WelcomeStep(
          trip: trip,
          onChange: (mutate) => mutate(trip),
          onContinue: onContinue ?? () {},
        ),
      ),
    );
  }

  testWidgets('esnek gezi görünümü doğrudan hedef kartlarını gösterir',
      (tester) async {
    await tester.pumpWidget(harness(createEmptyTrip()));
    expect(find.text("Japonya'da esnek gezi"), findsOneWidget);
    expect(find.text('Tokyo'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Osaka'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Osaka'), findsOneWidget);
  });

  testWidgets('eski bilet tercihini false değerine normalize eder',
      (tester) async {
    final trip = createEmptyTrip();
    trip.preferences.hasTicket = true;
    await tester.pumpWidget(harness(trip));
    await tester.pump();
    expect(trip.preferences.hasTicket, isFalse);
  });

  testWidgets('esnek gezi → tarih aralığına tıklayınca travelDates dolar',
      (tester) async {
    final trip = createEmptyTrip();
    await tester.pumpWidget(harness(trip));

    // Tokyo'nun ilk aralık satırı: 26 Mart · 10 gün · Sakura zirvesi.
    // Yıl: trip.tripStart boşsa now.year+1 → tarih yılı buna göre değişir.
    // Sadece travelDates.start'ın "-03-26" ile bittiğini doğrulamak yeterli.
    final row = find.textContaining('Sakura zirvesi').first;
    await tester.tap(row, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final start = trip.preferences.travelDates.start;
    expect(start.endsWith('-03-26'), isTrue,
        reason: 'travelDates.start beklenen "-03-26" ile bitmiyor: $start');
  });

  testWidgets('kalkış şehri düzenlenebilir', (tester) async {
    final trip = createEmptyTrip();
    await tester.pumpWidget(harness(trip));
    await tester.tap(find.textContaining('İstanbul').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'İzmir');
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();
    expect(trip.preferences.originCity, 'İzmir');
  });

  group('googleFlightsUrl', () {
    test('beklenen deep-link biçimini üretir', () {
      final url = googleFlightsUrl(
        from: 'İzmir',
        toIata: 'NRT',
        start: DateTime(2027, 8, 23),
        end: DateTime(2027, 8, 31),
      );
      // q parametresinin URL-encode edilmesi bekleniyor.
      expect(
        url,
        'https://www.google.com/travel/flights?q='
        '${Uri.encodeComponent('Flights from İzmir to NRT on 2027-08-23 through 2027-08-31')}',
      );
      expect(
          url.startsWith('https://www.google.com/travel/flights?q='), isTrue);
    });
  });

  group('formatTrShortDate', () {
    test('"gün Ay-kısa Gün-kısa" biçiminde döndürür', () {
      // 2026-08-23 → Pazar (Paz)
      expect(formatTrShortDate(DateTime(2026, 8, 23)), '23 Ağu Paz');
      // 2027-08-23 → Pazartesi (Pzt)
      expect(formatTrShortDate(DateTime(2027, 8, 23)), '23 Ağu Pzt');
    });
  });
}
