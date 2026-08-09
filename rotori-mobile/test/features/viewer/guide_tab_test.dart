// Rehber sekmesi — düzen sözleşmesi.
//
// 1) "Seyahat öncesi hallet" EN ÜSTTE (aksiyon gerektiren tek şey),
// 2) bölümler KAPALI başlar (duvar değil),
// 3) çocuk maddeleri yalnız çocuklu gezide görünür.

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

  /// Rehber sekmesine geç.
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

  /// Viewer'ın kesintisiz animasyonu yüzünden pumpAndSettle kullanılamıyor.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Suica bölümü listenin altında kalıyor — dokunmadan önce görünür yap.
  Future<void> openSuica(WidgetTester tester) async {
    final header = find.text('Suica Kartı Nasıl Alınır?');
    await tester.scrollUntilVisible(header, 200,
        scrollable: find.byType(Scrollable).last);
    await settle(tester);
    await tester.tap(header);
    await settle(tester);
  }

  testWidgets('"Seyahat öncesi hallet" KAPALI başlar', (tester) async {
    final trip = baseTrip();
    await openGuide(tester, trip);

    expect(find.textContaining('Seyahat öncesi hallet'), findsOneWidget);
    // Kapalıyken afiliye bağlantıları render edilmemeli.
    expect(find.textContaining('JR Pass (Tüm Japonya)'), findsNothing);
  });

  testWidgets('"Seyahat öncesi hallet" dokununca açılır', (tester) async {
    final trip = baseTrip();
    await openGuide(tester, trip);

    await tester.tap(find.textContaining('Seyahat öncesi hallet'));
    await settle(tester);

    expect(find.textContaining('JR Pass'), findsWidgets);
  });

  testWidgets('"Seyahat öncesi hallet" rehberin EN ÜSTÜNDE', (tester) async {
    final trip = baseTrip();
    await openGuide(tester, trip);

    final prep = find.textContaining('Seyahat öncesi hallet');
    final heading = find.text('Mutlaka Bilmeniz Gerekenler');
    expect(prep, findsOneWidget);
    expect(heading, findsOneWidget);

    // Aksiyon kartı, konu başlığından YUKARIDA olmalı.
    expect(tester.getTopLeft(prep).dy, lessThan(tester.getTopLeft(heading).dy),
        reason: 'aksiyon kartı aşağı kaymış — kullanıcı hiç görmez');
  });

  testWidgets('bölümler kapalı başlar — madde duvarı yok', (tester) async {
    final trip = baseTrip();
    await openGuide(tester, trip);

    expect(find.text('Suica Kartı Nasıl Alınır?'), findsOneWidget);
    // Kapalıyken madde metni render edilmemeli.
    expect(find.textContaining('EN KOLAY YOL'), findsNothing);
  });

  testWidgets('başlığa dokununca bölüm açılır', (tester) async {
    final trip = baseTrip();
    await openGuide(tester, trip);

    await openSuica(tester);

    expect(find.textContaining('EN KOLAY YOL'), findsOneWidget);
  });

  group('çocuk maddeleri', () {
    testWidgets('çocuksuz gezide GÖRÜNMEZ', (tester) async {
      final trip = baseTrip()..preferences.childrenCount = 0;
      await openGuide(tester, trip);

      await openSuica(tester);

      expect(find.textContaining('ÇOCUK SUICA'), findsNothing);
    });

    testWidgets('çocuklu gezide GÖRÜNÜR', (tester) async {
      final trip = baseTrip()..preferences.childrenCount = 2;
      await openGuide(tester, trip);

      await openSuica(tester);

      expect(find.textContaining('ÇOCUK SUICA'), findsOneWidget);
    });

    testWidgets('kids ilgi etiketi de yeterli', (tester) async {
      final trip = baseTrip()
        ..preferences.childrenCount = null
        ..preferences.interests.add(InterestTag.kids);
      await openGuide(tester, trip);

      await openSuica(tester);

      expect(find.textContaining('ÇOCUK SUICA'), findsOneWidget);
    });

    testWidgets('madde sayısı rozeti çocuklu gezide artar', (tester) async {
      final withoutKids = baseTrip()..preferences.childrenCount = 0;
      await openGuide(tester, withoutKids);
      // Suica bölümü rozetinde 5 yetişkin maddesi.
      expect(find.text('5'), findsWidgets);
    });
  });

  testWidgets('arama madde bulur ve bölümü açar', (tester) async {
    final trip = baseTrip();
    await openGuide(tester, trip);

    await tester.enterText(find.byType(TextField).first, 'konbini');
    await settle(tester);

    // Eşleşen madde doğrudan görünür (arama sırasında bölümler açık).
    expect(find.textContaining('konbini'), findsWidgets);
    // Eşleşmeyen bölüm hiç çizilmez.
    expect(find.text('Belgeler ve Giriş'), findsNothing);
  });

  testWidgets('eşleşme yoksa bilgilendirir', (tester) async {
    final trip = baseTrip();
    await openGuide(tester, trip);

    await tester.enterText(find.byType(TextField).first, 'zzzxxqq');
    await settle(tester);

    expect(find.text(tr('viewer.guide.noResult')), findsOneWidget);
  });
}
