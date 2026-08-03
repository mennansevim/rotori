import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:japan_trip/domain/plan_schedule_engine.dart';
import 'package:japan_trip/domain/types.dart';
import 'package:japan_trip/features/plans/plan_edit_session.dart';

Trip _trip() => Trip(
      id: 'trip',
      slug: 'trip',
      title: 'Plan',
      timezone: 'Asia/Tokyo',
      tripStart: '2026-08-01',
      tripEnd: '2026-08-01',
      flights: TripFlights(),
      preferences: TripPreferences(
        travelDates: TravelDates(start: '2026-08-01', end: '2026-08-01'),
        pace: Pace.moderate,
      ),
      days: [
        DayPlan(
          dayNumber: 1,
          date: '2026-08-01',
          theme: 'Tokyo',
          items: [
            TimelineItem(
              id: 'a',
              title: 'A',
              time: '09:00',
              scheduledTime: '09:00',
              durationMin: 60,
            ),
            TimelineItem(
              id: 'b',
              title: 'B',
              time: '10:15',
              scheduledTime: '10:15',
              durationMin: 60,
            ),
          ],
        ),
      ],
    );

void main() {
  test('optimistic state yayınlar ve başarılı kaydı korur', () async {
    final states = <PlanEditState>[];
    final saved = <Trip>[];
    final session = PlanEditSession(
      initialTrip: _trip(),
      persist: (trip) async => saved.add(trip),
      onChanged: states.add,
    );

    final result = await session.execute(const MoveActivityWithinDay(
      dayNumber: 1,
      activityId: 'b',
      targetIndex: 0,
    ));

    expect(result.isSuccess, isTrue);
    expect(states.first.isSaving, isTrue);
    expect(states.last.isSaving, isFalse);
    expect(session.current.days.single.items.first.id, 'b');
    expect(saved.single.days.single.items.first.id, 'b');
  });

  test('repository yerel yazım hatasında rollback yapar', () async {
    final states = <PlanEditState>[];
    final session = PlanEditSession(
      initialTrip: _trip(),
      persist: (_) async => throw StateError('disk full'),
      onChanged: states.add,
    );

    final result = await session.execute(const DeleteActivity(
      dayNumber: 1,
      activityId: 'a',
    ));

    expect(result.isSuccess, isFalse);
    expect(session.current.days.single.items.map((e) => e.id), ['a', 'b']);
    expect(states.last.saveFailed, isTrue);
    expect(session.canUndo, isFalse);
  });

  test('undo eski snapshotı geri getirip kaydeder', () async {
    final saved = <Trip>[];
    final session = PlanEditSession(
      initialTrip: _trip(),
      persist: (trip) async => saved.add(trip),
      onChanged: (_) {},
    );
    await session.execute(
      const DeleteActivity(dayNumber: 1, activityId: 'a'),
    );

    expect(await session.undo(), isTrue);
    expect(session.current.days.single.items.map((e) => e.id), ['a', 'b']);
    expect(saved, hasLength(2));
  });

  test('hızlı komutları sıraya alır ve son state kaybolmaz', () async {
    final firstWrite = Completer<void>();
    var writes = 0;
    final session = PlanEditSession(
      initialTrip: _trip(),
      persist: (_) async {
        writes++;
        if (writes == 1) await firstWrite.future;
      },
      onChanged: (_) {},
    );

    final first = session.execute(const MoveActivityWithinDay(
      dayNumber: 1,
      activityId: 'b',
      targetIndex: 0,
    ));
    final second = session.execute(const UpdateActivityDuration(
      dayNumber: 1,
      activityId: 'b',
      durationMinutes: 90,
    ));
    firstWrite.complete();
    await Future.wait([first, second]);

    expect(writes, 2);
    expect(session.current.days.single.items.first.id, 'b');
    expect(session.current.days.single.items.first.durationMin, 90);
  });

  test('geçersiz command state veya repositoryyi değiştirmez', () async {
    var writes = 0;
    final session = PlanEditSession(
      initialTrip: _trip(),
      persist: (_) async => writes++,
      onChanged: (_) {},
    );

    final result = await session.execute(const UpdateActivityTime(
      dayNumber: 1,
      activityId: 'b',
      startMinutes: 9 * 60,
    ));

    expect(result.failure!.code, PlanEditFailureCode.timeConflict);
    expect(writes, 0);
    expect(session.current.days.single.items[1].time, '10:15');
  });
}
