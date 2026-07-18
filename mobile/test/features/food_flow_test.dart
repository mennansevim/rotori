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

  testWidgets('mutfak/beslenme seçimi destinationFood içine upsert eder',
      (tester) async {
    final t = _tripWithDest();
    await tester.pumpWidget(harness(t));

    // Bir önerilen lezzet chip'ine dokun (destinationFood.foodLikes'a yazılır).
    final dishFinder = find.textContaining('Tonkotsu');
    await tester.scrollUntilVisible(
      dishFinder,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(dishFinder.first, warnIfMissed: false);
    await tester.pumpAndSettle();

    final pref = t.preferences.destinationFood
        .where((f) => f.destinationId == 'd1')
        .toList();
    expect(pref, isNotEmpty);
    expect(pref.first.foodLikes, isNotEmpty);
  });

  testWidgets('375px iPhone genişliğinde beslenme/mutfak grid overflow etmez',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 812);
    addTearDown(tester.view.reset);

    final t = _tripWithDest();
    await tester.pumpWidget(harness(t));
    await tester.pumpAndSettle();

    // 2-sütun grid + Wrap render'ları exception fırlatmamalı.
    expect(tester.takeException(), isNull);
    // Scroll ederek grid'in ListView'da inşa edildiğini doğrula
    await tester.scrollUntilVisible(
      find.text('Beslenme tercihleri'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Beslenme tercihleri'), findsOneWidget);
    // GridView 2-sütun kullanılıyor
    final gridViews = tester.widgetList<GridView>(find.byType(GridView));
    expect(gridViews, isNotEmpty);
    expect(tester.takeException(), isNull);
  });
}
