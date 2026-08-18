import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/core/l10n.dart';
import 'package:rotori/domain/types.dart';
import 'package:rotori/features/plans/plans_list_screen.dart';

Trip _tripWithDestinations(List<TripDestination> destinations) => Trip(
      id: 'trip-1',
      slug: 'tokyo-kyoto',
      title: 'Japonya gezisi',
      timezone: 'Asia/Tokyo',
      tripStart: '2026-08-01',
      tripEnd: '2026-08-06',
      flights: TripFlights(),
      preferences: TripPreferences(
        travelDates: TravelDates(start: '2026-08-01', end: '2026-08-06'),
        pace: Pace.moderate,
        destinations: destinations,
      ),
      days: [
        DayPlan(dayNumber: 1, date: '2026-08-01', theme: 'Tokyo'),
        DayPlan(dayNumber: 2, date: '2026-08-02', theme: 'Tokyo'),
        DayPlan(dayNumber: 3, date: '2026-08-03', theme: 'Kyoto'),
      ],
    );

TripDestination _destination({
  required String city,
  required int order,
}) =>
    TripDestination(
      id: city.toLowerCase(),
      countryCode: 'JP',
      countryName: 'Japonya',
      city: city,
      arrivalDate: '2026-08-01',
      departureDate: '2026-08-06',
      order: order,
    );

void main() {
  test('plan city line lists destinations in route order', () {
    final trip = _tripWithDestinations([
      _destination(city: 'Kyoto', order: 2),
      _destination(city: 'Tokyo', order: 1),
    ]);

    expect(planDestinationLine(trip), 'Tokyo, Kyoto, Japonya');
  });

  test('plan destination count is localized for Turkish and English', () {
    final trip = _tripWithDestinations([
      _destination(city: 'Tokyo', order: 1),
      _destination(city: 'Kyoto', order: 2),
    ]);

    expect(planDestinationCount(trip, AppLang.tr), '2 şehir');
    expect(planDestinationCount(trip, AppLang.en), '2 cities');
  });

  test('plan day count falls back to inclusive date range', () {
    final trip = _tripWithDestinations([
      _destination(city: 'Tokyo', order: 1),
    ])
      ..days.clear();

    expect(planDayCount(trip), 6);
  });

  test('plan date range follows reference compact format', () {
    final trip = _tripWithDestinations([
      _destination(city: 'Tokyo', order: 1),
    ]);

    expect(planDateRange(trip, AppLang.en), 'Aug 1–6, 2026');
    expect(planDateRange(trip, AppLang.tr), '1–6 Ağu 2026');
  });
}
