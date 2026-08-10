import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/core/l10n.dart';
import 'package:rotori/domain/city_transfers.dart';
import 'package:rotori/domain/fill_empty_days.dart';
import 'package:rotori/domain/itinerary_generator.dart';
import 'package:rotori/domain/plan_warnings.dart';
import 'package:rotori/domain/trip_factory.dart';
import 'package:rotori/domain/types.dart';

TripDestination _dest(String city, int order, String arr, String dep,
        {String airport = ''}) =>
    TripDestination(
      id: 'd$order',
      countryCode: 'JP',
      countryName: 'Japonya',
      city: city,
      airport: airport,
      arrivalDate: arr,
      departureDate: dep,
      order: order,
    );

int? hhmm(String? v) {
  if (v == null || !v.contains(':')) return null;
  final p = v.split(':');
  final h = int.tryParse(p[0]), m = int.tryParse(p[1]);
  if (h == null || m == null) return null;
  return h * 60 + m;
}

void main() {
  for (final pace in Pace.values) {
    for (final arrival in ['02:00', '13:00', '21:00']) {
      test('diag pace=${pace.name} arrival=$arrival', () {
        final trip = createEmptyTrip();
        trip.preferences.pace = pace;
        trip.preferences.destinations = [
          _dest('Tokyo', 0, '2026-10-01', '2026-10-06', airport: 'HND'),
        ];
        trip.preferences.travelDates =
            TravelDates(start: '2026-10-01', end: '2026-10-06');
        trip.tripStart = '2026-10-01T$arrival:00';
        trip.tripEnd = '2026-10-06T20:00:00';
        trip.days = generateDaysBetween('2026-10-01', '2026-10-06');

        var days = generateItineraryFromTrip(trip, lang: AppLang.tr);
        days = fillEmptyDays(days, trip.preferences.destinations,
            lang: AppLang.tr);
        days = applyCityTransitions(days, trip.preferences.destinations);

        for (final day in days) {
          final times = day.items.map((i) => i.time).toList();
          final mins = times.map(hhmm).toList();
          final problems = <String>[];
          for (var i = 1; i < mins.length; i++) {
            if (mins[i] != null &&
                mins[i - 1] != null &&
                mins[i]! < mins[i - 1]!) {
              problems.add('OUT_OF_ORDER@$i');
            }
          }
          var maxGap = 0;
          for (var i = 1; i < mins.length; i++) {
            if (mins[i] != null && mins[i - 1] != null) {
              final g = mins[i]! - mins[i - 1]!;
              if (g > maxGap) maxGap = g;
            }
          }
          if (maxGap >= 240) problems.add('BIG_GAP=${maxGap}dk');
          final w = planWarningsFor(day);
          if (w.isNotEmpty) {
            problems.add('WARN=${w.map((x) => x.message).join(" | ")}');
          }
          if (problems.isNotEmpty) {
            final detail = day.items
                .map((i) => '${i.time}/${i.durationMin ?? "-"}/${i.title}')
                .join(' , ');
            // ignore: avoid_print
            print('[${pace.name}/$arrival] gün${day.dayNumber} '
                'n=${day.items.length} → ${problems.join(" ;; ")}\n    $detail');
          }
        }
      });
    }
  }
}
