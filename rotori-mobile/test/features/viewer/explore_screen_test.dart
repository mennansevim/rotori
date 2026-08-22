import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/core/l10n.dart';
import 'package:rotori/core/supabase_client.dart';
import 'package:rotori/data/plans_repository.dart';
import 'package:rotori/domain/place_coords.dart';
import 'package:rotori/domain/types.dart';
import 'package:rotori/features/viewer/explore_screen.dart';
import 'package:rotori/features/viewer/geofence_service.dart';
import 'package:rotori/features/viewer/viewer_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Trip _trip() => Trip(
      id: 'explore-test',
      slug: 'explore-test',
      title: 'Tokyo',
      timezone: 'Asia/Tokyo',
      tripStart: '2026-10-01',
      tripEnd: '2026-10-03',
      flights: TripFlights(),
      preferences: TripPreferences(
        travelDates: TravelDates(start: '2026-10-01', end: '2026-10-03'),
        pace: Pace.moderate,
      ),
      days: [
        DayPlan(
          dayNumber: 1,
          date: '2026-10-01',
          theme: 'Tokyo',
          items: [
            TimelineItem(
              id: 'sensoji',
              title: 'Planlı durak',
              time: '09:00',
            ),
          ],
        ),
      ],
    );

Widget _harness() {
  return ProviderScope(
    overrides: [
      currentUserProvider.overrideWithValue(null),
      sharedPrefsProvider.overrideWith(
        (ref) async => SharedPreferences.getInstance(),
      ),
    ],
    child: LanguageScope(
      lang: AppLang.tr,
      child: MaterialApp(
        home: Theme(
          data: ViewerPalette.appleLight.toThemeData(),
          child: ViewerPaletteScope(
            palette: ViewerPalette.appleLight,
            child: ExploreScreen(trip: _trip()),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('planlı duraklar odağı ve harita görünür', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Keşfet'), findsOneWidget);
    expect(find.text('Planlı duraklar'), findsWidgets);
    expect(find.text('Harita'), findsOneWidget);
    expect(find.text('Planlı durak'), findsOneWidget);
  });

  testWidgets('Yakınımda konum isteğini bağlam içinde gösterir',
      (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.text('Yakınımda').first);
    await tester.pump();

    expect(find.text('Yakınımda'), findsWidgets);
    expect(find.text('Konum alınana kadar planındaki durakları gösteriyoruz.'),
        findsOneWidget);
  });

  test('Yakınımda konum varsa durakları mesafeye göre sıralar', () {
    final near = ResolvedStop(
      item: TimelineItem(id: 'near', title: 'Yakın durak'),
      lat: 35.6586,
      lng: 139.7454,
      order: 2,
    );
    final far = ResolvedStop(
      item: TimelineItem(id: 'far', title: 'Uzak durak'),
      lat: 35.6595,
      lng: 139.7005,
      order: 1,
    );
    final sample = GeoSample(
      lat: 35.6587,
      lng: 139.7455,
      timestamp: DateTime(2026, 10, 1),
    );

    final sorted = sortExploreStopsByDistance([far, near], sample);

    expect(
        sorted.map((stop) => stop.item.title), ['Yakın durak', 'Uzak durak']);
  });

  test('Yakınımda konum yoksa plan sırasını korur', () {
    final first = ResolvedStop(
      item: TimelineItem(id: 'first', title: 'İlk durak'),
      lat: 35.6586,
      lng: 139.7454,
      order: 1,
    );
    final second = ResolvedStop(
      item: TimelineItem(id: 'second', title: 'İkinci durak'),
      lat: 35.6595,
      lng: 139.7005,
      order: 2,
    );

    final sorted = sortExploreStopsByDistance([first, second], null);

    expect(
        sorted.map((stop) => stop.item.title), ['İlk durak', 'İkinci durak']);
  });
}
