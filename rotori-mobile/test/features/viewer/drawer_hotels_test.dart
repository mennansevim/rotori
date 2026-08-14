// Drawer "Konaklama" bölümü — otel ekleme yolu her durumda açık kalmalı.
//
// Regresyon: `_DrawerAddCard` yalnız `hotels.isEmpty` dalında çiziliyordu ve
// `/plans/:id/hotels/new` rotasının uygulamada başka hiçbir girişi yok. İlk
// otel eklendiği anda ikinciyi eklemek imkânsızlaşıyordu; çok şehirli planda
// (Tokyo + Kyoto) rezervasyon yarım kalıyordu.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rotori/core/l10n.dart';
import 'package:rotori/core/supabase_client.dart';
import 'package:rotori/domain/plan_generation.dart';
import 'package:rotori/domain/types.dart';
import 'package:rotori/features/plans/plan_providers.dart';
import 'package:rotori/features/plans/plan_viewer_screen.dart';

String tr(String key) => L10n.resolve(key, AppLang.tr);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Trip twoCityTrip() => buildTripFromCities(
        cityKeys: const ['tokyo', 'kyoto'],
        startYmd: '2026-10-15',
        endYmd: '2026-10-21',
      );

  HotelStay tokyoHotel() => HotelStay(
        id: 'hotel-tokyo',
        city: 'Tokyo',
        name: 'Shinjuku Granbell Hotel',
        checkIn: '2026-10-15',
        checkOut: '2026-10-18',
        address: '2-14-5 Kabukicho, Shinjuku, Tokyo',
      );

  Widget harness(Trip trip) => ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(null),
          planByIdProvider.overrideWith((ref, id) => Stream<Trip>.value(trip)),
        ],
        child: MaterialApp(home: PlanViewerScreen(planId: trip.id)),
      );

  Future<void> openDrawer(WidgetTester tester, Trip trip) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness(trip));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// "Konaklama" bölümünü açar — varsayılan kapalıdır.
  Future<void> expandHotels(WidgetTester tester) async {
    final header = find.text(tr('viewer.hotels').replaceAll('🏨 ', ''));
    await tester.scrollUntilVisible(
      header,
      160,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(header);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('otel yokken boş-durum ekleme kartı görünür', (tester) async {
    final trip = twoCityTrip();
    expect(trip.hotels, isEmpty);

    await openDrawer(tester, trip);

    final addCard = find.text(tr('drawer.hotels.add'));
    await tester.scrollUntilVisible(
      addCard,
      160,
      scrollable: find.byType(Scrollable).last,
    );
    expect(addCard, findsOneWidget);
  });

  testWidgets(
      'otel VARKEN de ekleme yolu açık kalır (ikinci şehir rezerve edilebilir)',
      (tester) async {
    final trip = twoCityTrip()..hotels.add(tokyoHotel());
    expect(trip.hotels, hasLength(1));

    await openDrawer(tester, trip);
    await expandHotels(tester);

    // Mevcut otel listelenmeli.
    expect(find.text('Shinjuku Granbell Hotel'), findsOneWidget);

    // Ve ekleme satırı da bulunmalı — asıl regresyon kapısı.
    final addRow = find.byKey(const ValueKey('drawer-hotels-add-another'));
    await tester.scrollUntilVisible(
      addRow,
      160,
      scrollable: find.byType(Scrollable).last,
    );
    expect(addRow, findsOneWidget);
    expect(
      find.descendant(of: addRow, matching: find.text(tr('hotels.addAnother'))),
      findsOneWidget,
    );
  });

  testWidgets('ekleme satırı dokunulabilir ve tek satırlık kalır',
      (tester) async {
    final trip = twoCityTrip()..hotels.add(tokyoHotel());

    await openDrawer(tester, trip);
    await expandHotels(tester);

    final addRow = find.byKey(const ValueKey('drawer-hotels-add-another'));
    await tester.scrollUntilVisible(
      addRow,
      160,
      scrollable: find.byType(Scrollable).last,
    );

    // Otel kartlarıyla görsel olarak yarışmamalı: ince, tek satır.
    expect(tester.getSize(addRow).height, lessThan(44));

    // Dokunma bir InkWell'e bağlı olmalı (rota push'u burada doğrulanmaz;
    // Navigator harness'ı olmadan gerçek push testi kırılgan olurdu).
    expect(
      find.descendant(of: addRow, matching: find.byType(InkWell)),
      findsOneWidget,
    );
  });
}
