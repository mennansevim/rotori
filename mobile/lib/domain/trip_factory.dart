// TypeScript packages/shared/src/tripFactory.ts'in Dart karşılığı (MVP).
// createEmptyTrip: boş bir Trip iskeletidir.

import 'dart:math';
import 'types.dart';

/// Basit slug üretici — timestamp base-36.
String _slug() =>
    'yeni-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';

/// UUID benzeri (tam RFC4122 değil ama JSON DB'de yeterli).
String _uuid() {
  final r = Random.secure();
  String h(int n) => List.generate(n, (_) => r.nextInt(16).toRadixString(16)).join();
  return '${h(8)}-${h(4)}-${h(4)}-${h(4)}-${h(12)}';
}

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

DateTime _addDays(DateTime d, int days) => d.add(Duration(days: days));

/// 7 günlük boş Trip, tarih bugünden 14 gün sonra başlar.
/// Not: TS'te generateDaysBetween günleri de dolduruyordu; MVP burada boş liste
/// döndürür — Faz 3b'de tam port yapılacak.
Trip createEmptyTrip({Trip? overrides}) {
  final now = DateTime.now();
  final start = _addDays(now, 14);
  final end = _addDays(start, 6);
  final startStr = _ymd(start);
  final endStr = _ymd(end);

  return Trip(
    id: _uuid(),
    slug: _slug(),
    title: 'Japonya Turu',
    subtitle: '',
    timezone: 'Asia/Tokyo',
    tripStart: '${startStr}T08:00:00',
    tripEnd: '${endStr}T20:00:00',
    flights: TripFlights(
      outbound: [
        FlightLeg(city: '', airport: '', dateTime: '${startStr}T10:00:00'),
        FlightLeg(city: '', airport: '', dateTime: '${startStr}T18:00:00'),
      ],
      returnLegs: [
        FlightLeg(city: '', airport: '', dateTime: '${endStr}T10:00:00'),
        FlightLeg(city: '', airport: '', dateTime: '${endStr}T20:00:00'),
      ],
    ),
    hotels: [],
    tickets: [],
    preferences: TripPreferences(
      travelDates: TravelDates(start: startStr, end: endStr),
      destinationCountry: 'JP',
      pace: Pace.moderate,
      partySize: 2,
      maxStepsPerDay: kWalkingTargetSteps[WalkingTarget.moderate],
      planMeals: true,
      mealBudgetPerPerson: 2500,
      mealBudgetCurrency: 'JPY',
      walkingTarget: WalkingTarget.moderate,
      transportPreference: TransportPreference.mixed,
      paymentPreference: PaymentPreference.creditAndCash,
    ),
    days: const [], // TODO: generateDaysBetween portu
    deadlines: Deadlines(),
  );
}
