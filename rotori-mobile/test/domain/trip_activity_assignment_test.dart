import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/domain/itinerary_optimizer.dart';
import 'package:rotori/domain/route_matrix.dart';
import 'package:rotori/domain/trip_activity_assignment.dart';

void main() {
  const engine = TripActivityAssignmentEngine();
  const hotel = TripLocation(
    id: 'hotel',
    name: 'Hotel',
    latitude: 0,
    longitude: 0,
  );
  final days = [
    _day(1, 9, 18, hotel),
    _day(2, 9, 18, hotel),
  ];

  test('full-day exclusive aktiviteyi boş güne tek başına ayırır', () {
    final result = engine.assign(
      days: days,
      activities: [
        _item('museum', 120, cluster: 'center'),
        _item(
          'usj',
          480,
          role: ActivityDayRole.fullDayExclusive,
          priority: ActivityPriority.mustDo,
        ),
        _item('castle', 120, cluster: 'center'),
      ],
    );

    expect(result.isSuccess, isTrue, reason: result.failure?.message);
    final specialDay = result.assignments.entries.singleWhere(
      (entry) => entry.value.any((item) => item.activity.id == 'usj'),
    );
    expect(specialDay.value.map((item) => item.activity.id), ['usj']);
  });

  test('dolu ilk gün yerine aynı şehirdeki diğer günü dener', () {
    final result = engine.assign(
      days: [
        _day(1, 9, 11, hotel),
        _day(2, 9, 18, hotel),
      ],
      activities: [
        _item('fixed', 90, fixedDayIndex: 1),
        _item('move-me', 180),
      ],
    );

    expect(result.isSuccess, isTrue);
    expect(
      result.assignments[2]!.map((item) => item.activity.id),
      contains('move-me'),
    );
    expect(result.dropped, isEmpty);
  });

  test('imkansız must-do için typed failure verir ve drop etmez', () {
    final result = engine.assign(
      days: [_day(1, 9, 10, hotel)],
      activities: [
        _item('must', 180, priority: ActivityPriority.mustDo),
      ],
    );

    expect(result.isSuccess, isFalse);
    expect(
      result.failure?.code,
      AssignmentFailureCode.protectedActivityInfeasible,
    );
    expect(result.dropped, isEmpty);
  });

  test('aynı girdide deterministik bucket sırası üretir', () {
    final input = [
      _item('b', 60, cluster: 'east'),
      _item('a', 60, cluster: 'east'),
      _item('c', 60, cluster: 'west'),
    ];
    final first = engine.assign(days: days, activities: input);
    final second =
        engine.assign(days: days, activities: input.reversed.toList());
    List<List<String>> ids(TripActivityAssignmentResult result) =>
        result.assignments.values
            .map((items) => items.map((item) => item.activity.id).toList())
            .toList();

    expect(ids(first), ids(second));
  });
}

TripAssignmentDay _day(
  int index,
  int startHour,
  int endHour,
  TripLocation hotel,
) =>
    TripAssignmentDay(
      index: index,
      city: 'Osaka',
      type: AssignmentDayType.full,
      startTime: DateTime(2026, 8, index, startHour),
      endTime: DateTime(2026, 8, index, endHour),
      hotel: hotel,
    );

AssignableTripActivity _item(
  String id,
  int duration, {
  String? cluster,
  ActivityPriority priority = ActivityPriority.normal,
  ActivityDayRole role = ActivityDayRole.normal,
  int? fixedDayIndex,
}) =>
    AssignableTripActivity(
      city: 'Osaka',
      dayRole: role,
      fixedDayIndex: fixedDayIndex,
      activity: OptimizationActivity(
        id: id,
        name: id,
        day: DateTime(2026, 8, 1),
        location: TripLocation(
          id: id,
          name: id,
          latitude: 1,
          longitude: 1,
          clusterId: cluster,
        ),
        durationMinutes: duration,
        minimumDurationMinutes: duration,
        priority: priority,
      ),
    );
