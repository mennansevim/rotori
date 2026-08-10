import 'types.dart';

/// Plan düzenleme kurallarının tek yapılandırma noktası.
class PlanSchedulePolicy {
  const PlanSchedulePolicy({
    this.dayStartMinutes = 9 * 60,
    this.defaultDurationMinutes = 60,
    this.minimumTransitionMinutes = 15,
    this.minimumMealGapMinutes = 15,
    this.maximumDayMinutes = 24 * 60,
  });

  final int dayStartMinutes;
  final int defaultDurationMinutes;
  final int minimumTransitionMinutes;
  final int minimumMealGapMinutes;
  final int maximumDayMinutes;
}

enum PlanEditFailureCode {
  dayNotFound,
  activityNotFound,
  invalidIndex,
  invalidDate,
  invalidDuration,
  invalidTime,
  lockedActivity,
  timeConflict,
  fixedTimeConflict,
  duplicateActivity,
  outsideDay,
}

class PlanEditFailure {
  const PlanEditFailure(
    this.code, {
    required this.message,
    this.activityId,
    this.conflictingActivityId,
    this.overlapMinutes,
  });

  final PlanEditFailureCode code;
  final String message;
  final String? activityId;
  final String? conflictingActivityId;
  final int? overlapMinutes;
}

class PlanChange {
  const PlanChange({
    required this.activityId,
    required this.fromDay,
    required this.toDay,
    required this.oldTime,
    required this.newTime,
  });

  final String activityId;
  final int fromDay;
  final int toDay;
  final String? oldTime;
  final String? newTime;
}

class PlanEditResult {
  const PlanEditResult._({
    this.trip,
    this.failure,
    this.changes = const [],
  });

  factory PlanEditResult.success(Trip trip, List<PlanChange> changes) =>
      PlanEditResult._(trip: trip, changes: changes);

  factory PlanEditResult.failure(PlanEditFailure failure) =>
      PlanEditResult._(failure: failure);

  final Trip? trip;
  final PlanEditFailure? failure;
  final List<PlanChange> changes;

  bool get isSuccess => trip != null;
}

sealed class PlanEditCommand {
  const PlanEditCommand();
}

class MoveActivityWithinDay extends PlanEditCommand {
  const MoveActivityWithinDay({
    required this.dayNumber,
    required this.activityId,
    required this.targetIndex,
    this.startMinutes,
    this.preserveExistingTimes = false,
  });

  final int dayNumber;
  final String activityId;
  final int targetIndex;
  final int? startMinutes;
  final bool preserveExistingTimes;
}

class MoveActivityToDay extends PlanEditCommand {
  const MoveActivityToDay({
    required this.sourceDayNumber,
    required this.activityId,
    required this.targetDayNumber,
    this.targetIndex,
    this.startMinutes,
    this.durationMinutes,
    this.preserveExistingTimes = false,
  });

  final int sourceDayNumber;
  final String activityId;
  final int targetDayNumber;
  final int? targetIndex;
  final int? startMinutes;
  final int? durationMinutes;
  final bool preserveExistingTimes;
}

class UpdateActivityTime extends PlanEditCommand {
  const UpdateActivityTime({
    required this.dayNumber,
    required this.activityId,
    required this.startMinutes,
  });

  final int dayNumber;
  final String activityId;
  final int startMinutes;
}

class UpdateActivityDuration extends PlanEditCommand {
  const UpdateActivityDuration({
    required this.dayNumber,
    required this.activityId,
    required this.durationMinutes,
  });

  final int dayNumber;
  final String activityId;
  final int durationMinutes;
}

class UpdateActivitySchedule extends PlanEditCommand {
  const UpdateActivitySchedule({
    required this.dayNumber,
    required this.activityId,
    required this.startMinutes,
    required this.durationMinutes,
  });

  final int dayNumber;
  final String activityId;
  final int startMinutes;
  final int durationMinutes;
}

class DeleteActivity extends PlanEditCommand {
  const DeleteActivity({
    required this.dayNumber,
    required this.activityId,
  });

  final int dayNumber;
  final String activityId;
}

class AddActivity extends PlanEditCommand {
  const AddActivity({
    required this.dayNumber,
    required this.activity,
    this.targetIndex,
  });

  final int dayNumber;
  final TimelineItem activity;
  final int? targetIndex;
}

class ReorderDays extends PlanEditCommand {
  const ReorderDays({required this.oldIndex, required this.newIndex});

  final int oldIndex;
  final int newIndex;
}

class UpdateDayDetails extends PlanEditCommand {
  const UpdateDayDetails({
    required this.dayNumber,
    this.title,
    this.date,
  });

  final int dayNumber;
  final String? title;
  final String? date;
}

