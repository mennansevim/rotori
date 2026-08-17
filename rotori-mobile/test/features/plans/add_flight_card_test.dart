// "✈️ Uçuşunu ekle" kartı — viewer'da tripHasFlightInfo koşuluna göre
// görünür/kapanır davranışı.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rotori/core/l10n.dart';
import 'package:rotori/core/supabase_client.dart';
import 'package:rotori/domain/plan_generation.dart';
import 'package:rotori/domain/types.dart';
import 'package:rotori/features/plans/plan_providers.dart';
import 'package:rotori/features/plans/plan_viewer_screen.dart';

String tr(String key) => L10n.resolve(key, AppLang.tr);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget harness(Trip trip) {
    final router = GoRouter(
      initialLocation: '/plans/${trip.id}/view',
      routes: [
        GoRoute(
          path: '/plans/:id/view',
          builder: (_, __) => PlanViewerScreen(planId: trip.id),
        ),
        GoRoute(
          path: '/plans/:id/flights',
          builder: (_, __) => _FlightStub(trip: trip),
        ),
      ],
    );
    return ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(null),
        planByIdProvider(trip.id).overrideWith((ref) => Stream.value(trip)),
      ],
      child: Builder(
        builder: (context) => MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: MaterialApp.router(routerConfig: router),
        ),
      ),
    );
  }

  testWidgets('uçuş bilgisi yoksa kart görünür', (tester) async {
    final trip = buildTripFromCities(
      cityKeys: const ['tokyo'],
      startYmd: '2026-10-15',
      endYmd: '2026-10-21',
    );
    await tester.pumpWidget(harness(trip));
    await tester.pumpAndSettle();

    expect(find.text(tr('viewer.addFlight.title')), findsOneWidget);
  });

  testWidgets('uçuş bilgisi doluysa kart görünmez', (tester) async {
    final trip = buildTripFromCities(
      cityKeys: const ['tokyo'],
      startYmd: '2026-10-15',
      endYmd: '2026-10-21',
    );
    trip.flights.outbound.first
      ..city = 'İstanbul'
      ..airport = 'IST';
    expect(tripHasFlightInfo(trip), isTrue);

    await tester.pumpWidget(harness(trip));
    await tester.pumpAndSettle();

    expect(find.text(tr('viewer.addFlight.title')), findsNothing);
  });

  testWidgets('✕ kartı kapatır', (tester) async {
    final trip = buildTripFromCities(
      cityKeys: const ['tokyo'],
      startYmd: '2026-10-15',
      endYmd: '2026-10-21',
    );
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness(trip));
    await tester.pumpAndSettle();

    expect(find.text(tr('viewer.addFlight.title')), findsOneWidget);
    // Viewer'da başka kapatılabilir kartlar da var ("Bunları da gör") —
    // ✕ ikonunu UÇUŞ kartının içinde ara, yoksa finder belirsiz kalıyor.
    final flightRow = find
        .ancestor(
          of: find.text(tr('viewer.addFlight.title')),
          matching: find.byType(Row),
        )
        .last;
    final closeButton = find.descendant(
      of: flightRow,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is IconButton &&
            widget.onPressed != null &&
            widget.icon is Icon &&
            (widget.icon as Icon).icon == Icons.close_rounded,
      ),
    );
    await tester.ensureVisible(closeButton);
    await tester.tap(closeButton);
    await tester.pumpAndSettle();

    expect(find.text(tr('viewer.addFlight.title')), findsNothing);
  });

  testWidgets('karta dokununca uçuş sayfasına gider', (tester) async {
    final trip = buildTripFromCities(
      cityKeys: const ['tokyo'],
      startYmd: '2026-10-15',
      endYmd: '2026-10-21',
    );
    await tester.pumpWidget(harness(trip));
    await tester.pumpAndSettle();

    await tester.tap(find.text(tr('viewer.addFlight.title')));
    await tester.pumpAndSettle();

    expect(find.text('Uçuş sayfası'), findsOneWidget);
  });

  testWidgets('kayıttan sonra drawer açılır ve Uçuşlar akordiyonu açıktır',
      (tester) async {
    final trip = buildTripFromCities(
      cityKeys: const ['tokyo'],
      startYmd: '2026-10-15',
      endYmd: '2026-10-21',
    );
    await tester.pumpWidget(harness(trip));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text(tr('drawer.flights.add')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test uçuşunu kaydet'));
    await tester.pumpAndSettle();

    expect(
        find.text(tr('viewer.flights').replaceAll('✈️ ', '')), findsOneWidget);
    expect(find.text('14:30'), findsOneWidget);
    expect(find.text('09:15'), findsOneWidget);
  });
}

class _FlightStub extends StatelessWidget {
  const _FlightStub({required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('Uçuş sayfası'),
          ElevatedButton(
            onPressed: () {
              final saved = Trip.fromJson(trip.toJson())
                ..flights = TripFlights(
                  outbound: [
                    FlightLeg(
                      city: 'İstanbul',
                      airport: 'IST',
                      dateTime: '2026-10-15T08:00:00',
                    ),
                    FlightLeg(
                      city: 'Tokyo',
                      airport: 'HND',
                      dateTime: '2026-10-15T14:30:00',
                    ),
                  ],
                  returnLegs: [
                    FlightLeg(
                      city: 'Tokyo',
                      airport: 'HND',
                      dateTime: '2026-10-21T09:15:00',
                    ),
                    FlightLeg(
                      city: 'İstanbul',
                      airport: 'IST',
                      dateTime: '2026-10-21T18:00:00',
                    ),
                  ],
                );
              context.pop(saved);
            },
            child: const Text('Test uçuşunu kaydet'),
          ),
        ],
      ),
    );
  }
}
