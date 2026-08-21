// Rehber sekmesi — yeni bilgi mimarisi sözleşmesi.
//
// 1) büyük "Rehber" başlığı + "Hızlı erişim" + "Tüm konular" görünür,
// 2) "Seyahat öncesi hallet" Rehber içinde görünmez,
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

  Widget harness(Trip trip, {bool accessibilityMode = false}) => ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(null),
          planByIdProvider.overrideWith((ref, id) => Stream<Trip>.value(trip)),
        ],
        child: MaterialApp(
          builder: accessibilityMode
              ? (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      disableAnimations: true,
                      textScaler: const TextScaler.linear(1.3),
                    ),
                    child: child!,
                  )
              : null,
          home: PlanViewerScreen(planId: trip.id),
        ),
      );

  Future<void> openGuide(
    WidgetTester tester,
    Trip trip, {
    bool accessibilityMode = false,
    double viewportHeight = 1400,
  }) async {
    tester.view.physicalSize = Size(390, viewportHeight);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      harness(trip, accessibilityMode: accessibilityMode),
    );
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

  Finder guideTextContaining(String text) => find.descendant(
        of: guideScroll(),
        matching: find.textContaining(text),
      );

  Finder guideKey(String key) => find.byKey(ValueKey(key));

  SlideTransition closestSlideTo(
    WidgetTester tester,
    Finder descendant,
  ) {
    SlideTransition? result;
    tester.element(descendant).visitAncestorElements((element) {
      if (element.widget case final SlideTransition transition) {
        result = transition;
        return false;
      }
      return true;
    });
    return result!;
  }

  bool hasFadeBeforeGuideSwitcher(
    WidgetTester tester,
    Finder descendant,
  ) {
    var hasFade = false;
    tester.element(descendant).visitAncestorElements((element) {
      if (element.widget is AnimatedSwitcher) return false;
      if (element.widget is FadeTransition) hasFade = true;
      return true;
    });
    return hasFade;
  }

  TextField searchField(WidgetTester tester) =>
      tester.widget<TextField>(guideKey('viewer-guide-search'));

  testWidgets('rehber başlığı ve konular görünür, hazırlık kartı görünmez',
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

    expect(prep, findsNothing);
    expect(find.text('Seyahat öncesi hallet'), findsNothing);
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

  testWidgets('detay açılışı sağdan, konu listesine dönüş soldan gelir',
      (tester) async {
    final trip = baseTrip();
    await openGuide(tester, trip);

    await tester.tap(guideKey('guide-topic-2'));
    await tester.pump(const Duration(milliseconds: 110));

    final detailSlide = closestSlideTo(tester, guideKey('guide-back-all'));
    expect(
      detailSlide.position.value.dx,
      greaterThan(0),
    );

    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(guideKey('guide-back-all'));
    await tester.pump(const Duration(milliseconds: 110));

    final listSlide = closestSlideTo(tester, guideKey('guide-title'));
    expect(
      listSlide.position.value.dx,
      lessThan(0),
    );

    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(
      guideKey('viewer-guide-search'),
      'Welcome Suica',
    );
    await tester.pump(const Duration(milliseconds: 110));

    final searchDetailSlide =
        closestSlideTo(tester, guideKey('guide-back-all'));
    expect(
      searchDetailSlide.position.value.dx,
      greaterThan(0),
    );
  });

  testWidgets('rehber sayfaları iz bırakmadan karşı yönlere kayar',
      (tester) async {
    final trip = baseTrip();
    await openGuide(tester, trip);

    await tester.tap(guideKey('guide-topic-2'));
    await tester.pump();

    final detailSlide = closestSlideTo(tester, guideKey('guide-back-all'));
    expect(
      detailSlide.position.value.dx,
      closeTo(1, 0.001),
      reason: 'detay, eski sayfanın üstünde değil ekranın sağından başlamalı',
    );
    expect(
      hasFadeBeforeGuideSwitcher(tester, guideKey('guide-back-all')),
      isFalse,
      reason: 'iki tam sayfa cross-fade edilince metinler hayalet iz bırakıyor',
    );

    await tester.pump(const Duration(milliseconds: 110));

    expect(
      closestSlideTo(tester, guideKey('guide-back-all')).position.value.dx,
      greaterThan(0),
    );
    expect(
      closestSlideTo(tester, guideKey('guide-title')).position.value.dx,
      lessThan(0),
      reason: 'liste sola çıkarken detay sağdan girmeli',
    );
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

  testWidgets('dar ekranda büyük metin ve azaltılmış hareket taşma üretmez',
      (tester) async {
    final trip = baseTrip();
    await openGuide(
      tester,
      trip,
      accessibilityMode: true,
      viewportHeight: 844,
    );

    expect(guideKey('guide-title'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(guideKey('guide-quick-2'));
    await settle(tester);

    expect(guideKey('guide-back-all'), findsOneWidget);
    expect(guideKey('viewer-top-status-bar'), findsOneWidget);
    expect(guideKey('viewer-quick-nav'), findsOneWidget);
    expect(tester.takeException(), isNull);
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
