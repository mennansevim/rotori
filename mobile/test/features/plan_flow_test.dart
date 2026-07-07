// Plan adımı — gezi planı oluştur (fallback), reorder→resequence, keşif.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:japan_trip/domain/day_optimizer.dart';
import 'package:japan_trip/domain/trip_factory.dart';
import 'package:japan_trip/domain/types.dart';
import 'package:japan_trip/features/planner/planner_theme.dart';
import 'package:japan_trip/features/planner/steps/plan_step.dart';

Trip _tripWithDest() {
  final t = createEmptyTrip();
  t.preferences.destinations.add(TripDestination(
    id: 'd1',
    countryCode: 'JP',
    countryName: 'Japonya',
    city: 'Tokyo',
    arrivalDate: t.preferences.travelDates.start,
    departureDate: t.preferences.travelDates.end,
    order: 0,
  ));
  return t;
}

void main() {
  Widget harness(Trip trip) => ProviderScope(
        child: MaterialApp(
          theme: PT.theme(),
          home: Scaffold(
            body: PlanStep(trip: trip, onChange: (m) => m(trip)),
          ),
        ),
      );

  testWidgets('destinasyon yoksa uyarı gösterir', (tester) async {
    await tester.pumpWidget(harness(createEmptyTrip()));
    expect(find.text('Önce Rota adımında havaalanı/durak ekleyin.'),
        findsOneWidget);
  });

  testWidgets('boş plan "Henüz gezi planı yok" gösterir', (tester) async {
    await tester.pumpWidget(harness(_tripWithDest()));
    expect(find.text('Plan'), findsWidgets);
    expect(find.text('Henüz gezi planı yok'), findsOneWidget);
  });

  testWidgets('"Gezi planı oluştur" fallback ile günleri doldurur',
      (tester) async {
    final t = _tripWithDest();
    await tester.pumpWidget(harness(t));

    await tester.tap(find.text('✨ Gezi planı oluştur'));
    await tester.pumpAndSettle();

    // Kural tabanlı üretici en az bir güne aktivite ekler.
    expect(t.days.any((d) => d.items.isNotEmpty), isTrue);
    // Boş durum kartı artık yok.
    expect(find.text('Henüz gezi planı yok'), findsNothing);
  });

  test('reorder resequenceTimes ile saatleri kronolojik dizer', () {
    // resequenceTimes davranışı: görsel sırayı korur, saatleri artan dağıtır.
    final items = [
      TimelineItem(id: 'a', title: 'A', time: '14:00', scheduledTime: '14:00'),
      TimelineItem(id: 'b', title: 'B', time: '09:00', scheduledTime: '09:00'),
    ];
    // b'yi başa taşı (kullanıcı sürükledi) → saatler 09:00, 14:00 sırasına gelir.
    final reordered = [items[1], items[0]];
    final result = resequenceTimes(reordered);
    expect(result[0].time, '09:00');
    expect(result[1].time, '14:00');
    expect(result[0].id, 'b');
    expect(result[1].id, 'a');
  });
}