class UpdateCityTransition extends PlanEditCommand {
  const UpdateCityTransition({
    required this.toDayNumber,
    required this.fromCity,
    required this.toCity,
    required this.mode,
  });

  final int toDayNumber;
  final String fromCity;
  final String toCity;
  final String mode;
}

class UpsertTicket extends PlanEditCommand {
  const UpsertTicket({required this.ticket, this.transitionDayNumber});

  final Ticket ticket;
  final int? transitionDayNumber;
}

/// UI, drag-and-drop ve persistence katmanlarının tamamı bu motoru kullanır.
///
/// Motor girdiyi değiştirmez. Başarılı sonuç yeni bir [Trip], başarısız sonuç
/// typed bir hata döndürür; böylece optimistic update güvenle geri alınabilir.
class PlanScheduleEngine {
  const PlanScheduleEngine({
    this.policy = const PlanSchedulePolicy(),
  });

  final PlanSchedulePolicy policy;

  /// Saat seçicilerin gösterebileceği, gerçekten kaydedilebilir başlangıçları
  /// döndürür. Her aday gerçek komut hattından geçirilir; sabit rezervasyon,
  /// aktivite süresi, 15 dakikalık tampon ve gün sınırı UI'da ayrıca
  /// kopyalanmaz.
  List<int> availableStartMinutes(
    Trip trip, {
    required int sourceDayNumber,
    required String activityId,
    required int targetDayNumber,
    int? durationMinutes,
    int firstMinute = 8 * 60,
    int lastMinute = 22 * 60,
    int stepMinutes = 15,
  }) {
    if (stepMinutes <= 0 || firstMinute < 0 || lastMinute < firstMinute) {
      return const [];
    }
    final source = _day(trip, sourceDayNumber);
    TimelineItem? sourceItem;
    if (source != null) {
      for (final item in source.items) {
        if (item.id == activityId) {
          sourceItem = item;
          break;
        }
      }
    }
    if (sourceItem == null || sourceItem.isFixed) return const [];

    final result = <int>[];
    for (var minute = firstMinute;
        minute <= lastMinute && minute < policy.maximumDayMinutes;
        minute += stepMinutes) {
      final candidateDuration = durationMinutes ?? _duration(sourceItem);
      if (sourceDayNumber != targetDayNumber &&
          !_fitsExistingTarget(
            trip,
            targetDayNumber: targetDayNumber,
            startMinutes: minute,
            durationMinutes: candidateDuration,
          )) {
        continue;
      }
      final command = sourceDayNumber == targetDayNumber
          ? UpdateActivitySchedule(
              dayNumber: sourceDayNumber,
              activityId: activityId,
              startMinutes: minute,
              durationMinutes: candidateDuration,
            )
          : MoveActivityToDay(
              sourceDayNumber: sourceDayNumber,
              activityId: activityId,
              targetDayNumber: targetDayNumber,
              startMinutes: minute,
              durationMinutes: candidateDuration,
            );
      final attempt = apply(trip, command);
      if (!attempt.isSuccess) continue;
      final moved = _activity(attempt.trip!, activityId);
      if (moved != null && _start(moved) == minute) result.add(minute);
    }
    return result;
  }

  /// Bir aktivite satırlar arasındaki bırakma alanına taşındığında önerilecek
  /// başlangıç saatini hesaplar. İki komşu arasında gerçek bir boşluk varsa
  /// uygun pencerenin ortasını, yoksa önceki aktivitenin bitişinden sonraki ilk
  /// güvenli saati döndürür. Boş günde aktivitenin mevcut saati korunur.
  int suggestedStartMinutesForInsertion(
    Trip trip, {
    required int sourceDayNumber,
    required String activityId,
    required int targetDayNumber,
    required int targetIndex,
  }) {
    final source = _day(trip, sourceDayNumber);
    final target = _day(trip, targetDayNumber);
    if (source == null || target == null) return policy.dayStartMinutes;
    final item = source.items
        .where((candidate) => candidate.id == activityId)
        .cast<TimelineItem?>()
        .firstWhere((candidate) => candidate != null, orElse: () => null);
    if (item == null) return policy.dayStartMinutes;

    final items = target.items
        .where((candidate) => candidate.id != activityId)
        .toList(growable: false);
    final index = targetIndex.clamp(0, items.length);
    final previous = index > 0 ? items[index - 1] : null;
    final next = index < items.length ? items[index] : null;
    final duration = _duration(item);

    if (previous == null && next == null) {
      return (_start(item) ?? policy.dayStartMinutes)
          .clamp(0, policy.maximumDayMinutes - duration);
    }

    final earliest = previous == null
        ? policy.dayStartMinutes
        : (_start(previous) ?? policy.dayStartMinutes) +
            _duration(previous) +
            _gapAfter(previous);
    if (next == null) {
      return earliest.clamp(0, policy.maximumDayMinutes - duration);
    }

    final nextStart = _start(next) ?? earliest;
    final latest = nextStart - duration - policy.minimumTransitionMinutes;
    final firstSlot = ((earliest + 14) ~/ 15) * 15;
    final lastSlot = (latest ~/ 15) * 15;
    if (firstSlot <= lastSlot) {
      final midpoint = (firstSlot + lastSlot) ~/ 2;
      final rounded = ((midpoint + 7) ~/ 15) * 15;
      return rounded.clamp(firstSlot, lastSlot);
    }
    return firstSlot.clamp(0, policy.maximumDayMinutes - duration);
  }

