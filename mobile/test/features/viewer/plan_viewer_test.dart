// Plan viewer widget testi — temalı görüntüleyicinin temel davranışları:
// başlık render, aktif gün genişletilmiş + geçmiş gün soluk, tema seçici açılır.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:japan_trip/data/plans_repository.dart';
import 'package:japan_trip/domain/types.dart';
import 'package:japan_trip/features/plans/plan_providers.dart';
import 'package:japan_trip/features/plans/plan_viewer_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Bugüne göre birkaç geçmiş + bir aktif gün içeren örnek Trip.
Trip _sampleTrip() {
  final now = DateTime.now();
  String d(int offsetDays) {
    final t = now.add(Duration(days: offsetDays));
    return '${t.year.toString().padLeft(4, '0')}-'
        '${t.month.toString().padLeft(2, '0')}-'
        '${t.day.toString().padLeft(2, '0')}';
  }

  DayPlan mk(int n, int offset, String theme, String itemTitle) => DayPlan(
        dayNumber: n,
        date: d(offset),
        theme: theme,
        tags: const ['test'],
        items: [
          TimelineItem(id: 'it$n', title: itemTitle, time: '10:00'),
        ],
      );

  return Trip(
    id: 'trip-1',
    slug: 'test-trip',
    title: 'Japonya Test Gezisi',
    subtitle: 'Widget testi',
    timezone: 'Asia/Tokyo',
    tripStart: d(-2),
    tripEnd: d(2),
    flights: TripFlights(),
    preferences: TripPreferences(
      travelDates: TravelDates(start: d(-2), end: d(2)),
      pace: Pace.moderate,
    ),
    days: [
      mk(1, -2, 'Geçmiş Gün Teması', 'Gecmis Aktivite'),
      mk(2, 0, 'Aktif Gün Teması', 'Aktif Aktivite'),
      mk(3, 2, 'Gelecek Gün Teması', 'Gelecek Aktivite'),
    ],
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget harness(Trip trip) {
    return ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWith(
          (ref) async => SharedPreferences.getInstance(),
        ),
        planByIdProvider(trip.id).overrideWith((ref) => Stream.value(trip)),
      ],
      child: MaterialApp(
        // Sonsuz sakura/pulse animasyonlarını testte kapat (deterministik).
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: PlanViewerScreen(planId: trip.id),
          ),
        ),
      ),
    );
  }

  testWidgets('başlık ve aktif gün teması render edilir', (tester) async {
    await tester.pumpWidget(harness(_sampleTrip()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Viewer minimalize edildi — başlık artık body'de değil, drawer'ın
    // "Rotori" markası. Ana view sadece top bar + günler. Aktif gün açık
    // olmalı; aktivitesi görünür alana kaydırılıp doğrulanır.
    await tester.scrollUntilVisible(
      find.text('Aktif Aktivite'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Aktif Aktivite'), findsOneWidget);
    expect(find.text('Aktif Gün Teması'), findsWidgets);
  });

  testWidgets('geçmiş gün soluk (Opacity 0.6) render edilir', (tester) async {
    await tester.pumpWidget(harness(_sampleTrip()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final opacities = tester
        .widgetList<Opacity>(find.byType(Opacity))
        .map((w) => w.opacity)
        .toList();
    expect(opacities.contains(0.6), isTrue,
        reason: 'geçmiş gün kartı 0.6 opaklıkta olmalı');
  });

  testWidgets('aktif gün genişletilmiş, gelecek gün kapalı', (tester) async {
    await tester.pumpWidget(harness(_sampleTrip()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Gelecek gün kapalı olduğu için aktivitesi başta görünmez.
    expect(find.text('Gelecek Aktivite'), findsNothing);
  });

  testWidgets('tema seçici açılır ve 3 tema listelenir', (tester) async {
    await tester.pumpWidget(harness(_sampleTrip()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Aksiyon şeridi drawer'a taşındı — önce hamburger'a dokunup drawer'ı
    // aç, sonra palette butonuna tıkla.
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.palette_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Japon Gecesi'), findsOneWidget);
    expect(find.text('Apple Aydınlık'), findsOneWidget);
    expect(find.text('Sakura Yumuşak'), findsOneWidget);
  });

  testWidgets('uçuş satırı boş şehir+havaalanı ile "—" gösterir', (tester) async {
    final now = DateTime.now();
    String d(int off) {
      final t = now.add(Duration(days: off));
      return '${t.year.toString().padLeft(4, '0')}-'
          '${t.month.toString().padLeft(2, '0')}-'
          '${t.day.toString().padLeft(2, '0')}';
    }

    // Bir bacak: şehir + havaalanı boş; dateTime dolu (blank-leg değil).
    // Diğer bacak: normal Tokyo/HND. Amaç: boş satır "—" ile görünmeli,
    // tamamen blank filtre dışına atılmamalı (dateTime dolu).
    final trip = Trip(
      id: 'trip-flights',
      slug: 'flights-test',
      title: 'Uçuş Testi',
      timezone: 'Asia/Tokyo',
      tripStart: d(-1),
      tripEnd: d(1),
      flights: TripFlights(
        outbound: [
          FlightLeg(city: '', airport: '', dateTime: '${d(-1)}T10:00:00'),
          FlightLeg(
              city: 'Tokyo', airport: 'HND', dateTime: '${d(-1)}T18:00:00'),
        ],
        returnLegs: [
          // Tamamen boş bacak → filtre dışı kalmalı
          FlightLeg(city: '', airport: '', dateTime: ''),
        ],
      ),
      preferences: TripPreferences(
        travelDates: TravelDates(start: d(-1), end: d(1)),
        pace: Pace.moderate,
      ),
      days: [
        DayPlan(dayNumber: 1, date: d(0), theme: 'x', tags: const [], items: []),
      ],
    );

    await tester.pumpWidget(harness(trip));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Uçuş özeti artık drawer'ın içinde — hamburger'a dokun, aç.
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    // Boş bacak "—" olarak render olmalı (_DrawerFlightsMini._iata)
    expect(find.text('—'), findsWidgets);
    // Dolu bacak korunmalı — IATA "HND" görünür (city yerine airport tercih).
    expect(find.text('HND'), findsWidgets);
  });
}
