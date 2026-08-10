import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/domain/booking_windows.dart';
import 'package:rotori/domain/trip_factory.dart';
import 'package:rotori/domain/types.dart';

Trip _tripWithItems({List<String>? titles, DateTime? travelStart}) {
  final t = createEmptyTrip();
  if (travelStart != null) {
    t.preferences.travelDates.start =
        '${travelStart.year.toString().padLeft(4, '0')}-'
        '${travelStart.month.toString().padLeft(2, '0')}-'
        '${travelStart.day.toString().padLeft(2, '0')}';
  }
  final day = DayPlan(dayNumber: 1, date: t.preferences.travelDates.start, theme: 'Tokyo');
  for (var i = 0; i < (titles?.length ?? 0); i++) {
    day.items.add(TimelineItem(
      id: 'it-$i',
      title: titles![i],
      kind: TimelineItemKind.activity,
      time: '10:00',
    ));
  }
  t.days = [day];
  return t;
}

void main() {
  final future = DateTime.now().add(const Duration(days: 200));

  test('boş plan → uyarı yok', () {
    expect(detectBookingAlerts(_tripWithItems()), isEmpty);
  });

  test('Universal Studios plandaysa USJ uyarısı', () {
    final t = _tripWithItems(
        titles: ['Universal Studios Japan'], travelStart: future);
    final alerts = detectBookingAlerts(t);
    expect(alerts.map((a) => a.window.id), contains('usj-express'));
    final usj = alerts.firstWhere((a) => a.window.id == 'usj-express');
    // Bilet 60 gün önce açılıyor.
    expect(usj.eventOn.difference(usj.opensOn).inDays, 60);
  });

  test('Disney → Tokyo Disney uyarısı', () {
    final t = _tripWithItems(
        titles: ['Tokyo Disneyland günü'], travelStart: future);
    expect(detectBookingAlerts(t).map((a) => a.window.id),
        contains('tokyo-disney'));
  });

  test('Shinkansen anahtar kelime tetikler (30 gün önce)', () {
    final t = _tripWithItems(
        titles: ['Shinkansen Nozomi'], travelStart: future);
    final alerts = detectBookingAlerts(t);
    final sh = alerts.firstWhere((a) => a.window.id == 'shinkansen-smartex');
    expect(sh.eventOn.difference(sh.opensOn).inDays, 30);
  });

  test('Tokyo + Kyoto rotası varsa Shinkansen implicit tetikler', () {
    final t = _tripWithItems(travelStart: future);
    t.preferences.destinations
      ..add(TripDestination(
        id: 'tok',
        countryCode: 'JP',
        countryName: 'Japonya',
        city: 'Tokyo',
        arrivalDate: t.preferences.travelDates.start,
        departureDate: t.preferences.travelDates.start,
        order: 0,
      ))
      ..add(TripDestination(
        id: 'kyo',
        countryCode: 'JP',
        countryName: 'Japonya',
        city: 'Kyoto',
        arrivalDate: t.preferences.travelDates.start,
        departureDate: t.preferences.travelDates.end,
        order: 1,
      ));
    expect(detectBookingAlerts(t).map((a) => a.window.id),
        contains('shinkansen-smartex'));
  });

  test('Geçmiş etkinlik uyarı üretmez', () {
    final past = DateTime.now().subtract(const Duration(days: 30));
    final t = _tripWithItems(titles: ['Universal Studios'], travelStart: past);
    expect(detectBookingAlerts(t), isEmpty);
  });
}