  bool _fitsExistingTarget(
    Trip trip, {
    required int targetDayNumber,
    required int startMinutes,
    required int durationMinutes,
  }) {
    final target = _day(trip, targetDayNumber);
    if (target == null ||
        startMinutes + durationMinutes > policy.maximumDayMinutes) {
      return false;
    }
    final candidateEnd = startMinutes + durationMinutes;
    for (final existing in target.items) {
      final existingStart = _start(existing);
      if (existingStart == null) return false;
      final existingEnd = existingStart + _duration(existing);
      final fitsBefore =
          candidateEnd + policy.minimumTransitionMinutes <= existingStart;
      final fitsAfter = startMinutes >= existingEnd + _gapAfter(existing);
      if (!fitsBefore && !fitsAfter) return false;
    }
    return true;
  }

  PlanEditResult apply(Trip original, PlanEditCommand command) {
    final baseline = _cloneTrip(original);
    _applyKnownReservationLocks(baseline);
    final trip = _cloneTrip(baseline);
    _applyKnownReservationLocks(trip);
    final before = _activityLocations(original);
    final failure = switch (command) {
      MoveActivityWithinDay command => _moveWithinDay(trip, command),
      MoveActivityToDay command => _moveToDay(trip, command),
      UpdateActivityTime command => _updateTime(trip, command),
      UpdateActivityDuration command => _updateDuration(trip, command),
      UpdateActivitySchedule command => _updateSchedule(trip, command),
      DeleteActivity command => _deleteActivity(trip, command),
      AddActivity command => _addActivity(trip, command),
      ReorderDays command => _reorderDays(trip, command),
      UpdateDayDetails command => _updateDayDetails(trip, command),
      UpdateCityTransition command => _updateCityTransition(trip, command),
      UpsertTicket command => _upsertTicket(trip, command),
    };
    if (failure != null) return PlanEditResult.failure(failure);
    _invalidateChangedRouteSnapshots(baseline, trip);

    final structuralFailure = _validateStructure(trip);
    if (structuralFailure != null) {
      return PlanEditResult.failure(structuralFailure);
    }

    // Eski/ithal planlarda birbiriyle ilgisiz zaman çakışmaları bulunabilir.
    // Kullanıcının geçerli bir düzenlemesini bu tarihsel borç yüzünden
    // engelleme; yalnızca komutun oluşturduğu yeni veya büyüttüğü çakışmayı
    // reddet. Böylece kullanıcı planı parça parça düzeltebilir.
    final baselineConflicts = {
      for (final conflict in _timeConflicts(baseline))
        _conflictKey(conflict): conflict,
    };
    for (final conflict in _timeConflicts(trip)) {
      final previous = baselineConflicts[_conflictKey(conflict)];
      final isNew = previous == null;
      final isWorse =
          (conflict.overlapMinutes ?? 0) > (previous?.overlapMinutes ?? 0);
      if (isNew || isWorse) {
        return PlanEditResult.failure(conflict);
      }
    }
    return PlanEditResult.success(trip, _changes(before, trip));
  }

  PlanEditFailure? validate(Trip trip) {
    final structuralFailure = _validateStructure(trip);
    if (structuralFailure != null) return structuralFailure;
    final conflicts = _timeConflicts(trip);
    return conflicts.isEmpty ? null : conflicts.first;
  }

