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
          builder: (_, __) => const Scaffold(body: Text('Uçuş sayfası')),
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
    await tester.pumpWidget(harness(trip));
    await tester.pumpAndSettle();

    expect(find.text(tr('viewer.addFlight.title')), findsOneWidget);
    // Viewer'da başka kapatılabilir kartlar da var ("Bunları da gör") —
    // ✕ ikonunu UÇUŞ kartının içinde ara, yoksa finder belirsiz kalıyor.
    await tester.tap(find.descendant(
      of: find.ancestor(
        of: find.text(tr('viewer.addFlight.title')),
        matching: find.byType(Container),
      ).first,
      matching: find.byIcon(Icons.close_rounded),
    ));
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
}
