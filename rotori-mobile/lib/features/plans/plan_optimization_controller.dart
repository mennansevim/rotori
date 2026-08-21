import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/offline_japan_route_matrix.dart';
import '../../domain/day_optimizer.dart';
import '../../domain/destination_profiles.dart';
import '../../domain/itinerary_optimizer.dart';
import '../../domain/japan_calendar.dart';
import '../../domain/japan_transit_realism.dart';
import '../../domain/luggage_logistics.dart';
import '../../domain/plan_field_signals.dart';
import '../../domain/plan_warnings.dart';
import '../../domain/route_field_context.dart';
import '../../domain/route_time_bounds.dart';
import '../../domain/route_matrix.dart';
import '../../domain/route_execution.dart';
import '../../domain/route_optimization_validator.dart';
import '../../domain/japan_suggestions.dart'
    show isTimeLocked, isTimedEntryTitle;
import '../../domain/types.dart';

typedef OptimizedPlanPersist = Future<void> Function(Trip trip);

class DayOptimizationInput {
  const DayOptimizationInput({
    required this.trip,
    required this.dayNumber,
    required this.planVersion,
    required this.constraints,
    this.preferences = const RoutePreferences(),
    this.preferredActivityOrder = const [],
  });

  final Trip trip;
  final int dayNumber;
  final int planVersion;
  final DayRouteConstraints constraints;
  final RoutePreferences preferences;
  final List<String> preferredActivityOrder;
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
    this.preferredActivityOrder = const [],
    this.executionLegs = const [],
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
  final List<String> preferredActivityOrder;
  final List<RouteExecutionLeg> executionLegs;
  final bool fromCache;
  final bool isConfirmed;

  /// Optimize edilmiş rota mevcut rotadan GERÇEKTEN iyi mi?
  ///
  /// **Neden gerekli:** Sayfa `before`/`after` kartlarını gösterip her koşulda
  /// "Uygula" sunuyordu. Gün zaten en iyi sırada olduğunda iki kart birebir
  /// aynı çıkıyor, kullanıcı yine de uygulayabiliyor ve hiçbir şey değişmiyor —
  /// planı "optimize edilmiş" diye işaretleyen boş bir işlem.
  ///
  /// Sıralama hedefin önem sırasıdır: ulaşım süresi > yürüyüş > aktarma sayısı
  /// > maliyet. Eşitlikte bir sonrakine bakılır; hepsi eşitse kazanç yok.
  bool get improvesRoute {
    if (_improvesPreferredOrder) return true;
    if (after.totalTravelMinutes != before.totalTravelMinutes) {
      return after.totalTravelMinutes < before.totalTravelMinutes;
    }
    if (after.totalWalkingMinutes != before.totalWalkingMinutes) {
      return after.totalWalkingMinutes < before.totalWalkingMinutes;
    }
    if (after.totalTransferCount != before.totalTransferCount) {
      return after.totalTransferCount < before.totalTransferCount;
    }
    return after.estimatedTransportCostYen < before.estimatedTransportCostYen;
  }