  PlanEditFailure? _validateStructure(Trip trip) {
    final ids = <String>{};
    for (final day in trip.days) {
      if (DateTime.tryParse(day.date) == null) {
        return PlanEditFailure(
          PlanEditFailureCode.invalidDate,
          message: 'Geçersiz gün tarihi: ${day.date}',
        );
      }
      for (var index = 0; index < day.items.length; index++) {
        final item = day.items[index];
        if (!ids.add(item.id)) {
          return PlanEditFailure(
            PlanEditFailureCode.duplicateActivity,
            message: 'Aynı aktivite plan içinde iki kez bulunamaz.',
            activityId: item.id,
          );
        }
        final duration = _duration(item);
        if (duration <= 0) {
          return PlanEditFailure(
            PlanEditFailureCode.invalidDuration,
            message: '${item.title} için süre sıfırdan büyük olmalı.',
            activityId: item.id,
          );
        }
        final start = _start(item);
        if (start == null) {
          return PlanEditFailure(
            PlanEditFailureCode.invalidTime,
            message: '${item.title} için geçerli bir başlangıç saati gerekli.',
            activityId: item.id,
          );
        }
        if (start + duration > policy.maximumDayMinutes) {
          return PlanEditFailure(
            PlanEditFailureCode.outsideDay,
            message: '${item.title} gün sınırını aşıyor.',
            activityId: item.id,
          );
        }
        final fixedStart = _parseTime(item.fixedStartTime);
        if (fixedStart != null && fixedStart != start) {
          return PlanEditFailure(
            PlanEditFailureCode.lockedActivity,
            message: '${item.title} sabit rezervasyon saatinde kalmalı.',
            activityId: item.id,
          );
        }
      }
    }
    return null;
  }

  List<PlanEditFailure> _timeConflicts(Trip trip) {
    final failures = <PlanEditFailure>[];
    for (final day in trip.days) {
      for (var index = 1; index < day.items.length; index++) {
        final item = day.items[index];
        final previous = day.items[index - 1];
        final start = _start(item);
        final previousStart = _start(previous);
        if (start == null || previousStart == null) continue;
        final earliest =
            previousStart + _duration(previous) + _gapAfter(previous);
        if (start >= earliest) continue;
        failures.add(PlanEditFailure(
          item.isFixed
              ? PlanEditFailureCode.fixedTimeConflict
              : PlanEditFailureCode.timeConflict,
          message:
              '${previous.title} ile ${item.title} arasında ${earliest - start} dakikalık çakışma var.',
          activityId: item.id,
          conflictingActivityId: previous.id,
          overlapMinutes: earliest - start,
        ));
      }
    }
    return failures;
  }

  String _conflictKey(PlanEditFailure failure) =>
      '${failure.conflictingActivityId ?? ''}>${failure.activityId ?? ''}';

  PlanEditFailure? _moveWithinDay(
    Trip trip,
    MoveActivityWithinDay command,
  ) {
    final day = _day(trip, command.dayNumber);
    if (day == null) return _missingDay(command.dayNumber);
    final oldIndex =
        day.items.indexWhere((item) => item.id == command.activityId);
    if (oldIndex < 0) return _missingActivity(command.activityId);
    if (command.targetIndex < 0 || command.targetIndex >= day.items.length) {
      return _invalidIndex();
    }
    final item = day.items[oldIndex];
    if (!item.canReorder || item.isFixed) return _locked(item);
    if (oldIndex == command.targetIndex) return null;

    day.items.removeAt(oldIndex);
    day.items.insert(command.targetIndex, item);
    if (command.preserveExistingTimes && command.startMinutes != null) {
      _setStart(item, command.startMinutes!);
      if (command.targetIndex > 0) {
        final previous = day.items[command.targetIndex - 1];
        final earliest =
            _start(previous)! + _duration(previous) + _gapAfter(previous);
        if (command.startMinutes! < earliest) {
          return PlanEditFailure(
            PlanEditFailureCode.timeConflict,
            message:
                '${previous.title} ile ${item.title} arasında ${earliest - command.startMinutes!} dakikalık çakışma var.',
            activityId: item.id,
            conflictingActivityId: previous.id,
            overlapMinutes: earliest - command.startMinutes!,
          );
        }
      }
      return _shiftForwardOnly(day, command.targetIndex + 1);
    }
    return _reschedule(
        day, oldIndex < command.targetIndex ? oldIndex : command.targetIndex);
  }

