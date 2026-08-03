// Publish adımı — collectTripWarnings render + "adıma dön" callback + JSON.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:japan_trip/domain/trip_factory.dart';
import 'package:japan_trip/domain/types.dart';
import 'package:japan_trip/features/planner/planner_theme.dart';
import 'package:japan_trip/features/planner/steps.dart';
import 'package:japan_trip/features/planner/steps/publish_step.dart';

Trip _tripWithDest() {
  final t = createEmptyTrip();
  t.preferences.destinations.add(TripDestination(
    id: 'd1',
    countryCode: 'JP',
    countryName: 'Japonya',
    city: 'Tokyo',
    arrivalDate: t.preferences.travelDates.start,
    departureDate: t.preferences.travelDates.end,
    order: 0,
  ));
  return t;
}

void main() {
  Widget harness(Trip trip, {void Function(StepId)? onGoToStep}) => MaterialApp(
        theme: PT.theme(),
        home: Scaffold(
          body: PublishStep(
            trip: trip,
            onChange: (m) => m(trip),
            onGoToStep: onGoToStep,
          ),
        ),
      );

  testWidgets('boş plan + destinasyon → hotels ve plan uyarıları render eder',
      (tester) async {
    final t = _tripWithDest();
    await tester.pumpWidget(harness(t));

    expect(find.text('Yayına hazır'), findsOneWidget);
    // hotels-missing uyarısı
    expect(
        find.textContaining('Henüz otel eklenmedi'), findsOneWidget);
    // plan-empty uyarısı
    expect(find.textContaining('Plan günleri tamamen boş'), findsOneWidget);
  });

  testWidgets('"adıma dön" butonu onGoToStep tetikler', (tester) async {
    final t = _tripWithDest();
    StepId? jumped;
    await tester.pumpWidget(harness(t, onGoToStep: (s) => jumped = s));

    // Konaklama adımına dön butonuna bas.
    final btn = find.text('Konaklama adımına dön →');
    expect(btn, findsOneWidget);
    await tester.ensureVisible(btn);
    await tester.tap(btn);
    await tester.pumpAndSettle();

    expect(jumped, StepId.hotels);
  });

  testWidgets('paylaşılabilir bağlantı kartı artık gösterilmez',
      (tester) async {
    final t = _tripWithDest();
    await tester.pumpWidget(harness(t));
    expect(find.text('Paylaşılabilir bağlantı'), findsNothing);
    expect(find.textContaining('/viewer/?u='), findsNothing);
    // Dışa/İçe aktar kaldırıldı; yalnızca yayın kilidi notu kalır.
    expect(find.text('Dışa aktar'), findsNothing);
    expect(find.text('İçe aktar'), findsNothing);
    expect(find.textContaining('Yayın kilidi'), findsOneWidget);
  });
}
