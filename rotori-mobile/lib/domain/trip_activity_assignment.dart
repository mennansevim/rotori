import 'itinerary_optimizer.dart';
import 'route_matrix.dart';

enum AssignmentDayType { arrival, full, transfer, departure }

enum ActivityDayRole { normal, halfDayAnchor, fullDayExclusive, excursion }

class TripAssignmentDay {
  const TripAssignmentDay({
    required this.index,
    required this.city,
    required this.type,
    required this.startTime,
    required this.endTime,
    required this.hotel,
    this.requiredMealMinutes = 0,
    this.minimumTransitionMinutes = 10,
    this.returnMinutes = 10,
    this.maxActivities,
  });

  final int index;
  final String city;
  final AssignmentDayType type;
  final DateTime startTime;
  final DateTime endTime;
  final TripLocation hotel;
  final int requiredMealMinutes;
  final int minimumTransitionMinutes;
  final int returnMinutes;
  final int? maxActivities;

  int get availableMinutes => endTime.difference(startTime).inMinutes;
  bool get acceptsActivities => type != AssignmentDayType.departure;
}

class AssignableTripActivity {
  const AssignableTripActivity({
    required this.activity,
    required this.city,
    this.dayRole = ActivityDayRole.normal,
    this.fixedDayIndex,
    this.repeatFixture = false,
  });

  final OptimizationActivity activity;
  final String city;
  final ActivityDayRole dayRole;
  final int? fixedDayIndex;
  final bool repeatFixture;
}

enum AssignmentFailureCode {
  invalidInput,
  protectedActivityInfeasible,
}

class AssignmentFailure {
  const AssignmentFailure({
    required this.code,
    required this.message,
    this.activityId,
  });

  final AssignmentFailureCode code;
  final String message;
  final String? activityId;
}

class TripActivityAssignmentResult {
  TripActivityAssignmentResult({
    required Map<int, List<AssignableTripActivity>> assignments,
    List<DroppedActivity> dropped = const [],
    this.failure,
  })  : assignments = Map<int, List<AssignableTripActivity>>.unmodifiable({
          for (final entry in assignments.entries)
            entry.key: List<AssignableTripActivity>.unmodifiable(entry.value),
        }),
        dropped = List.unmodifiable(dropped);

  final Map<int, List<AssignableTripActivity>> assignments;
  final List<DroppedActivity> dropped;
  final AssignmentFailure? failure;

  bool get isSuccess => failure == null;
}

/// Aynı şehirdeki aktiviteleri günlük optimizer çalışmadan önce günlere böler.
///
/// Maliyet karşılaştırması lexicographic'tir: hard uygunluk, cluster bölünmesi,
/// transit alt sınırı, yük dengesi ve gün indeksi. Böylece hash/map sırası
/// sonucu değiştirmez ve dropping ancak tüm uygun günler denendikten sonra olur.
class TripActivityAssignmentEngine {
  const TripActivityAssignmentEngine();