  PlanEditFailure? _moveToDay(Trip trip, MoveActivityToDay command) {
    final source = _day(trip, command.sourceDayNumber);
    final target = _day(trip, command.targetDayNumber);
    if (source == null) return _missingDay(command.sourceDayNumber);
    if (target == null) return _missingDay(command.targetDayNumber);
    final sourceIndex =
        source.items.indexWhere((item) => item.id == command.activityId);
    if (sourceIndex < 0) return _missingActivity(command.activityId);
    final item = source.items[sourceIndex];
    if (!item.canChangeDay || item.isFixed) return _locked(item);
    if (command.durationMinutes != null && command.durationMinutes! <= 0) {
      return const PlanEditFailure(
        PlanEditFailureCode.invalidDuration,
        message: 'Aktivite süresi sıfırdan büyük olmalı.',
      );
    }
    if (command.startMinutes != null &&
        (command.startMinutes! < 0 ||
            command.startMinutes! >= policy.maximumDayMinutes)) {
      return const PlanEditFailure(
        PlanEditFailureCode.invalidTime,
        message: 'Başlangıç saati gün içinde olmalı.',
      );
    }

    source.items.removeAt(sourceIndex);
    if (!command.preserveExistingTimes) {
      final sourceFailure = _reschedule(source, sourceIndex);
      if (sourceFailure != null) return sourceFailure;
    }
    final moved = item.copyWith(movedFromDay: source.dayNumber);
    if (command.durationMinutes != null) {
      moved.durationMin = command.durationMinutes;
    }
    if (command.startMinutes != null) {
      _setStart(moved, command.startMinutes!);
    }
    final targetIndex =
        command.targetIndex ?? _suggestedIndex(target.items, moved);
    if (targetIndex < 0 || targetIndex > target.items.length) {
      return _invalidIndex();
    }
    target.items.insert(targetIndex, moved);
    if (command.startMinutes == null) {
      return _reschedule(target, targetIndex);
    }
    if (targetIndex > 0) {
      final previous = target.items[targetIndex - 1];
      final earliest =
          _start(previous)! + _duration(previous) + _gapAfter(previous);
      if (command.startMinutes! < earliest) {
        return PlanEditFailure(
          PlanEditFailureCode.timeConflict,
          message:
              '${previous.title} ile ${moved.title} arasında ${earliest - command.startMinutes!} dakikalık çakışma var.',
          activityId: moved.id,
          conflictingActivityId: previous.id,
          overlapMinutes: earliest - command.startMinutes!,
        );
      }
    }
    _setStart(moved, command.startMinutes!);
    return command.preserveExistingTimes
        ? _shiftForwardOnly(target, targetIndex + 1)
        : _reschedule(target, targetIndex + 1);
  }

  PlanEditFailure? _updateTime(Trip trip, UpdateActivityTime command) {
    final day = _day(trip, command.dayNumber);
    if (day == null) return _missingDay(command.dayNumber);
    final index = day.items.indexWhere((item) => item.id == command.activityId);
    if (index < 0) return _missingActivity(command.activityId);
    final item = day.items[index];
    if (!item.canChangeTime || item.isFixed) return _locked(item);
    if (command.startMinutes < 0 ||
        command.startMinutes >= policy.maximumDayMinutes) {
      return PlanEditFailure(
        PlanEditFailureCode.invalidTime,
        message: 'Başlangıç saati gün içinde olmalı.',
        activityId: item.id,
      );
    }
    if (index > 0) {
      final previous = day.items[index - 1];
      final earliest =
          _start(previous)! + _duration(previous) + _gapAfter(previous);
      if (command.startMinutes < earliest) {
        return PlanEditFailure(
          PlanEditFailureCode.timeConflict,
          message:
              '${previous.title} ile ${item.title} arasında ${earliest - command.startMinutes} dakikalık çakışma var.',
          activityId: item.id,
          conflictingActivityId: previous.id,
          overlapMinutes: earliest - command.startMinutes,
        );
      }
    }
    _setStart(item, command.startMinutes);
    return _reschedule(day, index + 1);
  }

  PlanEditFailure? _updateDuration(
    Trip trip,
    UpdateActivityDuration command,
  ) {
    if (command.durationMinutes <= 0) {
      return const PlanEditFailure(
        PlanEditFailureCode.invalidDuration,
        message: 'Aktivite süresi sıfırdan büyük olmalı.',
      );
    }
    final day = _day(trip, command.dayNumber);
    if (day == null) return _missingDay(command.dayNumber);
    final index = day.items.indexWhere((item) => item.id == command.activityId);
    if (index < 0) return _missingActivity(command.activityId);
    final item = day.items[index];
    if (item.isFixed) return _locked(item);
    item.durationMin = command.durationMinutes;
    return _reschedule(day, index + 1);
  }

  PlanEditFailure? _updateSchedule(
    Trip trip,
    UpdateActivitySchedule command,
  ) {
    final timeFailure = _updateTime(
      trip,
      UpdateActivityTime(
        dayNumber: command.dayNumber,
        activityId: command.activityId,
        startMinutes: command.startMinutes,
      ),
    );
    if (timeFailure != null) return timeFailure;
    return _updateDuration(
      trip,
      UpdateActivityDuration(
        dayNumber: command.dayNumber,
        activityId: command.activityId,
        durationMinutes: command.durationMinutes,
      ),
    );
  }

