// Rotori uyum skorunun girdileri GERÇEKTEN toplanıyor mu?
//
// Kusur şuydu: skor diyet + bütçe girdilerine dayanıyordu ama uygulama
// ikisini de hiçbir yerde sormuyordu. `mealBudgetJpyPerPerson` hiçbir ekran
// tarafından yazılmıyor, `dietaryTags` de hiç toplanmayan
// `foodSensitivities`'ten türetiliyordu. Sonuç: herkeste aynı çıkan,
// nötr dolgudan ibaret bir "65/100".
//
// Bu test iki şeyi korur:
//   1) girdiler yokken arayüz bunu SÖYLER (sessizce nötr puan vermez),
//   2) kullanıcı girdileri doldurabilir ve seçim trip.preferences'a yazılır.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:japan_trip/data/plans_repository.dart';
import 'package:japan_trip/domain/eats.dart';
import 'package:japan_trip/domain/eats_query.dart';
import 'package:japan_trip/domain/types.dart';
import 'package:japan_trip/features/viewer/eats_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Trip _trip({List<String> tags = const [], int? budget}) => Trip(
      id: 'trip-pers',
      slug: 'pers',
      title: 'Personalization',
      timezone: 'Asia/Tokyo',
      tripStart: '2026-07-01',
      tripEnd: '2026-07-02',
      flights: TripFlights(),
      preferences: TripPreferences(
        travelDates: TravelDates(start: '2026-07-01', end: '2026-07-02'),
        pace: Pace.moderate,
        dietaryTags: tags,
        mealBudgetJpyPerPerson: budget,
      ),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  void tallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 9000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget harness(Trip trip) => ProviderScope(
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

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
  }

  testWidgets('girdiler yokken ekran kişiselleştirilemediğini söyler',
      (tester) async {
    tallViewport(tester);
    await tester.pumpWidget(harness(_trip()));
    await settle(tester);

    expect(find.text('Öneriler henüz sana göre değil'), findsOneWidget);
  });

  testWidgets('girdiler dolu olduğunda uyarı kaybolur', (tester) async {
    tallViewport(tester);
    await tester.pumpWidget(harness(_trip(tags: ['halal'], budget: 3000)));
    await settle(tester);

    expect(find.text('Öneriler henüz sana göre değil'), findsNothing);
  });

  testWidgets('uyarıya dokununca tercih sheet\'i açılır ve seçim kaydedilir',
      (tester) async {
    tallViewport(tester);
    final trip = _trip();
    await tester.pumpWidget(harness(trip));
    await settle(tester);

    await tester.tap(find.text('Öneriler henüz sana göre değil'));
    await tester.pumpAndSettle();

    expect(find.text('Sana göre önerebilmem için'), findsOneWidget);

    // Helal + ¥3,000 seç, kaydet. Tam metinle eşleştiriyoruz: arkadaki
    // listede "Helal sertifikalı" rozetleri de var, textContaining onları
    // yakalardı.
    await tester.tap(find.text('🕌 Helal'));
    await tester.pump();
    await tester.tap(find.text('≤ ¥3,000'));
    await tester.pump();
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();

    // Seçim trip.preferences'a yazıldı — skorun girdisi artık GERÇEK.
    expect(trip.preferences.dietaryTags, contains('halal'));
    expect(trip.preferences.mealBudgetJpyPerPerson, 3000);

    // Uyarı kayboldu.
    expect(find.text('Öneriler henüz sana göre değil'), findsNothing);
  });

  testWidgets('detay sheet\'inde eksik sinyaller "eksik" olarak gösterilir',
      (tester) async {
    tallViewport(tester);
    // Skor kırılımı premium bloğunun içinde — açık olmalı.
    SharedPreferences.setMockInitialValues({'debug_premium': true});
    await tester.pumpWidget(harness(_trip()));
    await settle(tester);

    final first = runEatsQuery(kEatsPlaces, tier: EatsTier.premium).first;
    await tester.tap(find.text(first.place.name));
    await tester.pumpAndSettle();

    // Nötr sayı yerine dürüst durum.
    expect(find.text('Henüz kişiselleştirilemiyor'), findsOneWidget);
    expect(find.text('eksik'), findsWidgets);
    expect(
      find.text('Skoru keskinleştirmek için eksik olanlar'),
      findsOneWidget,
    );
  });

  testWidgets('girdiler dolunca detayda gerçek skor ve sinyal sayısı çıkar',
      (tester) async {
    tallViewport(tester);
    SharedPreferences.setMockInitialValues({'debug_premium': true});
    final trip = _trip(tags: ['halal'], budget: 3000);
    await tester.pumpWidget(harness(trip));
    await settle(tester);

    final first = runEatsQuery(
      kEatsPlaces,
      query: const EatsQuery(minHalal: HalalTrust.muslimFriendly),
      tier: EatsTier.premium,
    ).first;
    await tester.tap(find.text(first.place.name));
    await tester.pumpAndSettle();

    expect(find.text('Henüz kişiselleştirilemiyor'), findsNothing);
    // 4 sinyalden 3'ü biliniyor (konum kapalı).
    expect(find.text('3/4 sinyal'), findsOneWidget);
  });
}
