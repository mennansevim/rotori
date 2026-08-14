// Kullanıcı kilidi — "bileti aldım, bu durak yerinden oynamasın".
//
// Diğer kilitler plan verisinden türer (uçuş saati, otel check-in'i). Bu tek
// kilidi kullanıcı koyar; rota yeniden kurulurken/optimize edilirken durağın
// günü ve saati korunmalı.

import 'package:flutter_test/flutter_test.dart';

import 'package:rotori/domain/plan_generation.dart';
import 'package:rotori/domain/plan_schedule_engine.dart';
import 'package:rotori/domain/types.dart';

void main() {
  Trip weekTrip() => buildTripFromCities(
        cityKeys: const ['tokyo'],
        startYmd: '2026-10-15',
        endYmd: '2026-10-21',
      );

  /// Kilitlenmeye uygun (sistem kilidi olmayan) ilk durağı bulur.
  ({DayPlan day, TimelineItem item}) freeStop(Trip trip) {
    for (final day in trip.days) {
      for (final item in day.items) {
        if (item.canUserToggleLock && !item.isFixed) {
          return (day: day, item: item);
        }
      }
    }
    fail('kilitlenebilir durak bulunamadı');
  }

  group('TimelineItem kilit davranışı', () {
    test('pinByUser günü, sırayı ve saati dondurur', () {
      final trip = weekTrip();
      final target = freeStop(trip);
      final item = target.item;
      final originalTime = item.time ?? item.scheduledTime;

      item.pinByUser(reason: 'Bilet alındı');

      expect(item.isUserPinned, isTrue);
      expect(item.isFixed, isTrue);
      expect(item.canChangeDay, isFalse);
      expect(item.canChangeTime, isFalse);
      expect(item.canReorder, isFalse);
      expect(item.canDelete, isFalse);
      expect(item.lockReason, 'Bilet alındı');
      // Saat, kilitlendiği andaki saatten yazılır.
      expect(item.fixedStartTime, originalTime);
    });

    test('unpinByUser kilidi tamamen geri alır', () {
      final trip = weekTrip();
      final item = freeStop(trip).item;

      item.pinByUser(reason: 'Bilet alındı');
      item.unpinByUser();

      expect(item.isUserPinned, isFalse);
      expect(item.isFixed, isFalse);
      expect(item.canChangeDay, isTrue);
      expect(item.canChangeTime, isTrue);
      expect(item.canReorder, isTrue);
      expect(item.canDelete, isTrue);
      expect(item.fixedStartTime, isNull);
      expect(item.lockReason, isNull);
    });

    test('sistem kilidi kullanıcı tarafından açılamaz', () {
      final item = TimelineItem(
        id: 'x',
        title: 'Uçuş varış',
        lockType: ActivityLockType.flight,
        canChangeTime: false,
        canReorder: false,
      );

      expect(item.canUserToggleLock, isFalse);

      // unpinByUser sistem kilidine DOKUNMAZ.
      item.unpinByUser();
      expect(item.lockType, ActivityLockType.flight);
      expect(item.canChangeTime, isFalse);

      // pinByUser da onu kullanıcı kilidine ÇEVİRMEZ.
      item.pinByUser(reason: 'Bilet alındı');
      expect(item.lockType, ActivityLockType.flight);
    });

    test('kilit JSON turunda korunur', () {
      final trip = weekTrip();
      final item = freeStop(trip).item;
      item.pinByUser(reason: 'Bilet alındı');

      final restored = Trip.fromJson(trip.toJson());
      final found = restored.days
          .expand((d) => d.items)
          .firstWhere((i) => i.id == item.id);

      expect(found.lockType, ActivityLockType.userPinned);
      expect(found.isUserPinned, isTrue);
      expect(found.canReorder, isFalse);
      expect(found.lockReason, 'Bilet alındı');
      // 'user_pinned' anahtarı JSON'a gerçekten yazılıyor.
      expect(trip.toJson().toString(), contains('user_pinned'));
    });
  });

  group('SetActivityUserLock komutu', () {
    test('kilitler ve kilidi açar', () {
      const engine = PlanScheduleEngine();
      final trip = weekTrip();
      final target = freeStop(trip);

      final locked = engine.apply(
        trip,
        SetActivityUserLock(
          dayNumber: target.day.dayNumber,
          activityId: target.item.id,
          locked: true,
          reason: 'Bilet alındı',
        ),
      );

      expect(locked.isSuccess, isTrue, reason: '${locked.failure?.message}');
      final lockedItem = locked.trip!.days
          .expand((d) => d.items)
          .firstWhere((i) => i.id == target.item.id);
      expect(lockedItem.isUserPinned, isTrue);

      final unlocked = engine.apply(
        locked.trip!,
        SetActivityUserLock(
          dayNumber: target.day.dayNumber,
          activityId: target.item.id,
          locked: false,
          reason: 'Bilet alındı',
        ),
      );

      expect(unlocked.isSuccess, isTrue);
      final freed = unlocked.trip!.days
          .expand((d) => d.items)
          .firstWhere((i) => i.id == target.item.id);
      expect(freed.isUserPinned, isFalse);
      expect(freed.canReorder, isTrue);
    });

    test('sistem kilitli durakta komut reddedilir', () {
      const engine = PlanScheduleEngine();
      final trip = weekTrip();
      final systemLocked = trip.days
          .expand((d) => d.items)
          .where((i) => !i.canUserToggleLock)
          .toList();
      if (systemLocked.isEmpty) return; // bu planda sistem kilidi yoksa atla

      final day = trip.days.firstWhere(
        (d) => d.items.any((i) => i.id == systemLocked.first.id),
      );

      final result = engine.apply(
        trip,
        SetActivityUserLock(
          dayNumber: day.dayNumber,
          activityId: systemLocked.first.id,
          locked: false,
          reason: 'x',
        ),
      );

      expect(result.isSuccess, isFalse);
      expect(result.failure!.code, PlanEditFailureCode.lockedActivity);
    });

    test('kilitli durak taşınamaz ve silinemez', () {
      const engine = PlanScheduleEngine();
      final trip = weekTrip();
      final target = freeStop(trip);
      final day = target.day;

      final locked = engine
          .apply(
            trip,
            SetActivityUserLock(
              dayNumber: day.dayNumber,
              activityId: target.item.id,
              locked: true,
              reason: 'Bilet alındı',
            ),
          )
          .trip!;

      // Gün içinde taşıma reddedilir.
      final moved = engine.apply(
        locked,
        MoveActivityWithinDay(
          dayNumber: day.dayNumber,
          activityId: target.item.id,
          targetIndex: 0,
        ),
      );
      expect(moved.isSuccess, isFalse);
      expect(moved.failure!.code, PlanEditFailureCode.lockedActivity);

      // Silme de reddedilir.
      final deleted = engine.apply(
        locked,
        DeleteActivity(
          dayNumber: day.dayNumber,
          activityId: target.item.id,
        ),
      );
      expect(deleted.isSuccess, isFalse);
    });
  });
}