  PlanEditFailure? _deleteActivity(Trip trip, DeleteActivity command) {
    final day = _day(trip, command.dayNumber);
    if (day == null) return _missingDay(command.dayNumber);
    final index = day.items.indexWhere((item) => item.id == command.activityId);
    if (index < 0) return _missingActivity(command.activityId);
    final item = day.items[index];
    if (!item.canDelete || item.isFixed) return _locked(item);
    day.items.removeAt(index);
    return null;
  }

  PlanEditFailure? _addActivity(Trip trip, AddActivity command) {
    final day = _day(trip, command.dayNumber);
    if (day == null) return _missingDay(command.dayNumber);
    final index =
        command.targetIndex ?? _suggestedIndex(day.items, command.activity);
    if (index < 0 || index > day.items.length) return _invalidIndex();
    day.items.insert(index, _cloneItem(command.activity));
    return _reschedule(day, index);
  }

  PlanEditFailure? _reorderDays(Trip trip, ReorderDays command) {
    if (command.oldIndex < 0 ||
        command.oldIndex >= trip.days.length ||
        command.newIndex < 0 ||
        command.newIndex >= trip.days.length) {
      return _invalidIndex();
    }
    final day = trip.days.removeAt(command.oldIndex);
    trip.days.insert(command.newIndex, day);
    for (var index = 0; index < trip.days.length; index++) {
      trip.days[index].dayNumber = index + 1;
    }
    return null;
  }

  PlanEditFailure? _updateDayDetails(
    Trip trip,
    UpdateDayDetails command,
  ) {
    final day = _day(trip, command.dayNumber);
    if (day == null) return _missingDay(command.dayNumber);
    if (command.date != null) {
      final parsed = DateTime.tryParse(command.date!);
      if (parsed == null) {
        return const PlanEditFailure(
          PlanEditFailureCode.invalidDate,
          message: 'Geçerli bir gün tarihi seçilmeli.',
        );
      }
      day.date = command.date!;
    }
    if (command.title != null) day.theme = command.title!.trim();
    return null;
  }

  PlanEditFailure? _updateCityTransition(
    Trip trip,
    UpdateCityTransition command,
  ) {
    final day = _day(trip, command.toDayNumber);
    if (day == null) return _missingDay(command.toDayNumber);
    final mode = command.mode.trim();
    if (mode.isEmpty) {
      return const PlanEditFailure(
        PlanEditFailureCode.invalidIndex,
        message: 'Geçerli bir ulaşım türü seçilmeli.',
      );
    }
    day.cityTransition = CityTransitionPlan(
      fromCity: command.fromCity.trim(),
      toCity: command.toCity.trim(),
      mode: mode,
      linkedTicketId: day.cityTransition?.linkedTicketId,
    );
    return null;
  }

  PlanEditFailure? _upsertTicket(Trip trip, UpsertTicket command) {
    final ticketJson = command.ticket.toJson();
    if (command.transitionDayNumber != null) {
      ticketJson['linkedTransitionDayNumber'] = command.transitionDayNumber;
    }
    final ticket = Ticket.fromJson(ticketJson);
    final index = trip.tickets.indexWhere((item) => item.id == ticket.id);
    if (index < 0) {
      trip.tickets.add(ticket);
    } else {
      trip.tickets[index] = ticket;
    }

    final transitionDayNumber = command.transitionDayNumber;
    if (transitionDayNumber == null) return null;
    final day = _day(trip, transitionDayNumber);
    if (day == null) return _missingDay(transitionDayNumber);
    final transition = day.cityTransition;
    if (transition == null) {
      return const PlanEditFailure(
        PlanEditFailureCode.activityNotFound,
        message: 'Biletin bağlanacağı şehir geçişi bulunamadı.',
      );
    }
    day.cityTransition = transition.copyWith(linkedTicketId: ticket.id);
    return null;
  }

  void _invalidateChangedRouteSnapshots(Trip before, Trip after) {
    final beforeByDay = {for (final day in before.days) day.dayNumber: day};
    for (final day in after.days) {
      final previous = beforeByDay[day.dayNumber];
      if (previous == null ||
          _itemSignature(previous.items) != _itemSignature(day.items)) {
        day.routeExecutionSnapshot = null;
      }
    }
  }

  String _itemSignature(List<TimelineItem> items) =>
      items.map((item) => item.toJson().toString()).join('\u0000');

