// Rotori Eats widget smoke testi:
// free listesi + her filtrede görünür premium tanıtımı + paywall açılışı.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:japan_trip/data/plans_repository.dart';
import 'package:japan_trip/domain/eats.dart';
import 'package:japan_trip/domain/types.dart';
import 'package:japan_trip/features/viewer/eats_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Trip _sampleTrip() => Trip(
      id: 'trip-eats',
      slug: 'eats-trip',
      title: 'Eats Test',
      timezone: 'Asia/Tokyo',
      tripStart: '2026-07-01',
      tripEnd: '2026-07-02',
      flights: TripFlights(),
      preferences: TripPreferences(
        travelDates: TravelDates(start: '2026-07-01', end: '2026-07-02'),
        pace: Pace.moderate,
      ),
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  void useTallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 6000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget harness(Trip trip) {
    return ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWith(
          (ref) async => SharedPreferences.getInstance(),
        ),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: EatsScreen(trip: trip),
          ),
        ),
      ),
    );
  }

  testWidgets('Eats bölümü 3 free sonuç + premium tanıtımı gösterir',
      (tester) async {
    useTallViewport(tester);
    await tester.pumpWidget(harness(_sampleTrip()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Restoranlar'), findsOneWidget);

    // Varsayılan helal filtresinde ilk 3 helal mekan gösterilir.
    final halal = filterEats(kEatsPlaces, EatsFilter.halal);
    final shown = halal.take(kEatsFreeLimit).toList();
    for (final place in shown) {
      expect(find.text(place.name), findsOneWidget);
    }

    // Premium upsell her filtrede görünür.
    expect(find.text('Rotori Eats Pass'), findsOneWidget);
    expect(find.text('Hepsini aç'), findsOneWidget);

    // CTA paywall sayfasını açar.
    await tester.ensureVisible(find.text('Hepsini aç'));
    await tester.tap(find.text('Hepsini aç'));
    await tester.pumpAndSettle();
    expect(find.text('Beni haberdar et'), findsOneWidget);
    expect(find.text('Premium ile açılanlar'), findsOneWidget);
  });

  testWidgets('filtre "Hepsi" seçilince restoran listesi değişir',
      (tester) async {
    useTallViewport(tester);
    await tester.pumpWidget(harness(_sampleTrip()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // "Hepsi" filtresine geç.
    await tester.tap(find.text('Hepsi'));
    await tester.pump();

    final all = filterEats(kEatsPlaces, EatsFilter.all);
    expect(find.text(all.first.name), findsOneWidget);
  });
}