  bool get _improvesPreferredOrder {
    if (preferredActivityOrder.isEmpty) return false;
    List<String> ids(Trip trip) => trip.days
        .where((day) => day.dayNumber == dayNumber)
        .expand((day) => day.items)
        .map((item) => item.id)
        .toList(growable: false);
    int deviation(List<String> order) {
      var total = 0;
      for (var index = 0; index < order.length; index++) {
        final preferredIndex = preferredActivityOrder.indexOf(order[index]);
        if (preferredIndex >= 0) total += (preferredIndex - index).abs();
      }
      return total;
    }

    final beforeOrder = ids(originalTrip);
    final afterOrder = ids(optimizedTrip);
    return afterOrder.join('\u0000') != beforeOrder.join('\u0000') &&
        deviation(afterOrder) < deviation(beforeOrder);
  }

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
      preferredActivityOrder: preferredActivityOrder,
      executionLegs: executionLegs,
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

final routeMatrixRepositoryProvider = Provider<RouteMatrixRepository>((ref) {
  return const OfflineJapanRouteMatrixRepository();
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

  /// Yeni plan oluşturulurken de aynı optimizasyon ve doğrulama hattını,
  /// kullanıcıya ayrı bir onay ekranı açmadan çalıştırır.
  Future<PlanOptimizationPreview> buildInitialPreview(
    DayOptimizationInput input,
  ) {
    return _buildPreview(input);
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
    final cityId = _dominantCity(input.trip, day);
    final field = _fieldRealityFor(
      input: input,
      day: day,
      dayDate: dayDate,
      cityId: cityId,
    );

    final activities = day.items.map((item) {
      final lat = item.lat;
      final lng = item.lng;
      if (lat == null || lng == null) {
        throw StateError(
          '${item.title} için rota koordinatı bulunamadı.',
        );
      }
      final duration = _durationFor(item);
      // Saatli giriş (teamLab/Disney/USJ) ve elle kilitlenenler: saat SABİT.
      // isFixed alanı eski planlarda boş olabildiği için başlıktan türetmeyi
      // de kapsayan isTimeLocked kullanılır.
      final locked = isTimeLocked(item);
      final fixedStart =
          locked ? _onDay(dayDate, item.fixedStartTime ?? item.time) : null;
      // Öğün kalemleri sabit değilse makul bir zaman penceresine bağlanır;
      // böylece optimizasyon öğle yemeğini sabahın köründe (ör. 06:13)
      // planlayamaz. Sabit öğünler kendi saatlerini korur.
      final mealWindow = locked ? null : _mealWindow(dayDate, item);
      final venueOpening = _onDay(dayDate, item.openingTime);
      final venueClosing = _onDay(dayDate, item.closingTime);
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
          clusterId: offlineJapanRouteClusterId(
            city: item.cityId,
            latitude: lat,
            longitude: lng,
          ),
        ),
        durationMinutes: duration,
        minimumDurationMinutes: duration,
        requiredArrivalBufferMinutes: item.arrivalBufferMin ?? 0,
        openingTime: venueOpening ?? mealWindow?.open,
        closingTime: venueClosing ?? mealWindow?.close,
        preferredTime: mealWindow?.preferred,
        fixedStartTime: fixedStart,
        fixedEndTime: _onDay(dayDate, item.fixedEndTime),
        isFixed: locked,
        isLocked: locked ||
            item.lockType != ActivityLockType.none ||
            !item.canChangeDay ||
            !item.canChangeTime ||
            !item.canReorder,
        // Kullanıcı kilidi rezervasyon sayılır: kilidi koymasının sebebi
        // zaten "bileti aldım" — motor bu durakları taşımaya çalışmadan önce
        // rezervasyonlu duraklarla aynı korumayı uygular.
        hasReservation: item.lockType == ActivityLockType.trainReservation ||
            item.lockType == ActivityLockType.ticketedEvent ||
            item.lockType == ActivityLockType.external ||
            item.isUserPinned ||
            isTimedEntryTitle(item.title),
        category: item.kind?.name,
        cityId: item.cityId ?? cityId,
        closureRule: _closureRuleFor(item),
        requiresHotelCheckIn: _isHotelCheckIn(item),
        repeatRule: _repeatRuleFor(item),
        // Kilitli durak asla "yer açmak için" düşürülmez.
        priority:
            item.kind == TimelineItemKind.meal || locked || item.isUserPinned
                ? ActivityPriority.mustDo
                : ActivityPriority.normal,
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
            day: input.constraints.availableStartTime,
            preferences: input.preferences,
          );
    } on Object {
      // Enjekte edilmiş bir repository hata verse bile plan kaybolmaz; aynı
      // sürümlü cihaz-içi paketle deterministik olarak yeniden kurulur.
      matrix = buildOfflineJapanRouteMatrix(
        locations,
        day: input.constraints.availableStartTime,
        preferences: input.preferences,
      );
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
      field: field,
      preferredActivityOrder: input.preferredActivityOrder,
    );
    final result = await ref.read(itineraryOptimizerProvider).optimize(request);
    if (!result.isSuccess || result.metrics == null) {
      final fallbackPreview = _buildLocalFallbackPreview(
        input: input,
        dayIndex: dayIndex,
        request: request,
        cacheKey: cacheKey,
        failure: result.failure,
      );
      if (fallbackPreview != null) return fallbackPreview;
      throw PlanOptimizationException(result.failure);
    }
    final validationIssues = const RouteOptimizationValidator().validate(
      request,
      result,
    );
    if (validationIssues.isNotEmpty) {
      final failure = OptimizationFailure(
        code: OptimizationFailureCode.invalidRequest,
        message: 'Rota doğrulama başarısız: ${validationIssues.first.message}',
        activityId: validationIssues.first.activityId,
        fromLocationId: validationIssues.first.fromLocationId,
        toLocationId: validationIssues.first.toLocationId,
      );
      throw PlanOptimizationException(failure);
    }

    final executionLegs = const RouteExecutionBuilder().build(
      result: result,
      startLocationId: input.constraints.startLocation.id,
      endLocationId: input.constraints.endLocation.id,
      locationNames: {
        input.constraints.startLocation.id:
            input.constraints.startLocation.name,
        input.constraints.endLocation.id: input.constraints.endLocation.name,
        for (final activity in activities)
          activity.location.id: activity.location.name,
      },
    );
    final snapshot = RouteExecutionSnapshot(
      planId: input.trip.id,
      dayNumber: input.dayNumber,
      planVersion: input.planVersion,
      activityHash: _activityHash(day),
      matrixVersion: matrix.version,
      generatedAt: DateTime.now().toUtc(),
      profile: input.preferences.profile,
      providerIds: executionLegs
          .map((leg) => leg.providerId)
          .whereType<String>()
          .toSet()
          .toList(growable: false),
      legs: executionLegs,
    );
    final optimizedTrip = _applyResult(
      input.trip,
      dayIndex,
      result,
      routeExecutionSnapshot: snapshot,
    );
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
      preferredActivityOrder: input.preferredActivityOrder,
      executionLegs: executionLegs,
    );
    previewCache.put(cacheKey, preview);
    return preview;
  }