  PlanEditFailure? _reschedule(DayPlan day, int fromIndex) {
    if (day.items.isEmpty || fromIndex >= day.items.length) return null;
    final safeIndex = fromIndex < 0 ? 0 : fromIndex;
    var cursor = safeIndex == 0
        ? _earliestStart(day.items)
        : _start(day.items[safeIndex - 1])! +
            _duration(day.items[safeIndex - 1]) +
            _gapAfter(day.items[safeIndex - 1]);

    for (var index = safeIndex; index < day.items.length; index++) {
      final item = day.items[index];
      final fixedStart = _parseTime(item.fixedStartTime) ??
          (item.isFixed ? _start(item) : null);
      if (fixedStart != null) {
        if (fixedStart < cursor) {
          return PlanEditFailure(
            PlanEditFailureCode.fixedTimeConflict,
            message:
                '${item.title} sabit saatine sığmıyor; ${cursor - fixedStart} dakika eksik.',
            activityId: item.id,
            conflictingActivityId: index == 0 ? null : day.items[index - 1].id,
            overlapMinutes: cursor - fixedStart,
          );
        }
        _setStart(item, fixedStart);
        cursor = fixedStart + _duration(item) + _gapAfter(item);
        continue;
      }
      _setStart(item, cursor);
      cursor += _duration(item) + _gapAfter(item);
      if (cursor - _gapAfter(item) > policy.maximumDayMinutes) {
        return PlanEditFailure(
          PlanEditFailureCode.outsideDay,
          message: '${item.title} gün sınırını aşıyor.',
          activityId: item.id,
        );
      }
    }
    return null;
  }

  /// Geçerli mevcut saatleri korur; yalnızca yeni yerleşimle çakışan sonraki
  /// aktiviteleri ileri iter. Drag/drop sonrası gereksiz saat sıkışmasını
  /// önlemek için kullanılır.
  PlanEditFailure? _shiftForwardOnly(DayPlan day, int fromIndex) {
    if (day.items.isEmpty || fromIndex >= day.items.length) return null;
    final safeIndex = fromIndex < 0 ? 0 : fromIndex;
    var cursor = safeIndex == 0
        ? policy.dayStartMinutes
        : _start(day.items[safeIndex - 1])! +
            _duration(day.items[safeIndex - 1]) +
            _gapAfter(day.items[safeIndex - 1]);

    for (var index = safeIndex; index < day.items.length; index++) {
      final item = day.items[index];
      final fixedStart = _parseTime(item.fixedStartTime) ??
          (item.isFixed ? _start(item) : null);
      if (fixedStart != null) {
        if (fixedStart < cursor) {
          return PlanEditFailure(
            PlanEditFailureCode.fixedTimeConflict,
            message:
                '${item.title} sabit saatine sığmıyor; ${cursor - fixedStart} dakika eksik.',
            activityId: item.id,
            conflictingActivityId: index == 0 ? null : day.items[index - 1].id,
            overlapMinutes: cursor - fixedStart,
          );
        }
        _setStart(item, fixedStart);
        cursor = fixedStart + _duration(item) + _gapAfter(item);
        continue;
      }
      final existing = _start(item);
      final start = existing != null && existing >= cursor ? existing : cursor;
      _setStart(item, start);
      cursor = start + _duration(item) + _gapAfter(item);
      if (cursor - _gapAfter(item) > policy.maximumDayMinutes) {
        return PlanEditFailure(
          PlanEditFailureCode.outsideDay,
          message: '${item.title} gün sınırını aşıyor.',
          activityId: item.id,
        );
      }
    }
    return null;
  }

  int _suggestedIndex(List<TimelineItem> items, TimelineItem item) {
    final wanted = _start(item);
    if (wanted == null) return items.length;
    final index = items
        .indexWhere((candidate) => (_start(candidate) ?? 1 << 20) > wanted);
    return index < 0 ? items.length : index;
  }

  int _earliestStart(List<TimelineItem> items) {
    final starts = items.map(_start).whereType<int>().toList();
    if (starts.isEmpty) return policy.dayStartMinutes;
    starts.sort();
    return starts.first;
  }

  int _duration(TimelineItem item) {
    final fixedStart = _parseTime(item.fixedStartTime);
    final fixedEnd = _parseTime(item.fixedEndTime);
    if (fixedStart != null && fixedEnd != null && fixedEnd > fixedStart) {
      return fixedEnd - fixedStart;
    }
    return item.durationMin ?? policy.defaultDurationMinutes;
  }

  int _gapAfter(TimelineItem item) => _isMeal(item)
      ? policy.minimumMealGapMinutes
      : policy.minimumTransitionMinutes;

  bool _isMeal(TimelineItem item) {
    if (item.kind == TimelineItemKind.meal) return true;
    final title = item.title.toLowerCase();
    return const [
      'kahvaltı',
      'öğle yemeği',
      'akşam yemeği',
      'brunch',
      'kafe',
      'cafe',
      'breakfast',
      'lunch',
      'dinner',
    ].any(title.contains);
  }

