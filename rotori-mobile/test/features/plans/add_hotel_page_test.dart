// "Oteli kaydet" oturum YOKKEN de kaydeder.
//
// İki regresyon üst üste geldi. İlki: `_save` içinde `if (repo == null)
// return;` vardı — buton sessizce ölüyordu. O düzeltilirken yerine
// "oturum açman gerekiyor" uyarısı konuldu, ama oturumsuz akış uygulamanın
// DESTEKLEDİĞİ bir yol: `planByIdProvider` repo yokken planı
// `draftTripProvider`'dan okuyor ve uçuş ekranı tam olarak bunu yapıyor.
// Sonuç: aynı planda uçuş eklenebiliyor, otel eklenemiyordu.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rotori/core/l10n.dart';
import 'package:rotori/core/supabase_client.dart';
import 'package:rotori/domain/types.dart';
import 'package:rotori/features/plans/add_hotel_page.dart';
import 'package:rotori/features/plans/plan_providers.dart';

String tr(String key) => L10n.resolve(key, AppLang.tr);

Trip _trip() => Trip(
      id: 'trip-h',
      slug: 'hotel-save',
      title: 'Otel Kaydet',
      timezone: 'Asia/Tokyo',
      tripStart: '2026-08-27',
      tripEnd: '2026-08-29',
      flights: TripFlights(),
      preferences: TripPreferences(
        travelDates: TravelDates(start: '2026-08-27', end: '2026-08-29'),
        pace: Pace.moderate,
        destinations: [
          TripDestination(
            id: 'd1',
            countryCode: 'JP',
            countryName: 'Japonya',
            city: 'Tokyo',
            arrivalDate: '2026-08-27',
            departureDate: '2026-08-29',
            order: 0,
          ),
        ],
      ),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget harness(Trip trip) => ProviderScope(
        overrides: [
          // Oturum yok → plansRepositoryProvider null döner (gerçek hata koşulu).
          currentUserProvider.overrideWithValue(null),
          planByIdProvider.overrideWith((ref, id) => Stream<Trip>.value(trip)),
        ],
        child: MaterialApp(home: AddHotelPage(planId: trip.id)),
      );

  Future<void> fillRequiredFields(WidgetTester tester) async {
    final fields = find.byType(TextField);
    // Sıra: Şehir, Otel adı, Açık adres, Adres (yerel), Maps, Telefon, Notlar.
    await tester.enterText(fields.at(0), 'Tokyo');
    await tester.enterText(fields.at(1), 'Granbell Hotel');
    await tester.enterText(fields.at(2), '2-14-5 Kabukicho');
    await tester.pump();
  }

  testWidgets('sayfa açılır ve kaydet butonu görünür', (tester) async {
    tester.view.physicalSize = const Size(500, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness(_trip()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(find.text(tr('hotels.saveHotel')), findsOneWidget);
  });

  /// Tarih seçiciyi açıp ilk uygun günü onaylar. `_valid` bunları şart
  /// koştuğu için, repo kontrolüne ULAŞMAK için gerçekten seçmek gerekiyor.
  Future<void> pickBothDates(WidgetTester tester) async {
    for (var i = 0; i < 2; i++) {
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_DateBox',
        ).at(i),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('oturum yokken de kaydeder — taslağa yazar, uyarı vermez',
      (tester) async {
    tester.view.physicalSize = const Size(500, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final trip = _trip();
    final container = ProviderContainer(overrides: [
      currentUserProvider.overrideWithValue(null),
      planByIdProvider.overrideWith((ref, id) => Stream<Trip>.value(trip)),
    ]);
    addTearDown(container.dispose);

    // Sayfa kaydettikten sonra `context.pop()` çağırıyor; altında bir rota
    // olmadan pop edilemez, o yüzden gerçek bir GoRouter yığını kuruluyor.
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, __) => const Scaffold()),
        GoRoute(
          path: '/hotel',
          builder: (_, __) => AddHotelPage(planId: trip.id),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    // İtilerek açılır — uygulamadaki gibi (`context.push`), böylece pop
    // edilebilir bir yığın olur.
    router.push('/hotel');
    await tester.pumpAndSettle();

    await fillRequiredFields(tester);
    await pickBothDates(tester);

    await tester.tap(find.text(tr('hotels.saveHotel')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Oturum uyarısı YOK — bu yol destekleniyor.
    expect(find.text(tr('hotels.needsSession')), findsNothing);
    expect(find.text(tr('hotels.saveFailed')), findsNothing);

    // Otel taslağa yazıldı: repo yokken planByIdProvider buradan okuyor.
    final draft = container.read(draftTripProvider);
    expect(draft, isNotNull, reason: 'taslak güncellenmedi');
    expect(draft!.hotels.map((h) => h.name), contains('Granbell Hotel'));

    // Kopya üzerinde çalışıldı: gelen trip nesnesi kirletilmedi.
    expect(trip.hotels, isEmpty);

    // Ve sayfa kapandı.
    await tester.pumpAndSettle();
    expect(find.byType(AddHotelPage), findsNothing);
  });
}
