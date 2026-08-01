import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/route_matrix_cache.dart';
import '../../data/route_matrix_remote.dart';
import '../../data/route_matrix_resolution.dart';
import '../../domain/itinerary_optimizer.dart';
import '../../domain/route_matrix.dart';
import '../../domain/types.dart';

typedef OptimizedPlanPersist = Future<void> Function(Trip trip);

class DayOptimizationInput {
  const DayOptimizationInput({
    required this.trip,
    required this.dayNumber,
    required this.planVersion,
    required this.constraints,
    this.preferences = const RoutePreferences(),
  });

  final Trip trip;
  final int dayNumber;
  final int planVersion;
  final DayRouteConstraints constraints;
  final RoutePreferences preferences;
}

class RouteSummary {
  const RouteSummary({
    required this.totalTravelMinutes,
    required this.totalWalkingMinutes,
    required this.totalTransferCount,
    required this.estimatedTransportCostYen,
    required this.isComplete,
  });

  final int totalTravelMinutes;
  final int totalWalkingMinutes;
  final int totalTransferCount;
  final int estimatedTransportCostYen;
  final bool isComplete;
}

class PlanOptimizationPreview {
  const PlanOptimizationPreview({
    required this.originalTrip,
    required this.optimizedTrip,
    required this.dayNumber,
    required this.before,
    required this.after,
    required this.result,
    required this.cacheKey,
    this.fromCache = false,
    this.isConfirmed = false,
  });

  final Trip originalTrip;
  final Trip optimizedTrip;
  final int dayNumber;
  final RouteSummary before;
  final RouteSummary after;
  final OptimizationResult result;
  final String cacheKey;
  final bool fromCache;
  final bool isConfirmed;

  PlanOptimizationPreview copyWith({
    bool? fromCache,
    bool? isConfirmed,
  }) {
    return PlanOptimizationPreview(
      originalTrip: originalTrip,
      optimizedTrip: optimizedTrip,
      dayNumber: dayNumber,
      before: before,
      after: after,
      result: result,
      cacheKey: cacheKey,
      fromCache: fromCache ?? this.fromCache,
      isConfirmed: isConfirmed ?? this.isConfirmed,
    );
  }
}

abstract interface class PlanOptimizationPreviewCache {
  PlanOptimizationPreview? get(String key);
  void put(String key, PlanOptimizationPreview preview);
}

class InMemoryPlanOptimizationPreviewCache
    implements PlanOptimizationPreviewCache {
  final Map<String, PlanOptimizationPreview> _entries = {};

  @override
  PlanOptimizationPreview? get(String key) => _entries[key];

  @override
  void put(String key, PlanOptimizationPreview preview) {
    _entries[key] = preview;
  }
}

final routeMatrixBackendGatewayProvider =
    Provider<RouteMatrixBackendGateway>((ref) {
  return const UnavailableRouteMatrixBackendGateway();
});

final routeMatrixSnapshotCacheProvider =
    Provider<RouteMatrixSnapshotCache>((ref) {
  return InMemoryRouteMatrixSnapshotCache();
});

final routeMatrixRepositoryProvider = Provider<RouteMatrixRepository>((ref) {
  final remote = RemoteRouteMatrixRepository(
    gateway: ref.watch(routeMatrixBackendGatewayProvider),
    providerId: 'rotori-route-backend',
  );
  return ResilientRouteMatrixRepository(
    ResilientRouteMatrixResolver(
      primary: remote,
      primaryProviderId: remote.providerId,
      cache: ref.watch(routeMatrixSnapshotCacheProvider),
    ),
  );
});

final itineraryOptimizerProvider = Provider<ItineraryOptimizer>((ref) {
  return const BeamSearchItineraryOptimizer();
});

final planOptimizationPreviewCacheProvider =
    Provider<PlanOptimizationPreviewCache>((ref) {
  return InMemoryPlanOptimizationPreviewCache();
});

final planOptimizationControllerProvider =
    AsyncNotifierProvider<PlanOptimizationController, PlanOptimizationPreview?>(
  PlanOptimizationController.new,
);