  int? _start(TimelineItem item) =>
      _parseTime(item.fixedStartTime ?? item.time ?? item.scheduledTime);

  int? _parseTime(String? value) {
    if (value == null) return null;
    final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(value);
    if (match == null) return null;
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    if (hour > 23 || minute > 59) return null;
    return hour * 60 + minute;
  }

  void _setStart(TimelineItem item, int minutes) {
    final value = _formatTime(minutes);
    item.time = value;
    item.scheduledTime = value;
  }

  String _formatTime(int minutes) {
    final hour = minutes ~/ 60;
    final minute = minutes % 60;
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  DayPlan? _day(Trip trip, int dayNumber) {
    for (final day in trip.days) {
      if (day.dayNumber == dayNumber) return day;
    }
    return null;
  }

  TimelineItem? _activity(Trip trip, String activityId) {
    for (final day in trip.days) {
      for (final item in day.items) {
        if (item.id == activityId) return item;
      }
    }
    return null;
  }

  PlanEditFailure _missingDay(int dayNumber) => PlanEditFailure(
        PlanEditFailureCode.dayNotFound,
        message: '$dayNumber. gün bulunamadı.',
      );

  PlanEditFailure _missingActivity(String activityId) => PlanEditFailure(
        PlanEditFailureCode.activityNotFound,
        message: 'Aktivite bulunamadı.',
        activityId: activityId,
      );

  PlanEditFailure _invalidIndex() => const PlanEditFailure(
        PlanEditFailureCode.invalidIndex,
        message: 'Hedef sıra geçersiz.',
      );

  PlanEditFailure _locked(TimelineItem item) => PlanEditFailure(
        PlanEditFailureCode.lockedActivity,
        message: item.lockReason ??
            'Bu bilgi bir rezervasyondan geliyor ve değiştirilemez.',
        activityId: item.id,
      );

  Trip _cloneTrip(Trip trip) => Trip.fromJson(trip.toJson());

  TimelineItem _cloneItem(TimelineItem item) =>
      TimelineItem.fromJson(item.toJson());

  Map<String, ({int day, String? time})> _activityLocations(Trip trip) => {
        for (final day in trip.days)
          for (final item in day.items)
            item.id: (
              day: day.dayNumber,
              time: item.time ?? item.scheduledTime
            ),
      };

  List<PlanChange> _changes(
    Map<String, ({int day, String? time})> before,
    Trip after,
  ) {
    final result = <PlanChange>[];
    for (final day in after.days) {
      for (final item in day.items) {
        final old = before[item.id];
        if (old == null || old.day != day.dayNumber || old.time != item.time) {
          result.add(PlanChange(
            activityId: item.id,
            fromDay: old?.day ?? day.dayNumber,
            toDay: day.dayNumber,
            oldTime: old?.time,
            newTime: item.time ?? item.scheduledTime,
          ));
        }
      }
    }
    return result;
  }

  void _applyKnownReservationLocks(Trip trip) {
    final purchasedTickets = {
      for (final ticket in trip.tickets)
        if (ticket.purchased) ticket.label: ticket,
    };
    for (final day in trip.days) {
      for (final item in day.items) {
        if (item.isFixed) continue;
        final title = item.title.toLowerCase();
        final ticket = purchasedTickets[item.title];
        final isArrivalOrDeparture = title.contains('arrival') ||
            title.contains('departure') ||
            title.contains('varış') ||
            title.contains('kalkış');
        final isFlight = title.contains('✈️') ||
            title.contains('🛬') ||
            ((title.contains('flight') || title.contains('uçuş')) &&
                isArrivalOrDeparture);
        final isTrainBoundary = (title.contains('train') ||
                title.contains('tren') ||
                title.contains('shinkansen')) &&
            isArrivalOrDeparture;
        final isHotelBoundary = title.contains('check-in') ||
            title.contains('check in') ||
            title.contains('check-out') ||
            title.contains('check out');
        if (ticket == null &&
            !isFlight &&
            !isTrainBoundary &&
            !isHotelBoundary) {
          continue;
        }

        item.lockType = isFlight || ticket?.kind == TicketKind.flight.name
            ? ActivityLockType.flight
            : isTrainBoundary
                ? ActivityLockType.trainReservation
                : isHotelBoundary
                    ? ActivityLockType.hotel
                    : ticket?.kind == TicketKind.train.name
                        ? ActivityLockType.trainReservation
                        : ActivityLockType.ticketedEvent;
        item.fixedStartTime ??= item.time ?? item.scheduledTime;
        item.canChangeDay = false;
        item.canChangeTime = false;
        item.canReorder = false;
        item.canDelete = false;
      }
    }
  }
}
