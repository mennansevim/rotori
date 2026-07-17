// ChecklistScreen widget smoke testi — bir kategori + madde render edilir;
// bir satıra dokununca işaretli durumu (strikethrough / checkbox) değişir.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:japan_trip/data/plans_repository.dart';
import 'package:japan_trip/domain/types.dart';
import 'package:japan_trip/features/viewer/checklist_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Trip _sampleTrip() => Trip(
      id: 'trip-cl',
      slug: 'checklist-trip',
      title: 'Valiz Test',
      timezone: 'Asia/Tokyo',
      tripStart: '2026-07-01',
      tripEnd: '2026-07-02',
      flights: TripFlights(),
      preferences: TripPreferences(
        travelDates: TravelDates(start: '2026-07-01', end: '2026-07-02'),
        pace: Pace.moderate,
        partySize: 2,
      ),
      days: const [],
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  void useTallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 6000);
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
            child: ChecklistScreen(trip: trip),
          ),
        ),
      ),
    );
  }

  testWidgets('kategori ve madde render edilir', (tester) async {
    useTallViewport(tester);
    await tester.pumpWidget(harness(_sampleTrip()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('🎒 Valiz & Hazırlık'), findsOneWidget);
    // Bir kategori başlığı
    expect(find.text('Belgeler'), findsOneWidget);
    // Bir madde
    expect(find.text('Pasaport'), findsOneWidget);
  });

  testWidgets('satıra dokununca işaretli durumu değişir', (tester) async {
    useTallViewport(tester);
    await tester.pumpWidget(harness(_sampleTrip()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Başlangıçta işaretsiz.
    expect(
      find.byIcon(Icons.check_box_outline_blank_rounded),
      findsWidgets,
    );

    // "Pasaport" satırına dokun.
    await tester.tap(find.text('Pasaport'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // En az bir işaretli kutu görünür (dokunulan madde).
    expect(find.byIcon(Icons.check_box_rounded), findsWidgets);

    // Etiket üzerinde strikethrough uygulanmış olmalı.
    final textWidget = tester.widget<Text>(find.text('Pasaport'));
    expect(textWidget.style?.decoration, TextDecoration.lineThrough);
  });
}
