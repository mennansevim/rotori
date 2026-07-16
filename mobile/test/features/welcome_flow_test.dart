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

  testWidgets('"Gezi planla" kartına tıklayınca mevsim görünümü açılır',
      (tester) async {
    final trip = createEmptyTrip();
    await tester.pumpWidget(harness(trip));

    await tester.tap(find.text('Gezi planla'));
    await tester.pumpAndSettle();

    // Başlık ekranda görünür
    expect(find.text("Japonya'da hangi mevsim?"), findsOneWidget);
    // "Önerilen..." aşağıda — scroll ile bul
    await tester.scrollUntilVisible(
      find.text('Önerilen 2 haftalık aralıklar'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Önerilen 2 haftalık aralıklar'), findsOneWidget);
    expect(trip.preferences.hasTicket, isFalse);
  });

  testWidgets('mevsim → bir öneri aralığına tıklayınca onContinue tetiklenir',
      (tester) async {
    var continued = false;
    final trip = createEmptyTrip();
    await tester.pumpWidget(harness(trip, onContinue: () => continued = true));

    await tester.tap(find.text('Gezi planla'));
    await tester.pumpAndSettle();

    // İlk önerilen aralık kartına scroll edip tıkla
    final rangeCard = find.text('Ekim 2026 — Sonbahar başlangıcı');
    await tester.scrollUntilVisible(
      rangeCard,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(rangeCard);
    await tester.pumpAndSettle();

    expect(continued, isTrue);
    // Tarihler uygulanmalı
    expect(trip.preferences.travelDates.start, '2026-10-15');
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
}
