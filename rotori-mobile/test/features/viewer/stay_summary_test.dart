// Drawer özet kartı — gece sayısı gezinin kendisinden gelir.
//
// Eskiden gece sayısı yalnızca REZERVE EDİLMİŞ otellerden toplanıyordu:
// yeni üretilen planda otel olmadığı için kart "0 Gece · 10 Gün" gibi
// kendi içinde çelişen bir şey gösteriyordu.
//
// Rezervasyon metriği karttan kaldırıldı; o bilgi hemen alttaki Konaklama
// satırının işi. Burada kalan sözleşme: üç metrik, tek satır, kısa kart.

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
  });

  testWidgets('otel eklenmesi gece sayısını EZMEZ', (tester) async {
    final trip = weekTrip();
    trip.hotels.add(HotelStay(
      id: 'h1',
      name: 'Test Hotel',
      city: 'Tokyo',
      address: 'Shinjuku',
      checkIn: '2026-10-15',
      checkOut: '2026-10-18', // yalnızca 3 gece rezerve
    ));

    await openDrawer(tester, trip);

    // Gece sayısı hâlâ gezinin uzunluğu.
    expect(find.text('6'), findsOneWidget);
    // Rezervasyon oranı ("3/6") artık bu kartta gösterilmiyor.
    expect(find.text('3/6'), findsNothing);
  });

  testWidgets('üç metrik tek satırda kalır ve kart kısa durur', (tester) async {
    final trip = weekTrip();

    await openDrawer(tester, trip);

    final labels = [
      tr('viewer.metric.nights'),
      tr('viewer.metric.cities'),
      tr('viewer.metric.days'),
    ];
    for (final label in labels) {
      expect(find.text(label), findsOneWidget, reason: '$label yok');
    }

    // Dikey merkezleri eşit → aynı yatay şerit.
    final centers =
        labels.map((l) => tester.getCenter(find.text(l)).dy).toList();
    for (final dy in centers) {
      expect((dy - centers.first).abs(), lessThan(1.0),
          reason: 'metrik etiketleri aynı satırda olmalı: $centers');
    }

    // Kart dikeyde kompakt kalmalı — eski üç-kolon düzeni ~150px'ti.
    final card = find.ancestor(
      of: find.text(tr('viewer.metric.nights')),
      matching: find.byType(Container),
    );
    expect(tester.getSize(card.first).height, lessThan(90));

    // Metrikler genişliğe dağılmış olmalı: sağda boşluk kalmasın.
    // Son metriğin merkezi kartın sağ yarısında durur.
    final cardRect = tester.getRect(card.first);
    final lastCenter = tester.getCenter(find.text(labels.last)).dx;
    expect(lastCenter, greaterThan(cardRect.center.dx),
        reason: 'son metrik sağ yarıda değil — şerit sola yapışmış');
  });

  testWidgets('kartta rezervasyon aksiyonu (chevron) yoktur', (tester) async {
    final trip = weekTrip();

    await openDrawer(tester, trip);

    // Özet kartı bilgi kartıdır; dokunulacak bir hedef sunmaz.
    expect(
      find.ancestor(
        of: find.text(tr('viewer.metric.nights')),
        matching: find.byType(InkWell),
      ),
      findsNothing,
    );
  });
}
