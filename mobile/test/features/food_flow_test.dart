// Food adımı — hassasiyet toggle → dietaryTags persist + destinationFood upsert.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:japan_trip/domain/trip_factory.dart';
import 'package:japan_trip/domain/types.dart';
import 'package:japan_trip/features/planner/planner_theme.dart';
import 'package:japan_trip/features/planner/steps/food_step.dart';

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
  Widget harness(Trip trip) => MaterialApp(
        theme: PT.theme(),
        home: Scaffold(
          body: FoodStep(trip: trip, onChange: (m) => m(trip)),
        ),
      );

  testWidgets('destinasyon yoksa uyarı gösterir', (tester) async {
    await tester.pumpWidget(harness(createEmptyTrip()));
    expect(find.text('Önce Rota adımında durak ekleyin.'), findsOneWidget);
  });

  testWidgets('hassasiyet toggle → foodSensitivities + dietaryTags persist',
      (tester) async {
    final t = _tripWithDest();
    await tester.pumpWidget(harness(t));

    expect(find.text('Yemek tercihleri'), findsOneWidget);

    // "Domuz eti istemiyorum" hassasiyetine tıkla.
    await tester.tap(find.text('🚫🐖 Domuz eti istemiyorum'));
    await tester.pumpAndSettle();

    expect(t.preferences.foodSensitivities.contains(FoodSensitivity.noPork),
        isTrue);
    // dietaryTagsFromSensitivities → 'no_pork'
    expect(t.preferences.dietaryTags.contains('no_pork'), isTrue);

    // Tekrar tıkla → kaldırır.
    await tester.tap(find.text('🚫🐖 Domuz eti istemiyorum'));
    await tester.pumpAndSettle();
    expect(t.preferences.foodSensitivities.contains(FoodSensitivity.noPork),
        isFalse);
    expect(t.preferences.dietaryTags.contains('no_pork'), isFalse);
  });

  testWidgets('destinasyon başına mutfak/lezzet grid'
      ' artık render edilmez — sadece hassasiyet + bütçe kalır', (tester) async {
    final t = _tripWithDest();
    await tester.pumpWidget(harness(t));
    await tester.pumpAndSettle();

    // Kaldırılan bölümler görünmemeli.
    expect(find.textContaining('Beslenme tercihleri'), findsNothing);
    expect(find.textContaining('Mutfak türleri'), findsNothing);
    expect(find.textContaining('Önerilen lezzetler'), findsNothing);
    // Bütçe alanı hala var.
    expect(find.textContaining('Kişi başı öğün'), findsOneWidget);
    expect(find.text('Öğünleri plana ekle'), findsOneWidget);
  });

  testWidgets('375px iPhone genişliğinde hassasiyet wrap overflow etmez',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 812);
    addTearDown(tester.view.reset);

    final t = _tripWithDest();
    await tester.pumpWidget(harness(t));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // PCardTitle metni upper-case'e çevirir → 'YEMEK HASSASIYETLERI' fragment ara.
    expect(find.textContaining('YEMEK HASSASIYETLERI'), findsOneWidget);
  });
}
