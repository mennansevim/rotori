import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rotori/core/l10n.dart';
import 'package:rotori/core/supabase_client.dart';
import 'package:rotori/domain/plan_generation.dart';
import 'package:rotori/domain/types.dart';
import 'package:rotori/features/plans/flights/flight_details_page.dart';
import 'package:rotori/features/plans/plan_providers.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Trip flightDraft() {
    final trip = buildTripFromCities(
      cityKeys: const ['tokyo', 'osaka'],
      startYmd: '2026-10-15',
      endYmd: '2026-10-21',
    );
    trip.preferences
      ..originCity = 'İstanbul'
      ..originAirport = 'IST'
      ..outboundArrivalTime = '14:30'
      ..returnDepartAirport = 'KIX'
      ..returnDepartTime = '09:15'
      ..returnArrivalAirport = 'IST';
    trip.preferences.destinations
      ..first.airport = 'HND'
      ..last.airport = 'KIX';
    trip.days[2].theme = 'Elle düzenlenmiş orta gün';
    return trip;
  }

  Widget harness(Trip trip) {
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, __) => const _ResultPage()),
        GoRoute(
          path: '/flights',
          builder: (_, __) => FlightDetailsPage(planId: trip.id),
        ),
      ],
    );
    return ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(null),
        planByIdProvider(trip.id).overrideWith((ref) => Stream.value(trip)),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  testWidgets(
    'tek Kaydet aksiyonu günleri yeniler, bilgi verir ve güncel planı döndürür',
    (tester) async {
      final trip = flightDraft();
      await tester.pumpWidget(harness(trip));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Uçuş ekle'));
      await tester.pumpAndSettle();

      expect(
        find.text(L10n.resolve('flights.regenAction', AppLang.tr)),
        findsNothing,
      );

      final save = find.text(L10n.resolve('common.save', AppLang.tr));
      await tester.scrollUntilVisible(
        save,
        500,
        scrollable: find.byType(Scrollable).last,
      );
      expect(save, findsOneWidget);
      await tester.tap(save);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.text(L10n.resolve('flights.saved.title', AppLang.tr)),
        findsOneWidget,
      );
      expect(
        find.text(L10n.resolve('flights.saved.body', AppLang.tr)),
        findsOneWidget,
      );

      await tester.tap(find.text(L10n.resolve('common.done', AppLang.tr)));
      await tester.pumpAndSettle();

      expect(find.text('Uçuş eklendi'), findsOneWidget);
      expect(find.text('HND · 14:30'), findsOneWidget);
      expect(find.text('KIX · 09:15'), findsOneWidget);
      expect(find.text('Elle düzenlenmiş orta gün'), findsOneWidget);
    },
  );
}

class _ResultPage extends StatefulWidget {
  const _ResultPage();

  @override
  State<_ResultPage> createState() => _ResultPageState();
}

class _ResultPageState extends State<_ResultPage> {
  Trip? _result;

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      body: Center(
        child: result == null
            ? ElevatedButton(
                onPressed: () async {
                  final saved = await context.push<Trip>('/flights');
                  if (mounted) setState(() => _result = saved);
                },
                child: const Text('Uçuş ekle'),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(tripHasFlightInfo(result)
                      ? 'Uçuş eklendi'
                      : 'Uçuş eksik'),
                  Text(
                    '${result.flights.outbound.last.airport} · '
                    '${result.preferences.outboundArrivalTime}',
                  ),
                  Text(
                    '${result.flights.returnLegs.first.airport} · '
                    '${result.preferences.returnDepartTime}',
                  ),
                  Text(result.days[2].theme),
                ],
              ),
      ),
    );
  }
}
