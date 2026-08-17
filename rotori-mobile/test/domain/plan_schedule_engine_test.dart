import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/domain/plan_schedule_engine.dart';
import 'package:rotori/domain/route_execution.dart';
import 'package:rotori/domain/route_matrix.dart';
import 'package:rotori/domain/types.dart';

TimelineItem item(
  String id,
  String time, {
  int duration = 60,
  TimelineItemKind kind = TimelineItemKind.activity,
  ActivityLockType lockType = ActivityLockType.none,
  bool canChangeDay = true,
  bool canChangeTime = true,
  bool canReorder = true,
  bool canDelete = true,
  String? fixedStart,
}) =>
    TimelineItem(
      id: id,
      title: id,
      time: time,
      scheduledTime: time,
      durationMin: duration,
      kind: kind,
      lockType: lockType,
      fixedStartTime: fixedStart,
      canChangeDay: canChangeDay,
      canChangeTime: canChangeTime,
      canReorder: canReorder,
      canDelete: canDelete,
    );

Trip tripWith(List<DayPlan> days) => Trip(
      id: 'trip',
      slug: 'trip',
      title: 'Plan',
      timezone: 'Asia/Tokyo',
      tripStart: '2026-08-01',
      tripEnd: '2026-08-03',
      flights: TripFlights(),
      preferences: TripPreferences(
        travelDates: TravelDates(start: '2026-08-01', end: '2026-08-03'),
        pace: Pace.moderate,
      ),
      days: days,
    );

DayPlan day(int number, List<TimelineItem> items) => DayPlan(
      dayNumber: number,
      date: '2026-08-0$number',
      theme: 'Gün $number',
      items: items,
    );

TimelineItem findItem(Trip trip, String id) => trip.days
    .expand((day) => day.items)
    .firstWhere((candidate) => candidate.id == id);

