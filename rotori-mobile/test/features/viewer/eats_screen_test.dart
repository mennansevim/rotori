// Rotori Eats ekranı widget testleri.
//
// Kapsam: ücretsiz katman sınırı, detaylı filtre popup'ı ve içindeki kilitler,
// premium açıkken açılan yetenekler ve "güvenlik bilgisi asla kilitlenmez"
// kuralı.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:japan_trip/data/plans_repository.dart';
import 'package:japan_trip/domain/eats.dart';
import 'package:japan_trip/domain/eats_query.dart';
import 'package:japan_trip/domain/types.dart';
import 'package:japan_trip/features/viewer/eats_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Trip _sampleTrip({List<String> dietaryTags = const []}) => Trip(
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
        dietaryTags: dietaryTags,
      ),
    );

/// Ekran "şu anki öğün"ü Japonya yerel saatinden türetir; test de aynı
/// hesabı yapmalı ki beklenen öneriler tutsun.
int japanHourForTest() =>
    DateTime.now().toUtc().add(const Duration(hours: 9)).hour;

void main() {
  void useTallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 9000);
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

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
  }

  group('ücretsiz katman', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('arama + filtre çubuğu ve ücretsiz rozeti görünür',
        (tester) async {
      useTallViewport(tester);
      await tester.pumpWidget(harness(_sampleTrip()));
      await settle(tester);

      expect(find.text('Filtre'), findsOneWidget);
      expect(find.text('Ücretsiz'), findsOneWidget);
      expect(find.text('Şimdi ne yesem?'), findsOneWidget);
    });

    testWidgets('sonuç sayısı ücretsiz limitle sınırlanır ve bu söylenir',
        (tester) async {
      useTallViewport(tester);
      await tester.pumpWidget(harness(_sampleTrip()));
      await settle(tester);

      final all = runEatsQuery(kEatsPlaces, tier: EatsTier.free);
      expect(all.length, greaterThan(kEatsFreeVisibleLimit));

      // Başlık "N sonuçtan M tanesi" biçiminde kırpmayı açıkça söyler.
      expect(
        find.text('${all.length} sonuçtan $kEatsFreeVisibleLimit tanesi'),
        findsOneWidget,
      );

      // İlk kEatsFreeVisibleLimit mekan görünür, sonraki görünmez.
      for (final r in all.take(kEatsFreeVisibleLimit)) {
        expect(find.text(r.place.name), findsOneWidget, reason: r.place.id);
      }
      expect(find.text(all[kEatsFreeVisibleLimit].place.name), findsNothing);
    });

    testWidgets('premium tanıtım kartı ve paywall açılır', (tester) async {
      useTallViewport(tester);
      await tester.pumpWidget(harness(_sampleTrip()));
      await settle(tester);

      expect(find.text('Rotori Eats Pass'), findsOneWidget);
      await tester.ensureVisible(find.text('Hepsini aç'));
      await tester.tap(find.text('Hepsini aç'));
      await tester.pumpAndSettle();

      expect(find.text('Premium ile açılanlar'), findsOneWidget);
      expect(find.text('Beni haberdar et'), findsOneWidget);
      // Paywall ücretsiz katmanın ne verdiğini de dürüstçe söyler.
      expect(find.text('Ücretsiz katmanda ne var?'), findsOneWidget);
    });

    testWidgets('"Şimdi ne yesem?" kilitli — dokununca paywall açar',
        (tester) async {
      useTallViewport(tester);
      await tester.pumpWidget(harness(_sampleTrip()));
      await settle(tester);

      await tester.tap(find.text('Şimdi ne yesem?'));
      await tester.pumpAndSettle();
      expect(find.text('Premium ile açılanlar'), findsOneWidget);
    });
  });

  group('detaylı filtre popup', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('açılır, ücretsiz eksenler açık, premium eksenler kilitli',
        (tester) async {
      useTallViewport(tester);
      await tester.pumpWidget(harness(_sampleTrip()));
      await settle(tester);

      await tester.tap(find.text('Filtre'));
      await tester.pumpAndSettle();

      expect(find.text('Detaylı filtre'), findsOneWidget);
      // Ücretsiz eksenler
      expect(find.text('Helal güveni'), findsOneWidget);
      expect(find.text('Vejetaryen / vegan'), findsOneWidget);
      expect(find.text('Şehir'), findsOneWidget);
      // Premium eksenler kilit rozetiyle görünür (gizlenmez).
      expect(find.text('Mutfak'), findsOneWidget);
      expect(find.text('Kişi başı fiyat'), findsOneWidget);
      expect(find.widgetWithText(Container, 'Pass'), findsWidgets);
    });

    testWidgets('ücretsiz eksende seçim listeyi daraltır', (tester) async {
      useTallViewport(tester);
      await tester.pumpWidget(harness(_sampleTrip()));
      await settle(tester);

      await tester.tap(find.text('Filtre'));
      await tester.pumpAndSettle();

      // Şehir = Kyoto
      await tester.tap(find.text('Kyoto'));
      await tester.pumpAndSettle();

      final expected = runEatsQuery(
        kEatsPlaces,
        query: const EatsQuery(cities: {'Kyoto'}),
        tier: EatsTier.free,
      );
      await tester.tap(find.text('${expected.length} sonucu göster'));
      await tester.pumpAndSettle();

      // Filtre butonu aktif sayacı gösterir ve liste Kyoto'ya daralır.
      expect(find.text('1'), findsWidgets);
      expect(find.text(expected.first.place.name), findsOneWidget);
    });

    testWidgets('kilitli eksene dokunmak paywall açar', (tester) async {
      useTallViewport(tester);
      await tester.pumpWidget(harness(_sampleTrip()));
      await settle(tester);

      await tester.tap(find.text('Filtre'));
      await tester.pumpAndSettle();

      // Kilitli bölümün gövdesi IgnorePointer içindedir; dokunuşu yakalayan
      // sarmalayıcı GestureDetector'dır — testin de onu hedeflemesi gerekir.
      final lockedSection = find
          .ancestor(
            of: find.text('Mutfak'),
            matching: find.byType(GestureDetector),
          )
          .first;
      await tester.ensureVisible(lockedSection);
      await tester.pumpAndSettle();
      await tester.tap(lockedSection);
      await tester.pumpAndSettle();

      expect(find.text('Premium ile açılanlar'), findsOneWidget);
    });
  });

  group('premium katman', () {
    setUp(() => SharedPreferences.setMockInitialValues({'debug_premium': true}));

    testWidgets('kırpma kalkar, Pass rozeti ve Rotori Seçkisi görünür',
        (tester) async {
      useTallViewport(tester);
      await tester.pumpWidget(harness(_sampleTrip()));
      await settle(tester);

      expect(find.text('Pass aktif'), findsOneWidget);

      final all = runEatsQuery(kEatsPlaces, tier: EatsTier.premium);
      expect(find.text('${all.length} sonuç'), findsOneWidget);

      // Yalnızca premium'da görünen küratörlü kayıt listeye girer.
      final curated = kEatsPlaces.firstWhere((p) => p.premiumOnly);
      expect(find.text(curated.name), findsOneWidget);

      // Upsell kartı premium'da gösterilmez.
      expect(find.text('Hepsini aç'), findsNothing);
    });

    testWidgets('"Şimdi ne yesem?" 3 gerekçeli öneri sheet\'i açar',
        (tester) async {
      useTallViewport(tester);
      await tester.pumpWidget(harness(_sampleTrip()));
      await settle(tester);

      await tester.tap(find.text('Şimdi ne yesem?'));
      await tester.pumpAndSettle();

      // Başlıkta emoji ile metin birleşik render edilir.
      expect(find.textContaining('Şimdi buraya git'), findsOneWidget);

      final picks = pickEatsNow(
        kEatsPlaces,
        context: EatsContext(nowSlot: MealSlotX.forHour(japanHourForTest())),
      );
      expect(picks.length, kEatsPickCount);
      for (final r in picks) {
        expect(find.textContaining(r.place.name), findsWidgets,
            reason: r.place.id);
      }
    });

    testWidgets('premium eksen filtre popup\'ında kilitsiz açılır',
        (tester) async {
      useTallViewport(tester);
      await tester.pumpWidget(harness(_sampleTrip()));
      await settle(tester);

      await tester.tap(find.text('Filtre'));
      await tester.pumpAndSettle();

      // Kilit rozeti hiç yok.
      expect(find.widgetWithText(Container, 'Pass'), findsNothing);

      // Mutfak seçimi gerçekten uygulanır.
      await tester.tap(find.text('🍣 Suşi'));
      await tester.pumpAndSettle();

      final expected = runEatsQuery(
        kEatsPlaces,
        query: const EatsQuery(cuisines: {EatsCuisine.sushi}),
        tier: EatsTier.premium,
      );
      expect(find.text('${expected.length} sonucu göster'), findsOneWidget);
    });
  });

  group('kişiselleştirme ve güvenlik', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('helal tercihi seçiliyse filtre otomatik kurulur',
        (tester) async {
      useTallViewport(tester);
      await tester.pumpWidget(harness(_sampleTrip(dietaryTags: ['halal'])));
      await settle(tester);

      // Aktif filtre rozeti görünür ve listede helal olmayan mekan yok.
      expect(find.textContaining('Müslüman dostu'), findsWidgets);

      final expected = runEatsQuery(
        kEatsPlaces,
        query: const EatsQuery(minHalal: HalalTrust.muslimFriendly),
        tier: EatsTier.free,
      );
      expect(find.text(expected.first.place.name), findsOneWidget);
    });

    testWidgets('detay sheet\'inde güvenlik bilgisi ücretsiz katmanda da açık',
        (tester) async {
      useTallViewport(tester);
      await tester.pumpWidget(harness(_sampleTrip(dietaryTags: ['halal'])));
      await settle(tester);

      final first = runEatsQuery(
        kEatsPlaces,
        query: const EatsQuery(minHalal: HalalTrust.muslimFriendly),
        tier: EatsTier.free,
      ).first;

      await tester.tap(find.text(first.place.name));
      await tester.pumpAndSettle();

      // Helal seviyesi açıklaması + sipariş frazları kilitli DEĞİL.
      expect(find.text('Kapıda göster / sor'), findsOneWidget);
      expect(find.text('これに豚肉は入っていますか？'), findsOneWidget);
      // Veri küratörlü ve canlı DEĞİL; sorumluluk reddi bunu açıkça söyler
      // ("son kontrol" gibi doğrulama iması taşımaz).
      expect(
        find.textContaining('doğrudan teyit ALINMAMIŞTIR'),
        findsOneWidget,
      );

      // Karar zekası ise kilitli.
      expect(find.text('Rotori uyum skoru'), findsOneWidget);
      expect(find.text('Eats Pass ile aç'), findsWidgets);
    });
  });
}