  TripActivityAssignmentResult assign({
    required List<TripAssignmentDay> days,
    required List<AssignableTripActivity> activities,
  }) {
    final dayByIndex = {for (final day in days) day.index: day};
    if (dayByIndex.length != days.length) {
      return TripActivityAssignmentResult(
        assignments: const {},
        failure: const AssignmentFailure(
          code: AssignmentFailureCode.invalidInput,
          message: 'Gün indeksleri benzersiz olmalıdır.',
        ),
      );
    }
    final duplicateIds = <String>{};
    final seenIds = <String>{};
    for (final item in activities) {
      if (!seenIds.add(item.activity.id) && !item.repeatFixture) {
        duplicateIds.add(item.activity.id);
      }
    }
    if (duplicateIds.isNotEmpty) {
      return TripActivityAssignmentResult(
        assignments: const {},
        failure: AssignmentFailure(
          code: AssignmentFailureCode.invalidInput,
          message: 'Açıklanmamış tekrar aktivitesi bulundu.',
          activityId: duplicateIds.first,
        ),
      );
    }

    final buckets = <int, List<AssignableTripActivity>>{
      for (final day in days) day.index: [],
    };
    final remaining = [...activities]..sort(_activityOrder);
    final dropped = <DroppedActivity>[];

    // Fixed/locked ve açık fixedDayIndex önce yerleşir.
    for (final item in [...remaining]) {
      final fixedIndex = item.fixedDayIndex;
      if (fixedIndex == null && !item.activity.hasFixedSchedule) continue;
      final target = fixedIndex ?? _dayIndexOf(item.activity.day, days);
      final day = target == null ? null : dayByIndex[target];
      if (day == null || !_canAssign(day, buckets[target]!, item)) {
        return _protectedFailure(buckets, item, days);
      }
      buckets[target]!.add(item);
      remaining.remove(item);
    }

    // Exclusive/excursion aktivitesi mümkünse boş tam güne ayrılır.
    for (final item in [...remaining].where(_isSpecial)) {
      final candidates = _candidateDays(days, buckets, item)
          .where((day) =>
              day.type == AssignmentDayType.full && buckets[day.index]!.isEmpty)
          .toList();
      if (candidates.isNotEmpty) {
        buckets[candidates.first.index]!.add(item);
        remaining.remove(item);
      }
    }

    for (final item in remaining) {
      final attempted = <int>[];
      final candidates = _candidateDays(days, buckets, item);
      TripAssignmentDay? best;
      List<num>? bestCost;
      for (final day in candidates) {
        attempted.add(day.index);
        if (!_canAssign(day, buckets[day.index]!, item)) continue;
        final cost = _assignmentCost(day, buckets, item);
        if (bestCost == null || _compareCost(cost, bestCost) < 0) {
          best = day;
          bestCost = cost;
        }
      }
      if (best != null) {
        buckets[best.index]!.add(item);
        continue;
      }
      if (item.activity.priority == ActivityPriority.mustDo ||
          item.activity.hasFixedSchedule) {
        return _protectedFailure(buckets, item, days);
      }
      dropped.add(DroppedActivity(
        activityId: item.activity.id,
        name: item.activity.name,
        priority: item.activity.priority,
        reason: DropReason.dayCapacity,
        attemptedDayIndexes: attempted,
      ));
    }

    for (final bucket in buckets.values) {
      bucket.sort(_activityOrder);
    }
    return TripActivityAssignmentResult(
      assignments: buckets,
      dropped: dropped,
    );
  }

  TripActivityAssignmentResult _protectedFailure(
    Map<int, List<AssignableTripActivity>> buckets,
    AssignableTripActivity item,
    List<TripAssignmentDay> days,
  ) =>
      TripActivityAssignmentResult(
        assignments: buckets,
        failure: AssignmentFailure(
          code: AssignmentFailureCode.protectedActivityInfeasible,
          message:
              'Must-do veya sabit aktivite uygun günlerin hiçbirine sığmadı.',
          activityId: item.activity.id,
        ),
      );

  Iterable<TripAssignmentDay> _candidateDays(
    List<TripAssignmentDay> days,
    Map<int, List<AssignableTripActivity>> buckets,
    AssignableTripActivity item,
  ) {
    final candidates = days.where((day) =>
        day.acceptsActivities &&
        day.city == item.city &&
        (item.fixedDayIndex == null || item.fixedDayIndex == day.index));
    final result = candidates.toList()
      ..sort((a, b) {
        final aEmptyFull =
            a.type == AssignmentDayType.full && buckets[a.index]!.isEmpty
                ? 0
                : 1;
        final bEmptyFull =
            b.type == AssignmentDayType.full && buckets[b.index]!.isEmpty
                ? 0
                : 1;
        if (_isSpecial(item) && aEmptyFull != bEmptyFull) {
          return aEmptyFull.compareTo(bEmptyFull);
        }
        return a.index.compareTo(b.index);
      });
    return result;
  }