class PlanOptimizationController
    extends AsyncNotifier<PlanOptimizationPreview?> {
  @override
  FutureOr<PlanOptimizationPreview?> build() => null;

  Future<void> optimizeDay(DayOptimizationInput input) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _buildPreview(input));
  }

  Future<bool> confirm(OptimizedPlanPersist persist) async {
    final preview = state.valueOrNull;
    if (preview == null || preview.isConfirmed) return false;
    state = const AsyncLoading();
    try {
      await persist(_cloneTrip(preview.optimizedTrip));
      state = AsyncData(preview.copyWith(isConfirmed: true));
      return true;
    } on Object catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      return false;
    }
  }

  void discard() {
    state = const AsyncData(null);
  }

  Future<PlanOptimizationPreview> _buildPreview(
    DayOptimizationInput input,
  ) async {
    final dayIndex = input.trip.days.indexWhere(
      (day) => day.dayNumber == input.dayNumber,
    );
    if (dayIndex < 0) {
      throw ArgumentError.value(
        input.dayNumber,
        'dayNumber',
        'Plan günü bulunamadı.',
      );
    }
    final day = input.trip.days[dayIndex];
    final dayDate = DateTime.tryParse(day.date);
    if (dayDate == null) {
      throw FormatException('Plan günü tarihi geçersiz: ${day.date}');
    }

    final activities = day.items.map((item) {
      final lat = item.lat;
      final lng = item.lng;
      if (lat == null || lng == null) {
        throw StateError(
          '${item.title} için rota koordinatı bulunamadı.',
        );
      }
      final duration = _durationFor(item);
      final fixedStart = item.isFixed
          ? _onDay(dayDate, item.fixedStartTime ?? item.time)
          : null;
      return OptimizationActivity(
        id: item.id,
        name: item.title,
        day: dayDate,
        location: TripLocation(
          id: item.id,
          name: item.title,
          latitude: lat,
          longitude: lng,
          city: item.cityId,
          clusterId: item.cityId,
        ),
        durationMinutes: duration,
        minimumDurationMinutes: duration,
        fixedStartTime: fixedStart,
        fixedEndTime: _onDay(dayDate, item.fixedEndTime),
        isFixed: item.isFixed,
        isLocked: item.lockType != ActivityLockType.none ||
            !item.canChangeDay ||
            !item.canChangeTime ||
            !item.canReorder,
        hasReservation: item.lockType == ActivityLockType.trainReservation ||
            item.lockType == ActivityLockType.ticketedEvent ||
            item.lockType == ActivityLockType.external,
        category: item.kind?.name,
      );
    }).toList(growable: false);

    final locations = <String, TripLocation>{
      input.constraints.startLocation.id: input.constraints.startLocation,
      input.constraints.endLocation.id: input.constraints.endLocation,
      for (final activity in activities)
        activity.location.id: activity.location,
    }.values.toList(growable: false);
    RouteMatrix matrix;
    try {
      matrix = await ref.read(routeMatrixRepositoryProvider).getRouteMatrix(
            locations: locations,
            day: dayDate,
            preferences: input.preferences,
          );
    } on Object {
      // Rota servisi kapalıyken kullanıcıya boş bir önizleme göstermek yerine
      // mevcut koordinatlardan güvenli bir tahmin üret. Gerçek backend tekrar
      // çalıştığında bir sonraki optimizasyonda otomatik olarak kullanılır.
      matrix = buildCoordinateFallbackMatrix(locations);
    }
    final cacheKey = _cacheKey(input, day, matrix.version);
    final previewCache = ref.read(planOptimizationPreviewCacheProvider);
    final cached = previewCache.get(cacheKey);
    if (cached != null) return cached.copyWith(fromCache: true);

    final request = OptimizationRequest(
      activities: activities,
      routeMatrix: matrix,
      constraints: input.constraints,
      preferences: input.preferences,
    );
    final result = await ref.read(itineraryOptimizerProvider).optimize(request);
    if (!result.isSuccess || result.metrics == null) {
      throw PlanOptimizationException(result.failure);
    }

    final optimizedTrip = _applyResult(input.trip, dayIndex, result);
    final preview = PlanOptimizationPreview(
      originalTrip: _cloneTrip(input.trip),
      optimizedTrip: optimizedTrip,
      dayNumber: input.dayNumber,
      before: _summarizeOriginal(request, day.items),
      after: RouteSummary(
        totalTravelMinutes: result.metrics!.totalTravelMinutes,
        totalWalkingMinutes: result.metrics!.totalWalkingMinutes,
        totalTransferCount: result.metrics!.totalTransferCount,
        estimatedTransportCostYen: result.metrics!.estimatedTransportCostYen,
        isComplete: true,
      ),
      result: result,
      cacheKey: cacheKey,
    );
    previewCache.put(cacheKey, preview);
    return preview;
  }

  Trip _applyResult(
    Trip original,
    int dayIndex,
    OptimizationResult result,
  ) {
    final trip = _cloneTrip(original);
    final day = trip.days[dayIndex];
    final byId = {for (final item in day.items) item.id: item};
    final optimizedItems = result.activities.map((scheduled) {
      final item = byId[scheduled.activityId]!;
      final time = _formatTime(scheduled.startTime);
      return item.copyWith(time: time, scheduledTime: time);
    }).toList(growable: false);
    trip.days[dayIndex] = day.copyWith(items: optimizedItems);
    return trip;
  }

  RouteSummary _summarizeOriginal(
    OptimizationRequest request,
    List<TimelineItem> items,
  ) {
    var fromId = request.constraints.startLocation.id;
    var travel = 0;
    var walking = 0;
    var transfers = 0;
    var cost = 0;
    var complete = true;
    final targetIds = [
      ...items.map((item) => item.id),
      request.constraints.endLocation.id,
    ];
    for (final toId in targetIds) {
      final options = request.routeMatrix
          .options(fromId, toId)
          .where((option) => option.isValid);
      TransportOption? best;
      var bestScore = double.infinity;
      for (final option in options) {
        final score = option.doorToDoorMinutes * request.weights.travel +
            option.walkingMinutes * request.weights.walking +
            option.waitingMinutes * request.weights.waiting +
            option.transferCount * request.weights.transfer +
            option.estimatedCostYen * request.weights.transportCost / 100;
        if (score < bestScore) {
          best = option;
          bestScore = score;
        }
      }
      if (best == null) {
        complete = false;
      } else {
        travel += best.doorToDoorMinutes;
        walking += best.walkingMinutes;
        transfers += best.transferCount;
        cost += best.estimatedCostYen;
      }
      fromId = toId;
    }
    return RouteSummary(
      totalTravelMinutes: travel,
      totalWalkingMinutes: walking,
      totalTransferCount: transfers,
      estimatedTransportCostYen: cost,
      isComplete: complete,
    );
  }
}

