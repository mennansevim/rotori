// Drawer "YOLCULUK" kartı — gece sayısı gezinin kendisinden gelir.
//
// Eskiden gece sayısı yalnızca REZERVE EDİLMİŞ otellerden toplanıyordu:
// yeni üretilen planda otel olmadığı için kart "0 Gece · 10 Gün" gibi
// kendi içinde çelişen bir şey gösteriyordu.

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

  /// 7 günlük plan → 6 gece.
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
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness(trip));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('otel yokken bile gece sayısı gün-1 olur', (tester) async {
    final trip = weekTrip();
    expect(trip.hotels, isEmpty, reason: 'yeni planda otel olmamalı');

    await openDrawer(tester, trip);

    // 7 gün → 6 gece. "0" ASLA görünmemeli.
    expect(find.text('6'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text(tr('viewer.stay.none')), findsOneWidget);
  });

  testWidgets('otel eklenince rezerve gece sayısı ayrıca gösterilir',
      (tester) async {
    final trip = weekTrip();
    trip.hotels.add(HotelStay(
      id: 'h1',
      name: 'Test Hotel',
      city: 'Tokyo',
      address: 'Shinjuku',
      checkIn: '2026-10-15',
      checkOut: '2026-10-18',
    ));

    await openDrawer(tester, trip);

    // Gece sayısı hâlâ gezinin uzunluğu — otel onu EZMEZ.
    expect(find.text('6'), findsOneWidget);
    // 3 gece rezerve edildi bilgisi ayrı satırda.
    expect(
      find.text(L10n.parametrize(
          tr('viewer.stay.covered'), {'booked': '3', 'total': '6'})),
      findsOneWidget,
    );
  });

  testWidgets('rezervasyon gezi süresini aşarsa kırpılır', (tester) async {
    final trip = weekTrip();
    trip.hotels.add(HotelStay(
      id: 'h1',
      name: 'Uzun',
      city: 'Tokyo',
      address: 'x',
      checkIn: '2026-10-01',
      checkOut: '2026-11-01', // 31 gece — 6 gecelik geziye sığmaz
    ));

    await openDrawer(tester, trip);

    // "31/6 gece" saçma olurdu; 6/6'ya kırpılmalı.
    expect(
      find.text(L10n.parametrize(
          tr('viewer.stay.covered'), {'booked': '6', 'total': '6'})),
      findsOneWidget,
    );
  });
}
