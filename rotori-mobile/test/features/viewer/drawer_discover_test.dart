// Drawer "KEŞFET" bölümü — her araç kendini anlatır.
//
// Eskiden bölüm beş adet ETİKETSİZ ikon karesiydi; ad yalnızca Tooltip'teydi
// ve dokunmatikte tooltip görünmediği için hiçbir karo ne yaptığını
// söylemiyordu. Ayrıca ürünün en zengin özelliği olan Rotori Eats, para
// tarayıcıyla birebir aynı görsel ağırlıktaydı.
//
// Bu test iki şeyi korur:
//   1) her keşif aracının adı ve tek satır açıklaması ekranda YAZILI,
//   2) Eats ayrı bir vitrin kartı ve katman rozetini (Ücretsiz / Pass)
//      premium durumuna göre gösteriyor.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:japan_trip/core/l10n.dart';
import 'package:japan_trip/core/supabase_client.dart';
import 'package:japan_trip/domain/plan_generation.dart';
import 'package:japan_trip/domain/types.dart';
import 'package:japan_trip/features/plans/plan_providers.dart';
import 'package:japan_trip/features/plans/plan_viewer_screen.dart';
import 'package:japan_trip/features/plans/premium_provider.dart';

String tr(String key) => L10n.resolve(key, AppLang.tr);

void main() {
  Trip weekTrip() => buildTripFromCities(
        cityKeys: const ['tokyo'],
        startYmd: '2026-10-15',
        endYmd: '2026-10-21',
      );

  Widget harness(Trip trip) => ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(null),
          planByIdProvider.overrideWith((ref, id) => Stream<Trip>.value(trip)),
        ],
        child: MaterialApp(home: PlanViewerScreen(planId: trip.id)),
      );

  Future<void> openDrawer(WidgetTester tester, Trip trip) async {
    // Uzun viewport: KEŞFET bölümü kaydırmadan görünür olsun.
    tester.view.physicalSize = const Size(390, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness(trip));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('her keşif aracı adıyla ve açıklamasıyla görünür',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await openDrawer(tester, weekTrip());

    // Adlar
    expect(find.text(tr('viewer.tt.eats')), findsOneWidget);
    expect(find.text(tr('viewer.tt.weather')), findsOneWidget);
    expect(find.text(tr('viewer.tt.budget')), findsOneWidget);
    expect(find.text(tr('viewer.tt.checklist')), findsOneWidget);
    expect(find.text(tr('scanner.price_tag')), findsOneWidget);

    // Açıklamalar — eskiden hiçbiri yazılı değildi.
    expect(find.text(tr('drawer.discover.eats.sub')), findsOneWidget);
    expect(find.text(tr('drawer.discover.weather.sub')), findsOneWidget);
    expect(find.text(tr('drawer.discover.budget.sub')), findsOneWidget);
    expect(find.text(tr('drawer.discover.checklist.sub')), findsOneWidget);
    expect(find.text(tr('drawer.discover.scanner.sub')), findsOneWidget);
  });

  testWidgets('Eats kartı ücretsiz katmanda "Ücretsiz" rozeti gösterir',
      (tester) async {
    SharedPreferences.setMockInitialValues({kPremiumPrefsKey: false});
    await openDrawer(tester, weekTrip());

    expect(find.text(tr('drawer.eats.free')), findsOneWidget);
    expect(find.text(tr('drawer.eats.pass')), findsNothing);
  });

  testWidgets('Eats kartı premium açıkken "Pass" rozetine döner',
      (tester) async {
    SharedPreferences.setMockInitialValues({kPremiumPrefsKey: true});
    await openDrawer(tester, weekTrip());
    // premiumProvider prefs'i asenkron okur; rozet bir sonraki frame'de döner.
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text(tr('drawer.eats.pass')), findsOneWidget);
    expect(find.text(tr('drawer.eats.free')), findsNothing);
  });

  testWidgets('Eats kartına dokununca drawer kapanır ve Eats ekranı açılır',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await openDrawer(tester, weekTrip());

    await tester.tap(find.text(tr('drawer.discover.eats.sub')));
    await tester.pumpAndSettle();

    // Eats ekranının kendi arama çubuğu ve filtre butonu geldi.
    expect(find.text('Filtre'), findsOneWidget);
  });
}
