// GEÇİCİ görsel kontrol girişi — animasyonlu rota haritasını doğrudan açar.
// flutter run -d web-server -t lib/preview_route_map.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/l10n.dart';
import 'domain/types.dart';
import 'features/viewer/route_map_sheet.dart';

void main() => runApp(const ProviderScope(child: _App()));

Trip _kyotoTrip() => Trip(
      id: 'demo',
      slug: 'demo',
      title: 'Kyoto',
      timezone: 'Asia/Tokyo',
      tripStart: '2026-05-13',
      tripEnd: '2026-05-16',
      flights: TripFlights(),
      preferences: TripPreferences(
        travelDates: TravelDates(start: '2026-05-13', end: '2026-05-16'),
        pace: Pace.moderate,
        destinations: [
          TripDestination(
            id: 'd1',
            countryCode: 'JP',
            countryName: 'Japonya',
            city: 'Kyoto',
            lat: 35.0116,
            lng: 135.7681,
            arrivalDate: '2026-05-13',
            departureDate: '2026-05-16',
            order: 0,
          ),
        ],
      ),
      days: [
        DayPlan(
          dayNumber: 2,
          date: '2026-05-13',
          theme: 'Kyoto klasikleri',
          items: [
            TimelineItem(id: 'a', title: 'Kinkaku-ji', time: '09:00'),
            TimelineItem(id: 'b', title: 'Arashiyama', time: '11:30'),
            TimelineItem(id: 'c', title: 'Nishiki Pazarı', time: '14:00'),
            TimelineItem(id: 'd', title: 'Kiyomizu-dera', time: '16:00'),
            TimelineItem(id: 'e', title: 'Gion', time: '18:30'),
          ],
        ),
      ],
    );

class _App extends StatelessWidget {
  const _App();

  @override
  Widget build(BuildContext context) {
    return LanguageScope(
      lang: AppLang.tr,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Builder(
          builder: (ctx) {
            final trip = _kyotoTrip();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              showRouteMapSheet(
                context: ctx,
                trip: trip,
                day: trip.days.first,
              );
            });
            return const Scaffold(
              backgroundColor: Color(0xFF101014),
              body: Center(child: Text('preview')),
            );
          },
        ),
      ),
    );
  }
}
