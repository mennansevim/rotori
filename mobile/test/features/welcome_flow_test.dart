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

  testWidgets('choose görünümü hero + 2 kartı gösterir', (tester) async {
    await tester.pumpWidget(harness(createEmptyTrip()));
    expect(find.text("Japonya'yı planlayalım"), findsOneWidget);
    expect(find.text('Biletim var'), findsOneWidget);
    expect(find.text('Gezi planla'), findsOneWidget);
  });

  testWidgets('"Biletim var" kartına tıklayınca bilet formu açılır',
      (tester) async {
    final trip = createEmptyTrip();
    await tester.pumpWidget(harness(trip));

    await tester.tap(find.text('Biletim var'));
    await tester.pumpAndSettle();

    // Bilet görünümüne geçmeli
    expect(find.text('Bilet bilgilerin'), findsOneWidget);
    expect(find.text('Gidiş tarihi'), findsOneWidget);
    // hasTicket işaretlenmeli
    expect(trip.preferences.hasTicket, isTrue);
  });

  testWidgets('"Gezi planla" kartına tıklayınca esnek gezi görünümü açılır',
      (tester) async {
    final trip = createEmptyTrip();
    await tester.pumpWidget(harness(trip));

    await tester.tap(find.text('Gezi planla'));
    await tester.pumpAndSettle();

    // Yeni Google Flights tarzı başlık + iki hedef kartı
    expect(find.text("Japonya'da esnek gezi"), findsOneWidget);
    expect(find.text('Tokyo'), findsOneWidget);
    // Osaka kartı alta düşer — scroll ile bulunur.
    await tester.scrollUntilVisible(
      find.text('Osaka'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Osaka'), findsOneWidget);
    expect(trip.preferences.hasTicket, isFalse);
  });

  testWidgets('esnek gezi → tarih aralığına tıklayınca travelDates dolar',
      (tester) async {
    final trip = createEmptyTrip();
    await tester.pumpWidget(harness(trip));

    await tester.tap(find.text('Gezi planla'));
    await tester.pumpAndSettle();

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

  testWidgets('bilet formu → geri butonu choose görünümüne döner',
      (tester) async {
    await tester.pumpWidget(harness(createEmptyTrip()));
    await tester.tap(find.text('Biletim var'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('← Geri'));
    await tester.pumpAndSettle();
    expect(find.text("Japonya'yı planlayalım"), findsOneWidget);
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
      expect(url.startsWith('https://www.google.com/travel/flights?q='), isTrue);
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