void main() {
  const engine = PlanScheduleEngine();

  test('DeleteTicket removes ticket and clears city transition link', () {
    final trip = tripWith([day(1, [])]);
    trip.days.single.cityTransition = const CityTransitionPlan(
      fromCity: 'Tokyo',
      toCity: 'Kyoto',
      mode: 'shinkansen',
      linkedTicketId: 't1',
    );
    trip.tickets.add(Ticket(
      id: 't1',
      kind: 'train',
      label: 'Tokyo → Kyoto',
      purchased: true,
    ));

    final result = const PlanScheduleEngine().apply(
      trip,
      const DeleteTicket(ticketId: 't1'),
    );

    expect(result.isSuccess, isTrue);
    expect(result.trip!.tickets, isEmpty);
    expect(result.trip!.days.single.cityTransition!.linkedTicketId, isNull);
  });

  test('DeleteTicket unlocks only its linked ticketed activity', () {
    final locked = item('teamlab', '14:00')
      ..lockType = ActivityLockType.ticketedEvent
      ..fixedStartTime = '14:00'
      ..canChangeTime = false
      ..canReorder = false;
    final trip = tripWith([
      day(1, [locked])
    ]);
    trip.tickets.add(Ticket(
      id: 't1',
      kind: 'attraction',
      label: 'teamLab',
      purchased: true,
      linkedActivityId: 'teamlab',
    ));

    final result = const PlanScheduleEngine().apply(
      trip,
      const DeleteTicket(ticketId: 't1'),
    );

    final activity = result.trip!.days.single.items.single;
    expect(activity.lockType, ActivityLockType.none);
    expect(activity.fixedStartTime, isNull);
    expect(activity.fixedEndTime, isNull);
    expect(activity.canChangeTime, isTrue);
    expect(activity.canChangeDay, isTrue);
    expect(activity.canReorder, isTrue);
    expect(activity.canDelete, isTrue);
    expect(activity.lockReason, isNull);
  });

  group('biletli etkinlik planlama', () {
    test('etkinlik ve bilet atomik eklenir; gün sabit saatin çevresine dizilir',
        () {
      final original = tripWith([
        day(1, [
          item('a', '09:00', duration: 120),
          item('b', '11:15', duration: 120),
          item('c', '13:30', duration: 120),
        ]),
      ]);
      final result = engine.apply(
        original,
        AddTicketedActivity(
          dayNumber: 1,
          activity: item('teamlab', '12:00', duration: 180),
          ticket: Ticket(
            id: 'ticket-teamlab',
            kind: TicketKind.attraction.name,
            label: 'teamlab',
            purchased: true,
            entryTime: '12:00',
            durationMin: 180,
            arrivalBufferMin: 30,
          ),
        ),
      );

      expect(result.isSuccess, isTrue);
      final updated = result.trip!;
      expect(updated.days.single.items.map((e) => e.id),
          ['a', 'teamlab', 'b', 'c']);
      expect(findItem(updated, 'teamlab').fixedStartTime, '12:00');
      expect(findItem(updated, 'teamlab').lockType,
          ActivityLockType.ticketedEvent);
      expect(findItem(updated, 'teamlab').canChangeDay, isFalse);
      expect(findItem(updated, 'teamlab').arrivalBufferMin, 30);
      expect(findItem(updated, 'b').time, '15:15');
      expect(updated.tickets, hasLength(1));
      expect(updated.tickets.single.linkedActivityId, 'teamlab');
      expect(updated.tickets.single.visitDate, '2026-08-01');
      expect(original.tickets, isEmpty, reason: 'girdi değişmemeli');
      expect(original.days.single.items.map((e) => e.id), ['a', 'b', 'c']);
    });

    test('bilet tarihi etkinliği doğru güne taşır ve JSON alanları korunur',
        () {
      final result = engine.apply(
        tripWith([
          day(1, [item('teamlab', '10:00', duration: 90)]),
          day(2, [item('breakfast', '09:00', duration: 60)]),
        ]),
        AttachTicketToActivity(
          activityId: 'teamlab',
          ticket: Ticket(
            id: 'ticket-2',
            kind: TicketKind.attraction.name,
            label: 'teamLab Planets',
            purchased: true,
            visitDate: '2026-08-02',
            entryTime: '14:30',
            durationMin: 180,
            arrivalBufferMin: 45,
          ),
        ),
      );

      expect(result.isSuccess, isTrue);
      expect(result.trip!.days.first.items, isEmpty);
      final moved = findItem(result.trip!, 'teamlab');
      expect(moved.time, '14:30');
      expect(moved.fixedStartTime, '14:30');
      expect(moved.durationMin, 180);
      expect(moved.arrivalBufferMin, 45);
      expect(result.trip!.days[1].items.map((e) => e.id),
          ['breakfast', 'teamlab']);

      final restored = Trip.fromJson(result.trip!.toJson());
      final ticket = restored.tickets.single;
      expect(ticket.linkedActivityId, 'teamlab');
      expect(ticket.entryTime, '14:30');
      expect(ticket.durationMin, 180);
      expect(ticket.arrivalBufferMin, 45);
    });
  });

  group('aynı gün sıralama ve saatleme', () {
    test('aktivite yukarı taşınır; süre korunur ve sonrası yeniden saatlenir',
        () {
      final original = tripWith([
        day(1, [item('a', '09:00'), item('b', '10:15'), item('c', '11:30')]),
      ]);
      final result = engine.apply(
        original,
        const MoveActivityWithinDay(
          dayNumber: 1,
          activityId: 'c',
          targetIndex: 1,
        ),
      );
      expect(result.isSuccess, isTrue);
      expect(result.trip!.days.single.items.map((e) => e.id), ['a', 'c', 'b']);
      expect(findItem(result.trip!, 'c').time, '10:15');
      expect(findItem(result.trip!, 'b').time, '11:30');
      expect(findItem(result.trip!, 'c').durationMin, 60);
      expect(original.days.single.items.map((e) => e.id), ['a', 'b', 'c'],
          reason: 'motor girdiyi değiştirmemeli');
    });

    test('aktivite aşağı taşınır', () {
      final result = engine.apply(
        tripWith([
          day(1, [item('a', '09:00'), item('b', '10:15'), item('c', '11:30')]),
        ]),
        const MoveActivityWithinDay(
          dayNumber: 1,
          activityId: 'a',
          targetIndex: 2,
        ),
      );
      expect(result.trip!.days.single.items.map((e) => e.id), ['b', 'c', 'a']);
    });

    test('günün başına ve sonuna taşıma çalışır', () {
      final base = tripWith([
        day(1, [item('a', '09:00'), item('b', '10:15'), item('c', '11:30')]),
      ]);
      final first = engine.apply(
        base,
        const MoveActivityWithinDay(
          dayNumber: 1,
          activityId: 'c',
          targetIndex: 0,
        ),
      );
      expect(first.trip!.days.single.items.first.id, 'c');
      final last = engine.apply(
        first.trip!,
        const MoveActivityWithinDay(
          dayNumber: 1,
          activityId: 'c',
          targetIndex: 2,
        ),
      );
      expect(last.trip!.days.single.items.last.id, 'c');
    });

    test('hızlı ardışık komutlar aynı snapshot üzerinde bozulmaz', () {
      var current = tripWith([
        day(1, [item('a', '09:00'), item('b', '10:15'), item('c', '11:30')]),
      ]);
      for (final command in const [
        MoveActivityWithinDay(
          dayNumber: 1,
          activityId: 'c',
          targetIndex: 0,
        ),
        MoveActivityWithinDay(
          dayNumber: 1,
          activityId: 'a',
          targetIndex: 2,
        ),
      ]) {
        current = engine.apply(current, command).trip!;
      }
      expect(current.days.single.items.map((e) => e.id), ['c', 'b', 'a']);
      expect(engine.validate(current), isNull);
    });
  });

  group('günler arası taşıma', () {
    test('bırakma saati iki komşu arasındaki uygun pencerenin ortasıdır', () {
      final trip = tripWith([
        day(1, [item('x', '16:00')]),
        day(2, [
          item('a', '09:00'),
          item('b', '14:00'),
        ]),
      ]);

      final suggestion = engine.suggestedStartMinutesForInsertion(
        trip,
        sourceDayNumber: 1,
        activityId: 'x',
        targetDayNumber: 2,
        targetIndex: 1,
      );

      expect(suggestion, 11 * 60 + 30);
    });

    test('drag taşımada kaynak ve geçerli hedef saatleri korunur', () {
      final original = tripWith([
        day(1, [
          item('source-before', '09:00'),
          item('x', '10:15'),
          item('source-after', '14:00'),
        ]),
        day(2, [
          item('target-before', '09:00'),
          item('target-after', '14:00'),
        ]),
      ]);
      final suggestion = engine.suggestedStartMinutesForInsertion(
        original,
        sourceDayNumber: 1,
        activityId: 'x',
        targetDayNumber: 2,
        targetIndex: 1,
      );
      final result = engine.apply(
        original,
        MoveActivityToDay(
          sourceDayNumber: 1,
          activityId: 'x',
          targetDayNumber: 2,
          targetIndex: 1,
          startMinutes: suggestion,
          preserveExistingTimes: true,
        ),
      );

      expect(result.isSuccess, isTrue);
      expect(findItem(result.trip!, 'source-after').time, '14:00');
      expect(findItem(result.trip!, 'x').time, '11:30');
      expect(findItem(result.trip!, 'target-after').time, '14:00');
    });

    test('aktivite boş güne taşınır ve kaynak gün bozulmaz', () {
      final original = tripWith([
        day(1, [item('a', '09:00'), item('b', '10:15')]),
        day(2, []),
      ]);
      final result = engine.apply(
        original,
        const MoveActivityToDay(
          sourceDayNumber: 1,
          activityId: 'b',
          targetDayNumber: 2,
        ),
      );
      expect(result.isSuccess, isTrue);
      expect(result.trip!.days[0].items.single.time, '09:00');
      expect(result.trip!.days[1].items.single.id, 'b');
      expect(result.trip!.days[1].items.single.movedFromDay, 1);
    });

    test('dolu güne yalnızca hedefte gereken saatleri kaydırarak taşır', () {
      final result = engine.apply(
        tripWith([
          day(1, [item('x', '14:00')]),
          day(2, [item('a', '09:00'), item('b', '12:00')]),
        ]),
        const MoveActivityToDay(
          sourceDayNumber: 1,
          activityId: 'x',
          targetDayNumber: 2,
          targetIndex: 1,
        ),
      );
      expect(result.trip!.days[1].items.map((e) => e.id), ['a', 'x', 'b']);
      expect(findItem(result.trip!, 'a').time, '09:00');
      expect(findItem(result.trip!, 'x').time, '10:15');
      expect(findItem(result.trip!, 'b').time, '11:30');
    });

    test('seçilen hedef saat korunur; kaynak ve hedef gün yeniden hizalanır',
        () {
      final result = engine.apply(
        tripWith([
          day(1, [
            item('a', '09:00', duration: 30),
            item('x', '10:00', duration: 30),
            item('b', '11:00', duration: 30),
          ]),
          day(2, [
            item('y', '09:00', duration: 30),
            item('z', '12:00', duration: 30),
          ]),
        ]),
        const MoveActivityToDay(
          sourceDayNumber: 1,
          activityId: 'x',
          targetDayNumber: 2,
          startMinutes: 10 * 60,
        ),
      );
      expect(result.isSuccess, isTrue);
      expect(findItem(result.trip!, 'b').time, '09:45');
      expect(findItem(result.trip!, 'x').time, '10:00');
      expect(findItem(result.trip!, 'z').time, '10:45');
    });

    test('hedef gün için yalnızca 15 dakikalık tamponlara sığan slotlar döner',
        () {
      final trip = tripWith([
        day(1, [item('x', '10:45', duration: 15)]),
        day(2, [
          item('a', '08:45', duration: 15),
          item('b', '09:30', duration: 15),
          item('c', '10:45', duration: 15),
          item('d', '11:30', duration: 15),
        ]),
      ]);

      final slots = engine.availableStartMinutes(
        trip,
        sourceDayNumber: 1,
        activityId: 'x',
        targetDayNumber: 2,
        durationMinutes: 15,
        firstMinute: 8 * 60 + 30,
        lastMinute: 12 * 60,
      );

      expect(slots, containsAll([10 * 60, 12 * 60]));
      for (final blocked in [
        8 * 60 + 30,
        8 * 60 + 45,
        9 * 60,
        9 * 60 + 15,
        9 * 60 + 30,
        9 * 60 + 45,
        10 * 60 + 30,
        10 * 60 + 45,
        11 * 60,
        11 * 60 + 15,
        11 * 60 + 30,
        11 * 60 + 45,
      ]) {
        expect(slots, isNot(contains(blocked)),
            reason: '$blocked pasif olmalı');
      }
    });

    test('taşıma duplicate üretmez', () {
      final result = engine.apply(
        tripWith([
          day(1, [item('x', '09:00')]),
          day(2, [item('a', '09:00')]),
        ]),
        const MoveActivityToDay(
          sourceDayNumber: 1,
          activityId: 'x',
          targetDayNumber: 2,
        ),
      );
      expect(
        result.trip!.days.expand((day) => day.items).where((e) => e.id == 'x'),
        hasLength(1),
      );
    });

    test('aynı komut ikinci kez çalışırsa veri bozulmaz', () {
      final first = engine.apply(
        tripWith([
          day(1, [item('x', '09:00')]),
          day(2, []),
        ]),
        const MoveActivityToDay(
          sourceDayNumber: 1,
          activityId: 'x',
          targetDayNumber: 2,
        ),
      );
      final second = engine.apply(
        first.trip!,
        const MoveActivityToDay(
          sourceDayNumber: 1,
          activityId: 'x',
          targetDayNumber: 2,
        ),
      );
      expect(second.failure!.code, PlanEditFailureCode.activityNotFound);
      expect(first.trip!.days.expand((d) => d.items), hasLength(1));
    });

    test('başka bir gündeki eski çakışma günler arası taşımayı engellemez', () {
      final original = tripWith([
        day(1, [
          item('otel transferi', '14:00'),
          item(
            'check-in',
            '15:00',
            duration: 120,
            lockType: ActivityLockType.hotel,
            fixedStart: '15:00',
            canChangeDay: false,
            canChangeTime: false,
            canReorder: false,
            canDelete: false,
          ),
          item('akşam yemeği', '19:30', kind: TimelineItemKind.meal),
        ]),
        day(2, [item('kahvaltı', '09:00', kind: TimelineItemKind.meal)]),
      ]);

      final result = engine.apply(
        original,
        const MoveActivityToDay(
          sourceDayNumber: 1,
          activityId: 'akşam yemeği',
          targetDayNumber: 2,
        ),
      );

      expect(result.isSuccess, isTrue);
      expect(findItem(result.trip!, 'akşam yemeği').movedFromDay, 1);
      expect(result.trip!.days[0].items.map((e) => e.id),
          ['otel transferi', 'check-in']);
    });
  });

  group('drag ile gün içi kesin aralığa bırakma', () {
    test('bırakılan aktivite araya girer ve sonraki geçerli saat korunur', () {
      final original = tripWith([
        day(1, [
          item('a', '09:00'),
          item('b', '11:30'),
          item('c', '14:00'),
        ]),
      ]);
      final suggestion = engine.suggestedStartMinutesForInsertion(
        original,
        sourceDayNumber: 1,
        activityId: 'c',
        targetDayNumber: 1,
        targetIndex: 1,
      );
      final result = engine.apply(
        original,
        MoveActivityWithinDay(
          dayNumber: 1,
          activityId: 'c',
          targetIndex: 1,
          startMinutes: suggestion,
          preserveExistingTimes: true,
        ),
      );

      expect(result.isSuccess, isTrue);
      expect(result.trip!.days.single.items.map((e) => e.id), ['a', 'c', 'b']);
      expect(findItem(result.trip!, 'c').time, '10:15');
      expect(findItem(result.trip!, 'b').time, '11:30');
    });
  });

  group('manuel saat, süre ve yemek kuralı', () {
    test('manuel saat değişikliği çakışmasızsa sonrası gerektiği kadar kayar',
        () {
      final result = engine.apply(
        tripWith([
          day(1, [item('a', '09:00'), item('b', '11:00'), item('c', '13:00')]),
        ]),
        const UpdateActivityTime(
          dayNumber: 1,
          activityId: 'b',
          startMinutes: 12 * 60,
        ),
      );
      expect(result.isSuccess, isTrue);
      expect(findItem(result.trip!, 'b').time, '12:00');
      expect(findItem(result.trip!, 'c').time, '13:15');
    });

    test('saat değişikliğinden sonraki günlük akış otomatik yeniden hesaplanır',
        () {
      final result = engine.apply(
        tripWith([
          day(1, [
            item('airport', '08:45', duration: 30),
            item('sensoji', '09:30', duration: 60),
            item('ueno', '10:45', duration: 15),
            item('lunch', '11:30', duration: 75, kind: TimelineItemKind.meal),
            item('museum', '13:00'),
          ]),
        ]),
        const UpdateActivityTime(
          dayNumber: 1,
          activityId: 'ueno',
          startMinutes: 11 * 60 + 15,
        ),
      );

      expect(result.isSuccess, isTrue);
      expect(findItem(result.trip!, 'airport').time, '08:45');
      expect(findItem(result.trip!, 'sensoji').time, '09:30');
      expect(findItem(result.trip!, 'ueno').time, '11:15');
      expect(findItem(result.trip!, 'lunch').time, '11:45');
      expect(findItem(result.trip!, 'museum').time, '13:15');
    });

    test(
        'eski transfer/check-in çakışması akşam yemeğini 18:30 veya 17:30 yapmayı engellemez',
        () {
      Trip original() => tripWith([
            day(1, [
              item('otel transferi', '14:00'),
              item(
                'check-in',
                '15:00',
                duration: 120,
                lockType: ActivityLockType.hotel,
                fixedStart: '15:00',
                canChangeDay: false,
                canChangeTime: false,
                canReorder: false,
                canDelete: false,
              ),
              item('akşam yemeği', '19:30', kind: TimelineItemKind.meal),
            ]),
          ]);

      for (final minutes in [18 * 60 + 30, 17 * 60 + 30]) {
        final result = engine.apply(
          original(),
          UpdateActivityTime(
            dayNumber: 1,
            activityId: 'akşam yemeği',
            startMinutes: minutes,
          ),
        );
        expect(result.isSuccess, isTrue, reason: '$minutes kabul edilmeli');
        expect(
          findItem(result.trip!, 'akşam yemeği').time,
          minutes == 18 * 60 + 30 ? '18:30' : '17:30',
        );
      }
    });

    test('önceki aktiviteyle çakışan manuel saat engellenir', () {
      final result = engine.apply(
        tripWith([
          day(1, [item('a', '09:00', duration: 90), item('b', '11:00')]),
        ]),
        const UpdateActivityTime(
          dayNumber: 1,
          activityId: 'b',
          startMinutes: 10 * 60,
        ),
      );
      expect(result.failure!.code, PlanEditFailureCode.timeConflict);
      expect(result.failure!.overlapMinutes, 45);
    });

    test('süre uzayınca sonraki aktiviteler kayar', () {
      final result = engine.apply(
        tripWith([
          day(1, [item('a', '09:00'), item('b', '10:15')]),
        ]),
        const UpdateActivityDuration(
          dayNumber: 1,
          activityId: 'a',
          durationMinutes: 120,
        ),
      );
      expect(findItem(result.trip!, 'b').time, '11:15');
    });

    test('saat ve süre tek atomik komutla güncellenir', () {
      final result = engine.apply(
        tripWith([
          day(1, [item('a', '09:00'), item('b', '10:15')]),
        ]),
        const UpdateActivitySchedule(
          dayNumber: 1,
          activityId: 'a',
          startMinutes: 8 * 60,
          durationMinutes: 120,
        ),
      );
      expect(result.isSuccess, isTrue);
      expect(findItem(result.trip!, 'a').time, '08:00');
      expect(findItem(result.trip!, 'a').durationMin, 120);
      expect(findItem(result.trip!, 'b').time, '10:15');
    });

    test('süre kısalınca önceki aktiviteler değişmez', () {
      final result = engine.apply(
        tripWith([
          day(1, [item('a', '09:00', duration: 120), item('b', '11:15')]),
        ]),
        const UpdateActivityDuration(
          dayNumber: 1,
          activityId: 'a',
          durationMinutes: 60,
        ),
      );
      expect(findItem(result.trip!, 'a').time, '09:00');
      expect(findItem(result.trip!, 'b').time, '10:15');
    });

    test('yemek sonrası da ortak 15 dakikalık tampon bırakılır', () {
      final result = engine.apply(
        tripWith([
          day(1, [
            item('müze', '09:00'),
            item('yemek', '10:15', kind: TimelineItemKind.meal),
            item('park', '12:00'),
          ]),
        ]),
        const UpdateActivityDuration(
          dayNumber: 1,
          activityId: 'yemek',
          durationMinutes: 90,
        ),
      );
      expect(findItem(result.trip!, 'park').time, '12:00');
    });

    test('yemek sonrası 15 dakikadan az mevcut plan geçersizdir', () {
      final invalid = tripWith([
        day(1, [
          item('yemek', '19:00', duration: 30, kind: TimelineItemKind.meal),
          item('gösteri', '19:40'),
        ]),
      ]);
      final failure = engine.validate(invalid);
      expect(failure!.code, PlanEditFailureCode.timeConflict);
      expect(failure.overlapMinutes, 5);
    });

    test('yemek başka güne taşındığında kural korunur', () {
      final result = engine.apply(
        tripWith([
          day(1, [item('yemek', '12:00', kind: TimelineItemKind.meal)]),
          day(2, [item('park', '13:00')]),
        ]),
        const MoveActivityToDay(
          sourceDayNumber: 1,
          activityId: 'yemek',
          targetDayNumber: 2,
          targetIndex: 0,
        ),
      );
      final meal = findItem(result.trip!, 'yemek');
      final park = findItem(result.trip!, 'park');
      expect(
        _minutes(park.time!) - (_minutes(meal.time!) + meal.durationMin!),
        greaterThanOrEqualTo(15),
      );
    });
  });

  group('sabit aktiviteler', () {
    TimelineItem flight() => item(
          'uçuş',
          '18:30',
          duration: 120,
          lockType: ActivityLockType.flight,
          fixedStart: '18:30',
          canChangeDay: false,
          canChangeTime: false,
          canReorder: false,
          canDelete: false,
        );

    test('sabit aktivite taşınamaz, saati ve günü değiştirilemez', () {
      final original = tripWith([
        day(1, [item('a', '09:00'), flight()]),
        day(2, []),
      ]);
      final reorder = engine.apply(
        original,
        const MoveActivityWithinDay(
          dayNumber: 1,
          activityId: 'uçuş',
          targetIndex: 0,
        ),
      );
      final moveDay = engine.apply(
        original,
        const MoveActivityToDay(
          sourceDayNumber: 1,
          activityId: 'uçuş',
          targetDayNumber: 2,
        ),
      );
      final changeTime = engine.apply(
        original,
        const UpdateActivityTime(
          dayNumber: 1,
          activityId: 'uçuş',
          startMinutes: 19 * 60,
        ),
      );
      expect(reorder.failure!.code, PlanEditFailureCode.lockedActivity);
      expect(moveDay.failure!.code, PlanEditFailureCode.lockedActivity);
      expect(changeTime.failure!.code, PlanEditFailureCode.lockedActivity);
    });

    test('sabit aktivite önüne sığmayan hareket engellenir', () {
      final result = engine.apply(
        tripWith([
          day(1, [
            item('uzun', '15:00', duration: 180),
            flight(),
            item('erken', '09:00'),
          ]),
        ]),
        const MoveActivityWithinDay(
          dayNumber: 1,
          activityId: 'erken',
          targetIndex: 1,
        ),
      );
      expect(result.failure!.code, PlanEditFailureCode.fixedTimeConflict);
    });

    test(
        'birden fazla sabit aktivite arasında yalnızca uygun boşluk kullanılır',
        () {
      final train = item(
        'tren',
        '12:00',
        duration: 60,
        lockType: ActivityLockType.trainReservation,
        fixedStart: '12:00',
        canChangeDay: false,
        canChangeTime: false,
        canReorder: false,
      );
      final result = engine.apply(
        tripWith([
          day(1, [train, item('a', '13:30'), flight()]),
        ]),
        const UpdateActivityDuration(
          dayNumber: 1,
          activityId: 'a',
          durationMinutes: 120,
        ),
      );
      expect(result.isSuccess, isTrue);
      expect(findItem(result.trip!, 'uçuş').time, '18:30');
    });

    test('sabit aktivite silinemez', () {
      final result = engine.apply(
        tripWith([
          day(1, [flight()]),
        ]),
        const DeleteActivity(dayNumber: 1, activityId: 'uçuş'),
      );
      expect(result.failure!.code, PlanEditFailureCode.lockedActivity);
    });

    test('uçuş ve tren varış/kalkış başlıkları eski planda da kilitlenir', () {
      for (final title in [
        'Flight Arrival',
        'Flight Departure',
        'Train Arrival',
        'Train Departure',
        'Tren Varış',
        'Tren Kalkış',
      ]) {
        final result = engine.apply(
          tripWith([
            day(1, [item(title, '10:00')]),
            day(2, []),
          ]),
          MoveActivityToDay(
            sourceDayNumber: 1,
            activityId: title,
            targetDayNumber: 2,
          ),
        );
        expect(
          result.failure?.code,
          PlanEditFailureCode.lockedActivity,
          reason: '$title kilitli olmalı',
        );
      }
    });
  });

  group('gün ve bütünlük kuralları', () {
    test('geçiş modu timeline, tema ve snapshot ile atomik senkronlanır', () {
      final transitionDay = day(2, [
        TimelineItem(
          id: 'legacy-transfer',
          title: '🚆 Kyoto → Osaka • JR Special Rapid',
          description: '30dk · ~580 ¥',
          kind: TimelineItemKind.transport,
          time: '09:00',
          scheduledTime: '09:00',
          durationMin: 30,
          cityId: 'Osaka',
        ),
        TimelineItem(
          id: 'dotonbori',
          title: '🐙 Dotonbori',
          kind: TimelineItemKind.activity,
          time: '10:00',
          scheduledTime: '10:00',
          durationMin: 90,
          cityId: 'Osaka',
        ),
      ])
        ..theme = '🚄 Shinkansen & Dotonbori'
        ..cityTransition = const CityTransitionPlan(
          fromCity: 'Kyoto',
          toCity: 'Osaka',
          mode: 'train',
        )
        ..routeExecutionSnapshot = RouteExecutionSnapshot(
          planId: 'trip',
          dayNumber: 2,
          planVersion: 1,
          activityHash: 'old-transfer',
          matrixVersion: 'matrix-v1',
          generatedAt: DateTime.utc(2026, 8, 11),
          profile: RouteOptimizationProfile.balanced,
          legs: const [],
        );

      final result = engine.apply(
        tripWith([day(1, []), transitionDay]),
        const UpdateCityTransition(
          toDayNumber: 2,
          fromCity: 'Kyoto',
          toCity: 'Osaka',
          mode: 'bus',
        ),
      );

      expect(result.isSuccess, isTrue);
      final updated = result.trip!.days[1];
      final transfer = updated.items.first;
      expect(updated.cityTransition?.mode, 'bus');
      expect(transfer.id, 'legacy-transfer');
      expect(transfer.isCityTransition, isTrue);
      expect(transfer.title, contains('Şehirlerarası otobüs'));
      expect(transfer.title, isNot(contains('JR Special Rapid')));
      expect(transfer.description, isNot(contains('580')));
      expect(transfer.durationMin, 75);
      expect(updated.theme, '🚌 Otobüs & Dotonbori');
      expect(updated.routeExecutionSnapshot, isNull);

      final restored = Trip.fromJson(result.trip!.toJson());
      expect(restored.days[1].items.first.isCityTransition, isTrue);

      final switchedAgain = engine.apply(
        result.trip!,
        const UpdateCityTransition(
          toDayNumber: 2,
          fromCity: 'Kyoto',
          toCity: 'Osaka',
          mode: 'flight',
        ),
      );
      expect(switchedAgain.isSuccess, isTrue);
      expect(switchedAgain.trip!.days[1].theme, '✈️ Uçak & Dotonbori');
      expect(
        switchedAgain.trip!.days[1].items.first.title,
        isNot(contains('Şehirlerarası otobüs')),
      );
    });

    test('şehir geçiş modu ve bağlı bilet atomik olarak kalıcılaşır', () {
      final selected = engine.apply(
        tripWith([day(1, []), day(2, [])]),
        const UpdateCityTransition(
          toDayNumber: 2,
          fromCity: 'Tokyo',
          toCity: 'Kyoto',
          mode: 'shinkansen',
        ),
      );
      expect(selected.isSuccess, isTrue);
      expect(selected.trip!.days[1].cityTransition?.mode, 'shinkansen');

      final ticketed = engine.apply(
        selected.trip!,
        UpsertTicket(
          transitionDayNumber: 2,
          ticket: Ticket(
            id: 'ticket-1',
            kind: 'train',
            label: 'Tokyo → Kyoto',
            purchased: true,
          ),
        ),
      );
      expect(ticketed.isSuccess, isTrue);
      expect(ticketed.trip!.tickets.single.linkedTransitionDayNumber, 2);
      expect(ticketed.trip!.days[1].cityTransition?.linkedTicketId, 'ticket-1');

      final restored = Trip.fromJson(ticketed.trip!.toJson());
      expect(restored.days[1].cityTransition?.mode, 'shinkansen');
      expect(restored.days[1].cityTransition?.linkedTicketId, 'ticket-1');
    });

    test('aktivite değişikliği eski rota snapshotını geçersizleştirir', () {
      final plannedDay = day(1, [item('a', '09:00')])
        ..routeExecutionSnapshot = RouteExecutionSnapshot(
          planId: 'trip',
          dayNumber: 1,
          planVersion: 1,
          activityHash: 'old',
          matrixVersion: 'matrix-v1',
          generatedAt: DateTime.utc(2026, 8, 10),
          profile: RouteOptimizationProfile.balanced,
          legs: const [],
        );

      final result = engine.apply(
        tripWith([plannedDay]),
        const UpdateActivityTime(
          dayNumber: 1,
          activityId: 'a',
          startMinutes: 10 * 60,
        ),
      );

      expect(result.isSuccess, isTrue);
      expect(result.trip!.days.single.routeExecutionSnapshot, isNull);
    });

    test('günler yeniden sıralanır ve numaralanır', () {
      final result = engine.apply(
        tripWith([day(1, []), day(2, []), day(3, [])]),
        const ReorderDays(oldIndex: 2, newIndex: 0),
      );
      expect(result.trip!.days.map((d) => d.date),
          ['2026-08-03', '2026-08-01', '2026-08-02']);
      expect(result.trip!.days.map((d) => d.dayNumber), [1, 2, 3]);
    });

    test('gün başlığı ve tarihi güncellenir', () {
      final result = engine.apply(
        tripWith([day(1, [])]),
        const UpdateDayDetails(
          dayNumber: 1,
          title: 'Kyoto',
          date: '2026-08-02',
        ),
      );
      expect(result.trip!.days.single.theme, 'Kyoto');
      expect(result.trip!.days.single.date, '2026-08-02');
    });

    test('geçersiz tarih reddedilir', () {
      final result = engine.apply(
        tripWith([day(1, [])]),
        const UpdateDayDetails(dayNumber: 1, date: 'yarın'),
      );
      expect(result.failure!.code, PlanEditFailureCode.invalidDate);
    });

    test('duplicate aktivite doğrulamada yakalanır', () {
      final failure = engine.validate(
        tripWith([
          day(1, [item('x', '09:00')]),
          day(2, [item('x', '09:00')]),
        ]),
      );
      expect(failure!.code, PlanEditFailureCode.duplicateActivity);
    });

    test('silinen aktivite yeniden planlamada geri gelmez', () {
      final deleted = engine.apply(
        tripWith([
          day(1, [item('a', '09:00'), item('b', '10:15')]),
        ]),
        const DeleteActivity(dayNumber: 1, activityId: 'a'),
      );
      final edited = engine.apply(
        deleted.trip!,
        const UpdateActivityDuration(
          dayNumber: 1,
          activityId: 'b',
          durationMinutes: 90,
        ),
      );
      expect(edited.trip!.days.single.items.map((e) => e.id), ['b']);
    });

    test('gece yarısını aşan aktivite geçersiz plan üretmez', () {
      final result = engine.apply(
        tripWith([
          day(1, [item('gece', '23:30', duration: 30)]),
        ]),
        const UpdateActivityDuration(
          dayNumber: 1,
          activityId: 'gece',
          durationMinutes: 90,
        ),
      );
      expect(result.failure!.code, PlanEditFailureCode.outsideDay);
    });
  });
}

int _minutes(String time) {
  final parts = time.split(':').map(int.parse).toList();
  return parts[0] * 60 + parts[1];
}
