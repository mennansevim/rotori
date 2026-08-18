// Rehber sekmesi — yeni bilgi mimarisi sözleşmesi.
//
// 1) büyük "Rehber" başlığı + "Hızlı erişim" + "Tüm konular" görünür,
// 2) "Seyahat öncesi hallet" başlığın üstünü işgal etmez,
// 3) konu seçimi aynı sekmede temiz detay görünümü açar,
// 4) arama, detay dönüşünde korunur ve çocuk filtrelemesi bozulmaz.

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

  Trip baseTrip() => buildTripFromCities(
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

  Future<void> openGuide(WidgetTester tester, Trip trip) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness(trip));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(find.text('Rehber').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Finder guideScroll() => find.byType(Scrollable).last;

  Finder guideText(String text) =>
      find.descendant(of: guideScroll(), matching: find.text(text));

  Finder guideTextContaining(String text) => find.descendant(
        of: guideScroll(),
        matching: find.textContaining(text),
      );

  Finder guideKey(String key) => find.byKey(ValueKey(key));

  TextField searchField(WidgetTester tester) =>
      tester.widget<TextField>(guideKey('viewer-guide-search'));

  testWidgets('rehber başlığı, hızlı erişim ve yardımcı satır görünür',
      (tester) async {
    final trip = baseTrip();
    await openGuide(tester, trip);

    final heading = guideKey('guide-title');
    final quickAccess = guideKey('guide-quick-access-heading');
    final allTopics = guideKey('guide-all-topics-heading');
    final prep = guideKey('guide-predeparture');

    expect(heading, findsOneWidget);
    expect(quickAccess, findsOneWidget);
    expect(allTopics, findsOneWidget);
    expect(guideKey('guide-quick-6'), findsOneWidget);
    expect(guideKey('guide-quick-2'), findsOneWidget);
    expect(guideKey('guide-quick-1'), findsOneWidget);
    expect(guideKey('guide-quick-3'), findsOneWidget);

    final scrollable = find.byType(Scrollable).first;
    for (var i = 0; i < 5 && prep.evaluate().isEmpty; i++) {
      await tester.drag(scrollable, const Offset(0, -700));
      await settle(tester);
    }

    expect(prep, findsOneWidget);

    expect(
      tester.getTopLeft(prep).dy,
      greaterThan(tester.getTopLeft(allTopics).dy),
      reason: 'yardımcı satır konu listesi başlığının üstünde kalmamalı',
    );
  });

  testWidgets('konuya dokununca aynı sekmede detay açılır', (tester) async {
    final trip = baseTrip();
    await openGuide(tester, trip);

    await tester.tap(guideKey('guide-topic-2'));
    await settle(tester);

    expect(guideKey('guide-back-all'), findsOneWidget);
    expect(guideKey('viewer-top-status-bar'), findsOneWidget);
    expect(guideKey('viewer-quick-nav'), findsOneWidget);
    expect(guideTextContaining('EN KOLAY YOL'), findsOneWidget);
    expect(find.text('Rehber'), findsWidgets);
  });

  testWidgets('arama eşleşen konuyu açar ve geri dönüşte aramayı korur',
      (tester) async {
    final trip = baseTrip();
    await openGuide(tester, trip);

    await tester.enterText(
      guideKey('viewer-guide-search'),
      'Welcome Suica',
    );
    await settle(tester);

    expect(guideKey('guide-back-all'), findsOneWidget);
    expect(guideTextContaining('Welcome Suica'), findsOneWidget);
    expect(guideKey('guide-topic-0'), findsNothing);

    await tester.tap(guideKey('guide-back-all'));
    await settle(tester);

    expect(searchField(tester).controller!.text, 'Welcome Suica');
    expect(guideKey('guide-topic-2'), findsOneWidget);
    expect(guideKey('guide-topic-0'), findsNothing);
  });

  testWidgets('arama sonucu yokken hızlı erişim gizlenir ve boş detay açılmaz',
      (tester) async {
    final trip = baseTrip();
    await openGuide(tester, trip);

    await tester.enterText(
      guideKey('viewer-guide-search'),
      'zzz-no-match',
    );
    await settle(tester);

    expect(guideKey('guide-quick-access-heading'), findsNothing);
    expect(guideKey('guide-quick-6'), findsNothing);
    expect(guideKey('guide-quick-2'), findsNothing);
    expect(guideKey('guide-back-all'), findsNothing);
  });

  group('çocuk maddeleri', () {
    testWidgets('çocuksuz gezide görünmez', (tester) async {
      final trip = baseTrip()..preferences.childrenCount = 0;
      await openGuide(tester, trip);

      await tester.tap(guideKey('guide-topic-2'));
      await settle(tester);

      expect(guideTextContaining('ÇOCUK SUICA'), findsNothing);
    });

    testWidgets('çocuklu gezide görünür', (tester) async {
      final trip = baseTrip()..preferences.childrenCount = 2;
      await openGuide(tester, trip);

      await tester.tap(guideKey('guide-topic-2'));
      await settle(tester);

      expect(guideTextContaining('ÇOCUK SUICA'), findsOneWidget);
    });

    testWidgets('kids ilgi etiketi de yeterli', (tester) async {
      final trip = baseTrip()
        ..preferences.childrenCount = null
        ..preferences.interests.add(InterestTag.kids);
      await openGuide(tester, trip);

      await tester.tap(guideKey('guide-topic-2'));
      await settle(tester);

      expect(guideTextContaining('ÇOCUK SUICA'), findsOneWidget);
    });
  });
}