class PlanOptimizationException implements Exception {
  const PlanOptimizationException(this.failure);

  final OptimizationFailure? failure;

  @override
  String toString() => failure?.message ?? 'Uygulanabilir rota oluşturulamadı.';
}

int _durationFor(TimelineItem item) {
  if (item.durationMin != null && item.durationMin! > 0) {
    return item.durationMin!;
  }
  return switch (item.kind) {
    TimelineItemKind.meal => 60,
    TimelineItemKind.transport || TimelineItemKind.hotel => 30,
    _ => 90,
  };
}

DateTime? _onDay(DateTime day, String? value) {
  if (value == null || value.isEmpty) return null;
  final parts = value.split(':');
  if (parts.length != 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null ||
      minute == null ||
      hour < 0 ||
      hour > 23 ||
      minute < 0 ||
      minute > 59) {
    return null;
  }
  return DateTime(day.year, day.month, day.day, hour, minute);
}

String _formatTime(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}';

String _cacheKey(
  DayOptimizationInput input,
  DayPlan day,
  String matrixVersion,
) {
  final activitySource = day.items
      .map((item) => [
            item.id,
            item.lat,
            item.lng,
            item.durationMin,
            item.fixedStartTime,
            item.fixedEndTime,
            item.lockType.name,
            item.time,
          ].join('|'))
      .join('\u0000');
  return [
    input.trip.id,
    input.planVersion,
    _stableHash(activitySource),
    input.preferences.profile.name,
    matrixVersion,
  ].join(':');
}

String _stableHash(String value) {
  var hash = 0x811c9dc5;
  for (final unit in value.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash.toRadixString(16);
}

Trip _cloneTrip(Trip trip) => Trip.fromJson(trip.toJson());