  Trip _applyResult(Trip original, int dayIndex, OptimizationResult result,
      {required RouteExecutionSnapshot routeExecutionSnapshot}) {
    final trip = _cloneTrip(original);
    final day = trip.days[dayIndex];
    final byId = {for (final item in day.items) item.id: item};
    final scheduled = result.activities
        .map(
          (activity) => (
            item: byId[activity.activityId]!,
            startMinutes: _toMinutes(activity.startTime),
          ),
        )
        .toList(growable: false);
    final normalizedStarts = _normalizeStartMinutes(scheduled);
    final optimizedItems = [
      for (var i = 0; i < scheduled.length; i++)
        scheduled[i].item.copyWith(
              time: _formatMinuteOfDay(normalizedStarts[i]),
              scheduledTime: _formatMinuteOfDay(normalizedStarts[i]),
            ),
    ];
    trip.days[dayIndex] = day.copyWith(
      items: optimizedItems,
      routeExecutionSnapshot: routeExecutionSnapshot,
    );
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

  PlanOptimizationPreview? _buildLocalFallbackPreview({
    required DayOptimizationInput input,
    required int dayIndex,
    required OptimizationRequest request,
    required String cacheKey,
    required OptimizationFailure? failure,
  }) {
    if (!_shouldUseLocalFallback(
      failure,
      hasFieldReality: request.field != null,
    )) {
      return null;
    }

    final originalDay = input.trip.days[dayIndex];
    final optimizedItems = optimizeDayItems(
      originalDay.items.map((item) => item.copyWith()).toList(growable: false),
    );
    if (optimizedItems.isEmpty) return null;

    final fixedById = {
      for (final item in originalDay.items)
        if (isTimeLocked(item)) item.id: item,
    };
    final normalizedItems = [
      for (final item in optimizedItems)
        if (fixedById.containsKey(item.id))
          item.copyWith(
            time: fixedById[item.id]!.time,
            scheduledTime: fixedById[item.id]!.scheduledTime,
            fixedStartTime: fixedById[item.id]!.fixedStartTime,
            fixedEndTime: fixedById[item.id]!.fixedEndTime,
          )
        else
          item,
    ];

    final optimizedTrip = _cloneTrip(input.trip);
    optimizedTrip.days[dayIndex] = optimizedTrip.days[dayIndex].copyWith(
      items: normalizedItems,
    );

    final fallbackFailure = failure ??
        const OptimizationFailure(
          code: OptimizationFailureCode.noFeasibleRoute,
          message: 'Kural tabanlı yerel rota önerisi kullanıldı.',
        );

    final preview = PlanOptimizationPreview(
      originalTrip: _cloneTrip(input.trip),
      optimizedTrip: optimizedTrip,
      dayNumber: input.dayNumber,
      before: _summarizeOriginal(request, originalDay.items),
      after: _summarizeOriginal(request, normalizedItems),
      result: OptimizationResult.failure(fallbackFailure),
      cacheKey: cacheKey,
      preferredActivityOrder: input.preferredActivityOrder,
    );
    ref.read(planOptimizationPreviewCacheProvider).put(cacheKey, preview);
    return preview;
  }

  bool _shouldUseLocalFallback(
    OptimizationFailure? failure, {
    required bool hasFieldReality,
  }) {
    if (failure == null) return false;
    // Kural tabanlı fallback saha kapılarını yeniden çalıştırmaz. Takvim,
    // pass, bagaj veya istasyon kuralı etkin bir isteği bu yola sokmak,
    // optimizer'ın reddettiği rotayı sessizce geri getirebilir.
    if (hasFieldReality) return false;
    return switch (failure.code) {
      OptimizationFailureCode.noFeasibleRoute ||
      OptimizationFailureCode.routeDataMissing ||
      OptimizationFailureCode.fixedTimeConflict ||
      OptimizationFailureCode.protectedActivityInfeasible =>
        true,
      _ => false,
    };
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

/// Öğün kalemleri için makul bir zaman penceresi + tercih fazı döndürür.
/// Optimizer bu pencereyi sert kısıt gibi kullanır: başlangıç açılışa çekilir,
/// kapanışı aşan öğün elenir. Faz, kalemin optimizasyon-öncesi saatinden
/// çıkarılır (şablon: 08:00 kahvaltı, 13:00 öğle, 19:00 akşam); saat yoksa
/// öğle varsayılır. Öğün olmayan kalemler için null döner.
/// Öğün için izin verilen zaman penceresi.
///
/// **Pencereler burada TANIMLANMAZ** — [mealPlacementWindow] üzerinden
/// plan_warnings.dart'taki tek kaynaktan gelir. Eskiden bu fonksiyonun kendi
/// saatleri vardı (akşam 17:30'dan açık) ve uyarı motorununkinden (18:00)
/// farklıydı: optimizasyon akşam yemeğini 17:30'a koyuyor, uygulama da kendi
/// çıktısını "normalde 18:00–22:00 arası yenir" diye uyarıyordu.
///
/// Pencere ayrıca rota günüyle (09:00–20:00) kesiştirilir.
({DateTime open, DateTime close, TimeOfDayPreference preferred})? _mealWindow(
  DateTime dayDate,
  TimelineItem item,
) {
  if (!_isMealActivity(item)) return null;
  final minutes = _minutesOf(item.time ?? item.scheduledTime);
  // Başlıktan tür çıkmazsa: 16:00 öncesi öğle, sonrası akşam (eski sezgi).
  final window = mealPlacementWindow(
    item,
    isFirstMeal: minutes < 0 || minutes < 16 * 60,
  );
  if (window == null) return null;

  DateTime at(int totalMinutes) {
    final clamped = totalMinutes.clamp(
      kRouteStartMinuteOfDay,
      kRouteEndHour * 60,
    );
    return DateTime(
      dayDate.year,
      dayDate.month,
      dayDate.day,
      clamped ~/ 60,
      clamped % 60,
    );
  }

  final hint = _mealHint(item.title);
  final pref = hint == _MealHint.breakfast
      ? TimeOfDayPreference.morning
      : window.start >= kDinnerStartMinutes
          ? TimeOfDayPreference.evening
          : TimeOfDayPreference.afternoon;

  return (open: at(window.start), close: at(window.end), preferred: pref);
}

int _minutesOf(String? value) {
  if (value == null || value.isEmpty) return -1;
  final parts = value.split(':');
  if (parts.length != 2) return -1;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return -1;
  return hour * 60 + minute;
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

int _toMinutes(DateTime value) => value.hour * 60 + value.minute;

String _formatMinuteOfDay(int value) {
  final clamped = value.clamp(0, 24 * 60 - 1);
  final hour = (clamped ~/ 60).toString().padLeft(2, '0');
  final minute = (clamped % 60).toString().padLeft(2, '0');
  return '$hour:$minute';
}

List<int> _normalizeStartMinutes(
  List<({TimelineItem item, int startMinutes})> scheduled,
) {
  if (scheduled.isEmpty) return const [];
  final starts = [
    for (final entry in scheduled)
      entry.item.isFixed
          ? entry.startMinutes
          : _floorToStep(entry.startMinutes, 5),
  ];

  // Geçişlerin ani saat sapmalarından doğabilecek 1-4 dakikalık çakışmaları
  // düzeltmek için kısa bir normalize turu uygula.
  for (var pass = 0; pass < scheduled.length; pass++) {
    for (var i = 1; i < scheduled.length; i++) {
      final previous = scheduled[i - 1].item;
      final current = scheduled[i].item;
      final required = starts[i - 1] +
          _durationFor(previous) +
          _minimumGapMinutes(previous, current);
      if (starts[i] >= required) continue;

      if (!current.isFixed) {
        starts[i] = _ceilToStep(required, 5);
        continue;
      }

      if (!previous.isFixed) {
        final latest = _floorToStep(
          starts[i] -
              _durationFor(previous) -
              _minimumGapMinutes(previous, current),
          5,
        );
        if (latest < starts[i - 1]) {
          starts[i - 1] = latest.clamp(0, 24 * 60 - 1);
        }
      }
    }
  }

  return starts;
}

int _floorToStep(int value, int step) => (value ~/ step) * step;

int _ceilToStep(int value, int step) => ((value + step - 1) ~/ step) * step;

int _minimumGapMinutes(TimelineItem previous, TimelineItem current) {
  return _isMealActivity(previous) || _isMealActivity(current) ? 15 : 15;
}

bool _isMealActivity(TimelineItem item) {
  if (item.kind == TimelineItemKind.meal) return true;
  return _mealHint(item.title) != _MealHint.none;
}

enum _MealHint { breakfast, lunch, dinner, none }

_MealHint _mealHint(String title) {
  final value = title.toLowerCase();
  bool has(String token) => value.contains(token);
  if (has('kahvaltı') || has('breakfast') || has('brunch')) {
    return _MealHint.breakfast;
  }
  if (has('öğle') || has('lunch')) return _MealHint.lunch;
  if (has('akşam') || has('dinner')) return _MealHint.dinner;
  return _MealHint.none;
}

String _cacheKey(
  DayOptimizationInput input,
  DayPlan day,
  String matrixVersion,
) {
  return [
    input.trip.id,
    input.planVersion,
    _activityHash(day),
    _stableHash(input.preferredActivityOrder.join('\u0000')),
    _fieldRealityHash(input, day),
    input.preferences.profile.name,
    matrixVersion,
  ].join(':');
}

String _fieldRealityHash(DayOptimizationInput input, DayPlan day) {
  final source = {
    'partySize':
        input.trip.preferences.partySize ?? input.preferences.partySize,
    'routePartySize': input.preferences.partySize,
    'cityTransition': day.cityTransition?.toJson(),
    'luggage': day.luggage?.toJson(),
    'crowd': day.crowd?.toJson(),
    'items': [
      for (final item in day.items)
        {
          'id': item.id,
          'cityId': item.cityId,
          'transit': item.transit?.toJson(),
          'repeat': item.repeat?.toJson(),
          'closure': item.closure?.toJson(),
        },
    ],
  };
  return _stableHash(jsonEncode(source));
}

String _activityHash(DayPlan day) {
  final activitySource = day.items
      .map((item) => [
            item.id,
            item.lat,
            item.lng,
            item.durationMin,
            item.fixedStartTime,
            item.fixedEndTime,
            item.openingTime,
            item.closingTime,
            item.lockType.name,
            item.time,
          ].join('|'))
      .join('\u0000');
  return _stableHash(activitySource);
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

String? _dominantCity(Trip trip, DayPlan day) {
  for (final item in day.items) {
    final cityId = item.cityId?.trim();
    if (cityId != null && cityId.isNotEmpty) return cityId;
  }
  final transitionCity = day.cityTransition?.toCity.trim();
  if (transitionCity != null && transitionCity.isNotEmpty) {
    return transitionCity;
  }
  return getDestinationForDate(trip.preferences.destinations, day.date)?.city;
}

FieldRealityContext _fieldRealityFor({
  required DayOptimizationInput input,
  required DayPlan day,
  required DateTime dayDate,
  required String? cityId,
}) {
  final luggage = day.luggage;
  final railPassValue = day.cityTransition?.railPass ?? _firstRailPass(day);
  final luggageSize = _enumByName(
        LuggageSize.values,
        luggage?.size,
      ) ??
      LuggageSize.none;
  return FieldRealityContext(
    travelDate: dayDate,
    cityId: cityId,
    traveller: TravellerProfile(
      railPass: _railPassFromValue(railPassValue),
      luggageSize: luggageSize,
      bagCount: luggage?.bagCount ?? 0,
      partySize:
          input.trip.preferences.partySize ?? input.preferences.partySize,
    ),
    luggagePlan: _luggagePlanFor(luggage),
  );
}

RailPassType _railPassFromValue(String? value) =>
    _enumByName(RailPassType.values, value) ?? RailPassType.none;

String? _firstRailPass(DayPlan day) {
  for (final item in day.items) {
    final value = item.transit?.railPass;
    if (value != null && value.trim().isNotEmpty) return value;
  }
  return null;
}

LuggagePlan? _luggagePlanFor(LuggageSignals? signals) {
  if (signals == null) return null;
  final strategy = _enumByName(
        LuggageHandlingStrategy.values,
        signals.strategy,
      ) ??
      LuggageHandlingStrategy.none;
  return LuggagePlan(
    strategy: strategy,
    originHandoverMinutes: signals.originHandoverMin,
    arrivalHandlingMinutes: signals.arrivalHandlingMin,
    retrievalMinutes: signals.retrievalMin,
    estimatedCostYen: signals.estimatedCostYen,
    advisories: {
      for (final value in signals.advisories)
        if (_enumByName(LuggageAdvisory.values, value) case final advisory?)
          advisory,
    },
    reasonCode: signals.reasonCode ?? 'persisted-${strategy.name}',
    baggageAvailableAfterDays: signals.baggageAvailableAfterDays,
  );
}

ClosureRule? _closureRuleFor(TimelineItem item) {
  final signals = item.closure;
  if (signals == null || signals.weeklyClosedWeekdays.isEmpty) return null;
  return ClosureRule(
    weeklyClosedWeekdays: signals.weeklyClosedWeekdays.toSet(),
  );
}

RepeatRule _repeatRuleFor(TimelineItem item) {
  final signals = item.repeat;
  if (signals == null) {
    return inferRepeatRule(
      title: item.title,
      category: item.kind?.name,
    );
  }
  if (signals.userExplicitSelection || signals.policy == 'userOverride') {
    return const RepeatRule.userSelected();
  }
  final maximum = signals.maximumConsecutiveDays ?? 2;
  if (signals.isRepeatableZone || signals.policy == 'repeatableZone') {
    return RepeatRule.zone(maximumConsecutiveDays: maximum);
  }
  final quota = signals.recommendedTotalMinutes;
  if (signals.policy == 'timeQuota' && quota != null && quota > 0) {
    return RepeatRule.quota(quota, maximumConsecutiveDays: maximum);
  }
  return const RepeatRule(policy: RepeatPolicy.hardZero);
}

bool _isHotelCheckIn(TimelineItem item) {
  if (item.kind != TimelineItemKind.hotel) return false;
  final value = item.title.toLowerCase();
  return value.contains('check-in') ||
      value.contains('check in') ||
      value.contains('checkin') ||
      value.contains('giriş') ||
      value.contains('giris');
}

T? _enumByName<T extends Enum>(List<T> values, String? raw) {
  if (raw == null) return null;
  for (final value in values) {
    if (value.name == raw.trim()) return value;
  }
  return null;
}