  bool _canAssign(
    TripAssignmentDay day,
    List<AssignableTripActivity> assigned,
    AssignableTripActivity candidate,
  ) {
    if (day.maxActivities != null && assigned.length >= day.maxActivities!) {
      return false;
    }
    if (_isSpecial(candidate) && assigned.isNotEmpty) return false;
    if (assigned.any(_isSpecial)) return false;
    final next = [...assigned, candidate];
    final duration = next.fold<int>(
      0,
      (sum, item) => sum + item.activity.durationMinutes,
    );
    final transitions = day.minimumTransitionMinutes * next.length;
    final lowerBound = duration +
        transitions +
        day.returnMinutes +
        (next.isEmpty ? 0 : day.requiredMealMinutes);
    if (lowerBound > day.availableMinutes) return false;

    // Erken kapanan aktiviteler için gerekli en erken bitiş alt sınırı.
    // Tarihler farklı olabilir; assignment yalnız gün içi saat/dakikayı kıyaslar.
    final byClosing = [...next]..sort((a, b) {
        final ac = a.activity.closingTime;
        final bc = b.activity.closingTime;
        if (ac == null && bc == null) {
          return a.activity.id.compareTo(b.activity.id);
        }
        if (ac == null) return 1;
        if (bc == null) return -1;
        final minuteA = ac.hour * 60 + ac.minute;
        final minuteB = bc.hour * 60 + bc.minute;
        final comparison = minuteA.compareTo(minuteB);
        return comparison != 0
            ? comparison
            : a.activity.id.compareTo(b.activity.id);
      });
    var cursor = day.startTime.hour * 60 + day.startTime.minute;
    for (final item in byClosing) {
      final opening = item.activity.openingTime;
      if (opening != null) {
        final openingMinute = opening.hour * 60 + opening.minute;
        if (cursor < openingMinute) cursor = openingMinute;
      }
      cursor += day.minimumTransitionMinutes + item.activity.durationMinutes;
      final closing = item.activity.closingTime;
      if (closing != null && cursor > closing.hour * 60 + closing.minute) {
        return false;
      }
    }
    return true;
  }

  List<num> _assignmentCost(
    TripAssignmentDay day,
    Map<int, List<AssignableTripActivity>> buckets,
    AssignableTripActivity candidate,
  ) {
    final bucket = buckets[day.index]!;
    final cluster = candidate.activity.clusterId;
    final clusterOnOtherDay = cluster == null
        ? false
        : buckets.entries.any((entry) =>
            entry.key != day.index &&
            entry.value.any((item) => item.activity.clusterId == cluster));
    final sameCluster = cluster != null &&
        bucket.any((item) => item.activity.clusterId == cluster);
    final fragmentation = clusterOnOtherDay && !sameCluster ? 1 : 0;
    final transitLowerBound =
        day.minimumTransitionMinutes * (bucket.length + 1);
    final load = bucket.fold<int>(
          0,
          (sum, item) => sum + item.activity.durationMinutes,
        ) +
        candidate.activity.durationMinutes;
    final utilization = day.availableMinutes == 0
        ? 1000000
        : (load * 1000 ~/ day.availableMinutes);
    return [fragmentation, transitLowerBound, utilization, day.index];
  }

  int _compareCost(List<num> a, List<num> b) {
    for (var i = 0; i < a.length; i++) {
      final comparison = a[i].compareTo(b[i]);
      if (comparison != 0) return comparison;
    }
    return 0;
  }

  int _activityOrder(
    AssignableTripActivity a,
    AssignableTripActivity b,
  ) {
    final fixedA =
        a.activity.hasFixedSchedule || a.fixedDayIndex != null ? 0 : 1;
    final fixedB =
        b.activity.hasFixedSchedule || b.fixedDayIndex != null ? 0 : 1;
    if (fixedA != fixedB) return fixedA.compareTo(fixedB);
    final specialA = _isSpecial(a) ? 0 : 1;
    final specialB = _isSpecial(b) ? 0 : 1;
    if (specialA != specialB) return specialA.compareTo(specialB);
    final priority =
        b.activity.priority.index.compareTo(a.activity.priority.index);
    if (priority != 0) return priority;
    final aClose = a.activity.closingTime?.millisecondsSinceEpoch ?? 1 << 62;
    final bClose = b.activity.closingTime?.millisecondsSinceEpoch ?? 1 << 62;
    if (aClose != bClose) return aClose.compareTo(bClose);
    final cluster =
        (a.activity.clusterId ?? '').compareTo(b.activity.clusterId ?? '');
    if (cluster != 0) return cluster;
    return a.activity.id.compareTo(b.activity.id);
  }

  bool _isSpecial(AssignableTripActivity item) =>
      item.dayRole == ActivityDayRole.fullDayExclusive ||
      item.dayRole == ActivityDayRole.excursion;

  int? _dayIndexOf(DateTime date, List<TripAssignmentDay> days) {
    for (final day in days) {
      final target = day.startTime;
      if (target.year == date.year &&
          target.month == date.month &&
          target.day == date.day) {
        return day.index;
      }
    }
    return null;
  }
}
