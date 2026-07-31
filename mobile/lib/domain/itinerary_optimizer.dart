import 'dart:math';

import 'route_matrix.dart';

enum TimeOfDayPreference { morning, afternoon, evening }

class OptimizationActivity {
  const OptimizationActivity({
    required this.id,
    required this.name,
    required this.day,
    required this.location,
    required this.durationMinutes,
    this.minimumDurationMinutes = 1,
    this.openingTime,
    this.closingTime,
    this.fixedStartTime,
    this.fixedEndTime,
    this.isFixed = false,
    this.isLocked = false,
    this.hasReservation = false,
    this.priority = 0,
    this.estimatedQueueMinutes = 0,
    this.preferredTime,
    this.category,
  });

  final String id;
  final String name;
  final DateTime day;
  final TripLocation location;
  final int durationMinutes;
  final int minimumDurationMinutes;
  final DateTime? openingTime;
  final DateTime? closingTime;
  final DateTime? fixedStartTime;
  final DateTime? fixedEndTime;
  final bool isFixed;
  final bool isLocked;
  final bool hasReservation;
  final int priority;
  final int estimatedQueueMinutes;
  final TimeOfDayPreference? preferredTime;
  final String? category;

  bool get hasFixedSchedule =>
      isFixed || isLocked || fixedStartTime != null || fixedEndTime != null;

  String? get clusterId => location.clusterId ?? location.district;
}

class DayRouteConstraints {
  const DayRouteConstraints({
    required this.startLocation,
    required this.endLocation,
    required this.availableStartTime,
    required this.availableEndTime,
  });

  final TripLocation startLocation;
  final TripLocation endLocation;
  final DateTime availableStartTime;
  final DateTime availableEndTime;
}

class OptimizationWeights {
  const OptimizationWeights({
    required this.travel,
    required this.waiting,
    required this.transfer,
    required this.backtracking,
    required this.scheduleRisk,
    required this.walking,
    required this.clusterBreak,
    required this.complexity,
    required this.transportCost,
  });

  final double travel;
  final double waiting;
  final double transfer;
  final double backtracking;
  final double scheduleRisk;
  final double walking;
  final double clusterBreak;
  final double complexity;
  final double transportCost;

  factory OptimizationWeights.forProfile(RouteOptimizationProfile profile) =>
      switch (profile) {
        RouteOptimizationProfile.balanced => const OptimizationWeights(
            travel: 1,
            waiting: .7,
            transfer: 8,
            backtracking: 1.5,
            scheduleRisk: 2,
            walking: 1,
            clusterBreak: 1,
            complexity: 1,
            transportCost: .3,
          ),
        RouteOptimizationProfile.fastest => const OptimizationWeights(
            travel: 1.8,
            waiting: .8,
            transfer: 3,
            backtracking: 1,
            scheduleRisk: 2.5,
            walking: .35,
            clusterBreak: .5,
            complexity: .5,
            transportCost: .04,
          ),
        RouteOptimizationProfile.leastWalking => const OptimizationWeights(
            travel: .8,
            waiting: .7,
            transfer: 7,
            backtracking: 1.3,
            scheduleRisk: 2,
            walking: 4,
            clusterBreak: 1,
            complexity: 1,
            transportCost: .15,
          ),
        RouteOptimizationProfile.cheapest => const OptimizationWeights(
            travel: .65,
            waiting: .5,
            transfer: 6,
            backtracking: 1.2,
            scheduleRisk: 2,
            walking: .35,
            clusterBreak: .8,
            complexity: .8,
            transportCost: 2.5,
          ),
      };
}

class OptimizerConfig {
  const OptimizerConfig({
    this.beamWidth = 7,
    this.simpleTransitionBufferMinutes = 10,
    this.complexTransitionBufferMinutes = 15,
    this.fixedActivityBufferMinutes = 20,
    this.preferredFixedActivityBufferMinutes = 30,
    this.walkingTimeToleranceMinutes = 5,
    this.walkingFatigueThresholdMinutes = 90,
    this.clusterReentryPenalty = 20,
    this.localImprovementPasses = 3,
    this.allowActivityDropping = false,
  });

  final int beamWidth;
  final int simpleTransitionBufferMinutes;
  final int complexTransitionBufferMinutes;
  final int fixedActivityBufferMinutes;
  final int preferredFixedActivityBufferMinutes;
  final int walkingTimeToleranceMinutes;
  final int walkingFatigueThresholdMinutes;
  final double clusterReentryPenalty;
  final int localImprovementPasses;

  /// Kapalıyken (varsayılan) davranış değişmez: sabit-olmayan aktiviteler de
  /// dahil tüm istek listesi planlanamazsa `noFeasibleRoute` ile başarısız
  /// olur — mevcut viewer/planner akışı kullanıcının eklediği hiçbir
  /// aktiviteyi sessizce kaybetmemelidir.
  ///
  /// Açıkken, tam küme sığmadığında motor sabit-olmayan aktiviteleri teker
  /// teker (gerekirse birden fazla) düşürüp kalanını planlar;
  /// [OptimizationResult.droppedActivityIds] düşürülenleri raporlar. Bu,
  /// günü aşırı dolu bir aktivite listesiyle değerlendiren dış çağıranlar
  /// (ör. AI rota prompt köprüsü) için tasarlanmıştır.
  final bool allowActivityDropping;
}

class OptimizationRequest {
  OptimizationRequest({
    required List<OptimizationActivity> activities,
    required this.routeMatrix,
    required this.constraints,
    this.preferences = const RoutePreferences(),
    OptimizationWeights? weights,
  })  : activities = List.unmodifiable(activities),
        weights =
            weights ?? OptimizationWeights.forProfile(preferences.profile);

  final List<OptimizationActivity> activities;
  final RouteMatrix routeMatrix;
  final DayRouteConstraints constraints;
  final RoutePreferences preferences;
  final OptimizationWeights weights;
}

class RouteLeg {
  const RouteLeg({
    required this.fromLocationId,
    required this.toLocationId,
    required this.mode,
    required this.departureTime,
    required this.arrivalTime,
    required this.travelDurationMinutes,
    required this.walkingDurationMinutes,
    required this.waitingDurationMinutes,
    required this.transferCount,
    required this.estimatedCostYen,
    required this.bufferMinutes,
    required this.reliabilityScore,
    required this.isEstimated,
  });

  final String fromLocationId;
  final String toLocationId;
  final TransportMode mode;
  final DateTime departureTime;
  final DateTime arrivalTime;
  final int travelDurationMinutes;
  final int walkingDurationMinutes;
  final int waitingDurationMinutes;
  final int transferCount;
  final int estimatedCostYen;
  final int bufferMinutes;
  final double reliabilityScore;
  final bool isEstimated;
}

class ScheduledActivity {
  ScheduledActivity({
    required this.activity,
    required this.order,
    required this.startTime,
    required this.endTime,
    required this.inboundLeg,
    required this.optimizationReason,
    List<String> warnings = const [],
  }) : warnings = List.unmodifiable(warnings);

  final OptimizationActivity activity;
  final int order;
  final DateTime startTime;
  final DateTime endTime;
  final RouteLeg inboundLeg;
  final String optimizationReason;
  final List<String> warnings;

  String get activityId => activity.id;
  DateTime get day => activity.day;
  TripLocation get location => activity.location;
  TransportMode get transportMode => inboundLeg.mode;
  DateTime get departureTime => inboundLeg.departureTime;
  DateTime get arrivalTime => inboundLeg.arrivalTime;
  int get travelDurationMinutes => inboundLeg.travelDurationMinutes;
  int get walkingDurationMinutes => inboundLeg.walkingDurationMinutes;
  int get waitingDurationMinutes => inboundLeg.waitingDurationMinutes;
  int get transferCount => inboundLeg.transferCount;
  int get estimatedCostYen => inboundLeg.estimatedCostYen;
  int get bufferMinutes => inboundLeg.bufferMinutes;
  String? get routeCluster => activity.clusterId;
  bool get isFixed => activity.hasFixedSchedule;
}

enum FeasibilityStatus { feasible, infeasible }

class OptimizationMetrics {
  const OptimizationMetrics({
    required this.totalTravelMinutes,
    required this.totalWalkingMinutes,
    required this.totalWaitingMinutes,
    required this.totalTransferCount,
    required this.estimatedTransportCostYen,
    required this.backtrackingMinutes,
    required this.routeEfficiencyScore,
    required this.score,
    required this.evaluatedStateCount,
    required this.prunedStateCount,
    required this.beamWidth,
  });

  final int totalTravelMinutes;
  final int totalWalkingMinutes;
  final int totalWaitingMinutes;
  final int totalTransferCount;
  final int estimatedTransportCostYen;
  final double backtrackingMinutes;
  final double routeEfficiencyScore;
  final double score;
  final int evaluatedStateCount;
  final int prunedStateCount;
  final int beamWidth;
}

enum OptimizationFailureCode {
  invalidRequest,
  duplicateActivityId,
  fixedActivityMissingTime,
  fixedTimeConflict,
  routeDataMissing,
  noFeasibleRoute,
}

class OptimizationFailure {
  const OptimizationFailure({
    required this.code,
    required this.message,
    this.activityId,
    this.fromLocationId,
    this.toLocationId,
  });

  final OptimizationFailureCode code;
  final String message;
  final String? activityId;
  final String? fromLocationId;
  final String? toLocationId;
}

class OptimizationResult {
  OptimizationResult._({
    required this.feasibilityStatus,
    required List<ScheduledActivity> activities,
    required List<RouteLeg> legs,
    required List<String> warnings,
    required List<String> optimizationChanges,
    List<String> droppedActivityIds = const [],
    this.metrics,
    this.failure,
  })  : activities = List.unmodifiable(activities),
        legs = List.unmodifiable(legs),
        warnings = List.unmodifiable(warnings),
        optimizationChanges = List.unmodifiable(optimizationChanges),
        droppedActivityIds = List.unmodifiable(droppedActivityIds);

  factory OptimizationResult.success({
    required List<ScheduledActivity> activities,
    required List<RouteLeg> legs,
    required OptimizationMetrics metrics,
    required List<String> warnings,
    required List<String> optimizationChanges,
    List<String> droppedActivityIds = const [],
  }) =>
      OptimizationResult._(
        feasibilityStatus: FeasibilityStatus.feasible,
        activities: activities,
        legs: legs,
        metrics: metrics,
        warnings: warnings,
        optimizationChanges: optimizationChanges,
        droppedActivityIds: droppedActivityIds,
      );

  factory OptimizationResult.failure(OptimizationFailure failure) =>
      OptimizationResult._(
        feasibilityStatus: FeasibilityStatus.infeasible,
        activities: const [],
        legs: const [],
        warnings: const [],
        optimizationChanges: const [],
        failure: failure,
      );

  final FeasibilityStatus feasibilityStatus;
  final List<ScheduledActivity> activities;
  final List<RouteLeg> legs;
  final OptimizationMetrics? metrics;
  final List<String> warnings;
  final List<String> optimizationChanges;
  final OptimizationFailure? failure;

  /// `OptimizerConfig.allowActivityDropping` açıkken, tam aktivite kümesi
  /// sığmadığı için çıkarılan sabit-olmayan aktivite id'leri. Varsayılan
  /// (kapalı) modda her zaman boştur.
  final List<String> droppedActivityIds;

  bool get isSuccess => feasibilityStatus == FeasibilityStatus.feasible;
}

abstract interface class ItineraryOptimizer {
  Future<OptimizationResult> optimize(OptimizationRequest request);
}

class BeamSearchItineraryOptimizer implements ItineraryOptimizer {
  const BeamSearchItineraryOptimizer({
    this.config = const OptimizerConfig(),
  });

  final OptimizerConfig config;

  @override
  Future<OptimizationResult> optimize(OptimizationRequest request) async {
    final result = await _solve(request);
    if (result.isSuccess ||
        !config.allowActivityDropping ||
        result.failure?.code != OptimizationFailureCode.noFeasibleRoute) {
      return result;
    }
    return _solveWithDropping(request);
  }

  /// [config.allowActivityDropping] açıkken tam aktivite kümesi sığmazsa
  /// çağrılır. Sabit-olmayan aktiviteleri teker teker dener; tek çıkarma
  /// yeterli olmazsa en fazla süreye sahip (gün üzerinde en baskılı) olanı
  /// atıp tekrar dener. Sabit aktiviteler asla çıkarılmaz.
  ///
  /// `category == 'meal'` olan aktiviteler korunur: meal-olmayan bir
  /// aktivitenin çıkarılması yeterliyse veya günün geri kalanı yine de
  /// baskılıysa asıl atılacak aday olarak seçilir; yalnızca ortada başka
  /// düşürülebilir (sabit olmayan, meal olmayan) aktivite kalmadığında bir
  /// öğün düşürülür. Bu, gerçek bir gezginin önce gezi durağından fedakârlık
  /// edip öğününden vazgeçmemesi sezgisiyle uyumludur.
  Future<OptimizationResult> _solveWithDropping(
    OptimizationRequest original,
  ) async {
    var current = original.activities;
    final dropped = <String>[];

    while (true) {
      final droppable =
          current.where((activity) => !activity.hasFixedSchedule).toList();
      if (droppable.isEmpty) {
        return OptimizationResult.failure(
          const OptimizationFailure(
            code: OptimizationFailureCode.noFeasibleRoute,
            message: 'Sabit aktiviteler bile gün sınırı içinde planlanamadı.',
          ),
        );
      }
      final nonMealDroppable =
          droppable.where((activity) => activity.category != 'meal').toList();
      final mealDroppable =
          droppable.where((activity) => activity.category == 'meal').toList();

      OptimizationResult? bestSuccess;
      OptimizationActivity? bestDrop;
      for (final pool in [nonMealDroppable, mealDroppable]) {
        for (final candidate in pool) {
          final trialActivities =
              current.where((activity) => activity.id != candidate.id).toList();
          final trialResult = await _solve(_withActivities(
            original,
            trialActivities,
          ));
          if (!trialResult.isSuccess) continue;
          if (bestSuccess == null ||
              trialResult.metrics!.score < bestSuccess.metrics!.score) {
            bestSuccess = trialResult;
            bestDrop = candidate;
          }
        }
        // Meal-olmayan havuzda en az bir çözüm bulunduysa öğünlere hiç
        // bakılmadan durulur.
        if (bestSuccess != null) break;
      }

      if (bestSuccess != null && bestDrop != null) {
        dropped.add(bestDrop.id);
        return OptimizationResult.success(
          activities: bestSuccess.activities,
          legs: bestSuccess.legs,
          metrics: bestSuccess.metrics!,
          warnings: bestSuccess.warnings,
          optimizationChanges: bestSuccess.optimizationChanges,
          droppedActivityIds: dropped,
        );
      }

      // Tek çıkarma yeterli olmadı — meal-olmayanlar arasından en uzun
      // süreliyi (günü en çok baskılayanı) at; hiç meal-olmayan kalmadıysa
      // ancak o zaman bir öğüne dokun.
      final fallbackPool =
          nonMealDroppable.isNotEmpty ? nonMealDroppable : mealDroppable;
      final worst = [...fallbackPool]
        ..sort((a, b) => b.durationMinutes.compareTo(a.durationMinutes));
      dropped.add(worst.first.id);
      current =
          current.where((activity) => activity.id != worst.first.id).toList();
    }
  }

  OptimizationRequest _withActivities(
    OptimizationRequest original,
    List<OptimizationActivity> activities,
  ) =>
      OptimizationRequest(
        activities: activities,
        routeMatrix: original.routeMatrix,
        constraints: original.constraints,
        preferences: original.preferences,
        weights: original.weights,
      );

  Future<OptimizationResult> _solve(OptimizationRequest request) async {
    final validation = _validate(request);
    if (validation != null) return OptimizationResult.failure(validation);

    if (request.activities.isEmpty) {
      return _emptyResult(request);
    }

    var evaluatedStates = 0;
    var prunedStates = 0;
    var beam = [
      _RouteState.initial(
        currentTime: request.constraints.availableStartTime,
        currentLocation: request.constraints.startLocation,
      ),
    ];

    for (var depth = 0; depth < request.activities.length; depth++) {
      final expanded = <_RouteState>[];
      for (final state in beam) {
        final candidates = request.activities
            .where((activity) => !state.visitedIds.contains(activity.id))
            .toList()
          ..sort((a, b) => a.id.compareTo(b.id));
        final earliestFixed = _earliestFixed(candidates);

        for (final candidate in candidates) {
          if (candidate.hasFixedSchedule &&
              earliestFixed != null &&
              candidate.id != earliestFixed.id) {
            continue;
          }
          final options = _validOptions(
            request.routeMatrix,
            state.currentLocation.id,
            candidate.location.id,
          );
          for (final option in options) {
            evaluatedStates++;
            final next = _append(
              request,
              state,
              candidate,
              option,
              remainingAfter: candidates
                  .where((activity) => activity.id != candidate.id)
                  .toList(),
            );
            if (next == null) {
              prunedStates++;
            } else {
              expanded.add(next);
            }
          }
        }
      }

      if (expanded.isEmpty) {
        return OptimizationResult.failure(
          const OptimizationFailure(
            code: OptimizationFailureCode.noFeasibleRoute,
            message:
                'Aktiviteler sabit saatler ve gün sınırı içinde planlanamadı.',
          ),
        );
      }

      expanded.sort((a, b) {
        final scoreComparison = _rank(request, a).compareTo(_rank(request, b));
        if (scoreComparison != 0) return scoreComparison;
        return a.routeKey.compareTo(b.routeKey);
      });
      if (expanded.length > config.beamWidth) {
        prunedStates += expanded.length - config.beamWidth;
      }
      beam = expanded.take(config.beamWidth).toList();
    }

    final completed = <_RouteState>[];
    for (final state in beam) {
      final withReturn = _appendReturn(request, state);
      if (withReturn == null) {
        prunedStates++;
      } else {
        completed.add(withReturn);
      }
    }
    if (completed.isEmpty) {
      return OptimizationResult.failure(
        const OptimizationFailure(
          code: OptimizationFailureCode.noFeasibleRoute,
          message: 'Gün sonunda zorunlu bitiş noktasına ulaşılamıyor.',
        ),
      );
    }

    completed.sort((a, b) {
      final scoreComparison = a.score.compareTo(b.score);
      if (scoreComparison != 0) return scoreComparison;
      return a.routeKey.compareTo(b.routeKey);
    });
    var best = completed.first;
    best = _improveLocally(request, best);

    return _toResult(
      request,
      best,
      evaluatedStates: evaluatedStates,
      prunedStates: prunedStates,
    );
  }

  OptimizationFailure? _validate(OptimizationRequest request) {
    if (config.beamWidth <= 0 ||
        request.constraints.availableEndTime
                .compareTo(request.constraints.availableStartTime) <=
            0 ||
        request.preferences.maximumWalkingMinutes < 0) {
      return const OptimizationFailure(
        code: OptimizationFailureCode.invalidRequest,
        message: 'Optimizasyon yapılandırması geçersiz.',
      );
    }

    final ids = <String>{};
    for (final activity in request.activities) {
      if (!ids.add(activity.id)) {
        return OptimizationFailure(
          code: OptimizationFailureCode.duplicateActivityId,
          message: 'Aktivite kimliği benzersiz olmalıdır: ${activity.id}',
          activityId: activity.id,
        );
      }
      if (activity.durationMinutes <= 0 ||
          activity.minimumDurationMinutes <= 0 ||
          activity.durationMinutes < activity.minimumDurationMinutes ||
          activity.estimatedQueueMinutes < 0 ||
          !_sameDay(activity.day, request.constraints.availableStartTime)) {
        return OptimizationFailure(
          code: OptimizationFailureCode.invalidRequest,
          message: 'Aktivite süresi veya günü geçersiz: ${activity.id}',
          activityId: activity.id,
        );
      }
      if (activity.hasFixedSchedule && activity.fixedStartTime == null) {
        return OptimizationFailure(
          code: OptimizationFailureCode.fixedActivityMissingTime,
          message: 'Sabit aktivitenin başlangıç saati eksik: ${activity.id}',
          activityId: activity.id,
        );
      }
      if (activity.fixedStartTime != null &&
          !_sameDay(activity.fixedStartTime!, activity.day)) {
        return OptimizationFailure(
          code: OptimizationFailureCode.invalidRequest,
          message: 'Sabit aktivite farklı bir güne taşınamaz: ${activity.id}',
          activityId: activity.id,
        );
      }
      final fixedEnd = activity.fixedEndTime;
      if (fixedEnd != null &&
          (activity.fixedStartTime == null ||
              fixedEnd.compareTo(activity.fixedStartTime!) <= 0 ||
              fixedEnd.difference(activity.fixedStartTime!).inMinutes <
                  activity.minimumDurationMinutes)) {
        return OptimizationFailure(
          code: OptimizationFailureCode.fixedTimeConflict,
          message: 'Sabit aktivitenin zaman aralığı geçersiz: ${activity.id}',
          activityId: activity.id,
        );
      }
      if (activity.openingTime != null &&
          activity.closingTime != null &&
          activity.closingTime!.compareTo(activity.openingTime!) <= 0) {
        return OptimizationFailure(
          code: OptimizationFailureCode.invalidRequest,
          message: 'Açılış-kapanış aralığı geçersiz: ${activity.id}',
          activityId: activity.id,
        );
      }
    }
    return null;
  }

  OptimizationResult _emptyResult(OptimizationRequest request) {
    final options = _validOptions(
      request.routeMatrix,
      request.constraints.startLocation.id,
      request.constraints.endLocation.id,
    );
    if (options.isEmpty) {
      return OptimizationResult.failure(
        OptimizationFailure(
          code: OptimizationFailureCode.routeDataMissing,
          message: 'Başlangıç ve bitiş noktası arasında rota verisi yok.',
          fromLocationId: request.constraints.startLocation.id,
          toLocationId: request.constraints.endLocation.id,
        ),
      );
    }
    final option = _sortOptions(request, options).first;
    final arrival = request.constraints.availableStartTime
        .add(Duration(minutes: option.doorToDoorMinutes));
    if (arrival.compareTo(request.constraints.availableEndTime) > 0) {
      return OptimizationResult.failure(
        const OptimizationFailure(
          code: OptimizationFailureCode.noFeasibleRoute,
          message: 'Gün sonu hedefine ayrılan süre yeterli değil.',
        ),
      );
    }
    final leg = _leg(
      request.constraints.startLocation.id,
      request.constraints.endLocation.id,
      request.constraints.availableStartTime,
      option,
      waitingMinutes: 0,
      bufferMinutes: 0,
    );
    final score = _transportScore(request, option);
    return OptimizationResult.success(
      activities: const [],
      legs: [leg],
      metrics: OptimizationMetrics(
        totalTravelMinutes: option.doorToDoorMinutes,
        totalWalkingMinutes: option.walkingMinutes,
        totalWaitingMinutes: option.waitingMinutes,
        totalTransferCount: option.transferCount,
        estimatedTransportCostYen: option.estimatedCostYen,
        backtrackingMinutes: 0,
        routeEfficiencyScore: _efficiency(score, option.doorToDoorMinutes),
        score: score,
        evaluatedStateCount: 1,
        prunedStateCount: 0,
        beamWidth: config.beamWidth,
      ),
      warnings: option.isEstimated
          ? const ['Gün sonu rota verisi yaklaşık değerdir.']
          : const [],
      optimizationChanges: const [],
    );
  }

  OptimizationActivity? _earliestFixed(
    List<OptimizationActivity> activities,
  ) {
    final fixed = activities.where((activity) => activity.hasFixedSchedule);
    if (fixed.isEmpty) return null;
    return fixed.reduce((a, b) {
      final comparison = a.fixedStartTime!.compareTo(b.fixedStartTime!);
      if (comparison != 0) return comparison < 0 ? a : b;
      return a.id.compareTo(b.id) <= 0 ? a : b;
    });
  }

  List<TransportOption> _validOptions(
    RouteMatrix matrix,
    String from,
    String to,
  ) =>
      matrix.options(from, to).where((option) => option.isValid).toList();

  _RouteState? _append(
    OptimizationRequest request,
    _RouteState state,
    OptimizationActivity activity,
    TransportOption option, {
    required List<OptimizationActivity> remainingAfter,
  }) {
    final departure = state.currentTime;
    final arrival = departure.add(Duration(minutes: option.doorToDoorMinutes));
    final buffer = _bufferFor(activity, option);
    var start = arrival.add(Duration(minutes: buffer));

    if (activity.hasFixedSchedule) {
      final fixedStart = activity.fixedStartTime!;
      if (start.compareTo(fixedStart) > 0) return null;
      start = fixedStart;
    } else if (activity.openingTime != null &&
        start.compareTo(activity.openingTime!) < 0) {
      start = activity.openingTime!;
    }

    final end = activity.fixedEndTime ??
        start.add(Duration(
          minutes: activity.durationMinutes + activity.estimatedQueueMinutes,
        ));
    if (end.compareTo(start) <= 0 ||
        end.difference(start).inMinutes < activity.minimumDurationMinutes ||
        start.compareTo(request.constraints.availableStartTime) < 0 ||
        end.compareTo(request.constraints.availableEndTime) > 0 ||
        (activity.closingTime != null &&
            end.compareTo(activity.closingTime!) > 0)) {
      return null;
    }

    final totalWalking = state.totalWalking + option.walkingMinutes;
    if (totalWalking > request.preferences.maximumWalkingMinutes) return null;

    final nextFixed = _earliestFixed(remainingAfter);
    if (nextFixed != null &&
        !_canReachFixed(request, activity.location, end, nextFixed)) {
      return null;
    }

    final idleWaiting = max(0, start.difference(arrival).inMinutes - buffer);
    final scheduleRisk = _scheduleRisk(activity, arrival, buffer);
    final backtracking = _backtrackingPenalty(
      state,
      activity,
      option,
    );
    final clusterBreak = _clusterBreakPenalty(state, activity);
    final fatigue = max(
      0,
      totalWalking - config.walkingFatigueThresholdMinutes,
    ).toDouble();
    final complexity =
        option.complexityPenalty + max(0, option.transferCount - 1) * 3;
    final availableOptions = _validOptions(
      request.routeMatrix,
      state.currentLocation.id,
      activity.location.id,
    );
    final increment = _transportScore(request, option) +
        _modeChoiceAdjustment(request, option, availableOptions) +
        idleWaiting * request.weights.waiting +
        backtracking * request.weights.backtracking +
        scheduleRisk * request.weights.scheduleRisk +
        (fatigue - state.fatigue) * request.weights.walking +
        clusterBreak * request.weights.clusterBreak +
        complexity * request.weights.complexity +
        _preferredTimePenalty(activity, start);

    final leg = _leg(
      state.currentLocation.id,
      activity.location.id,
      departure,
      option,
      waitingMinutes: idleWaiting + option.waitingMinutes,
      bufferMinutes: buffer,
    );
    final warningList = <String>[
      if (option.isEstimated)
        '${activity.name} geçişinde yaklaşık rota verisi kullanıldı.',
      if (option.reliabilityScore < .75)
        '${activity.name} geçişinin güvenilirliği düşük.',
    ];
    final closedClusters = {...state.closedClusters};
    final previousCluster = state.currentCluster;
    final nextCluster = activity.clusterId;
    if (previousCluster != null &&
        nextCluster != null &&
        previousCluster != nextCluster) {
      closedClusters.add(previousCluster);
    }

    final scheduled = ScheduledActivity(
      activity: activity,
      order: state.scheduled.length + 1,
      startTime: start,
      endTime: end,
      inboundLeg: leg,
      optimizationReason: _reason(state, activity, option, clusterBreak),
      warnings: warningList,
    );
    return state.copyWith(
      scheduled: [...state.scheduled, scheduled],
      visitedIds: {...state.visitedIds, activity.id},
      currentTime: end,
      currentLocation: activity.location,
      totalTravel: state.totalTravel + option.doorToDoorMinutes,
      totalWalking: totalWalking,
      totalWaiting: state.totalWaiting + idleWaiting + option.waitingMinutes,
      totalTransfers: state.totalTransfers + option.transferCount,
      totalCost: state.totalCost + option.estimatedCostYen,
      backtracking: state.backtracking + backtracking,
      clusterBreak: state.clusterBreak + clusterBreak,
      scheduleRisk: state.scheduleRisk + scheduleRisk,
      fatigue: fatigue,
      complexity: state.complexity + complexity,
      score: state.score + increment,
      closedClusters: closedClusters,
      currentCluster: nextCluster,
      previousLocation: state.currentLocation,
      previousOption: option,
      warnings: [...state.warnings, ...warningList],
    );
  }

  bool _canReachFixed(
    OptimizationRequest request,
    TripLocation from,
    DateTime departure,
    OptimizationActivity fixed,
  ) {
    final options =
        _validOptions(request.routeMatrix, from.id, fixed.location.id);
    return options.any((option) {
      final buffer = _bufferFor(fixed, option);
      final arrival =
          departure.add(Duration(minutes: option.doorToDoorMinutes + buffer));
      return arrival.compareTo(fixed.fixedStartTime!) <= 0;
    });
  }

  int _bufferFor(
    OptimizationActivity activity,
    TransportOption option,
  ) {
    if (activity.hasFixedSchedule || activity.hasReservation) {
      return config.fixedActivityBufferMinutes;
    }
    if (option.transferCount > 0 ||
        option.mode == TransportMode.shinkansen ||
        option.mode == TransportMode.regionalTrain ||
        option.complexityPenalty > 0) {
      return config.complexTransitionBufferMinutes;
    }
    return config.simpleTransitionBufferMinutes;
  }

  double _transportScore(
    OptimizationRequest request,
    TransportOption option,
  ) {
    final weights = request.weights;
    final perPersonCost =
        option.mode == TransportMode.taxi && request.preferences.partySize > 1
            ? option.estimatedCostYen / request.preferences.partySize
            : option.estimatedCostYen.toDouble();
    var score = option.doorToDoorMinutes * weights.travel +
        option.waitingMinutes * weights.waiting +
        option.transferCount * weights.transfer +
        option.walkingMinutes * weights.walking +
        (perPersonCost / 100) * weights.transportCost;
    if (option.mode == TransportMode.taxi) {
      score += switch (request.preferences.profile) {
        RouteOptimizationProfile.fastest => 0,
        RouteOptimizationProfile.leastWalking => 3,
        RouteOptimizationProfile.balanced => 12,
        RouteOptimizationProfile.cheapest => 30,
      };
    }
    if (option.reliabilityScore < .9) {
      score += (1 - option.reliabilityScore) * 20 * weights.scheduleRisk;
    }
    return score;
  }

  double _modeChoiceAdjustment(
    OptimizationRequest request,
    TransportOption option,
    List<TransportOption> alternatives,
  ) {
    if (option.mode != TransportMode.walking ||
        request.preferences.profile == RouteOptimizationProfile.leastWalking ||
        request.preferences.profile == RouteOptimizationProfile.fastest) {
      return 0;
    }
    final nonWalkingMinutes = alternatives
        .where(
          (candidate) =>
              candidate.mode != TransportMode.walking &&
              candidate.mode != TransportMode.taxi,
        )
        .map((candidate) => candidate.doorToDoorMinutes);
    if (nonWalkingMinutes.isEmpty) return 0;
    final fastest = nonWalkingMinutes.reduce(min);
    if (option.doorToDoorMinutes - fastest >
        config.walkingTimeToleranceMinutes) {
      return 0;
    }
    return request.preferences.profile == RouteOptimizationProfile.cheapest
        ? -35
        : -25;
  }

  double _scheduleRisk(
    OptimizationActivity activity,
    DateTime arrival,
    int requiredBuffer,
  ) {
    if (!activity.hasFixedSchedule) {
      if (activity.closingTime == null) return 0;
      final remaining = activity.closingTime!.difference(arrival).inMinutes;
      return max(0, 30 - remaining).toDouble();
    }
    final actualBuffer = activity.fixedStartTime!.difference(arrival).inMinutes;
    if (actualBuffer < requiredBuffer) return double.infinity;
    return max(
      0,
      config.preferredFixedActivityBufferMinutes - actualBuffer,
    ).toDouble();
  }

  double _preferredTimePenalty(
    OptimizationActivity activity,
    DateTime start,
  ) {
    final preferred = activity.preferredTime;
    if (preferred == null) return 0;
    final isPreferred = switch (preferred) {
      TimeOfDayPreference.morning => start.hour < 12,
      TimeOfDayPreference.afternoon => start.hour >= 12 && start.hour < 17,
      TimeOfDayPreference.evening => start.hour >= 17,
    };
    return isPreferred ? 0 : 12;
  }

  double _clusterBreakPenalty(
    _RouteState state,
    OptimizationActivity activity,
  ) {
    final cluster = activity.clusterId;
    if (cluster == null || !state.closedClusters.contains(cluster)) return 0;
    return config.clusterReentryPenalty;
  }

  double _backtrackingPenalty(
    _RouteState state,
    OptimizationActivity next,
    TransportOption option,
  ) {
    var penalty = 0.0;
    final previous = state.previousLocation;
    if (previous != null) {
      final ax = state.currentLocation.longitude - previous.longitude;
      final ay = state.currentLocation.latitude - previous.latitude;
      final bx = next.location.longitude - state.currentLocation.longitude;
      final by = next.location.latitude - state.currentLocation.latitude;
      final aLength = sqrt(ax * ax + ay * ay);
      final bLength = sqrt(bx * bx + by * by);
      if (aLength > 0 && bLength > 0) {
        final cosine = (ax * bx + ay * by) / (aLength * bLength);
        if (cosine < -.25) {
          penalty += option.doorToDoorMinutes * -cosine;
        }
      }
    }
    final previousOption = state.previousOption;
    if (previousOption?.lineId != null &&
        previousOption!.lineId == option.lineId &&
        previousOption.directionId != null &&
        option.directionId != null &&
        previousOption.directionId != option.directionId) {
      penalty += option.doorToDoorMinutes.toDouble();
    }
    if (next.hasFixedSchedule) {
      penalty *= .35;
    }
    return penalty;
  }

  String _reason(
    _RouteState state,
    OptimizationActivity activity,
    TransportOption option,
    double clusterBreak,
  ) {
    if (activity.hasFixedSchedule) {
      return 'Sabit saat korunarak çevresindeki aktiviteler planlandı.';
    }
    if (state.currentCluster != null &&
        state.currentCluster == activity.clusterId) {
      return '${activity.name} aynı coğrafi kümede olduğu için arka arkaya yerleştirildi.';
    }
    if (option.mode == TransportMode.walking) {
      return 'Kapıdan kapıya süre ve rota sadeliği nedeniyle yürüyüş seçildi.';
    }
    if (clusterBreak > 0) {
      return 'Zaman kısıtları nedeniyle daha önce ziyaret edilen bölgeye dönüldü.';
    }
    return 'Gerçek kapıdan kapıya süre ve günün genel akışına göre yerleştirildi.';
  }

  double _rank(OptimizationRequest request, _RouteState state) {
    if (state.visitedIds.length == request.activities.length) {
      return state.score;
    }
    final remaining = request.activities
        .where((activity) => !state.visitedIds.contains(activity.id))
        .toList();
    var bestNext = double.infinity;
    for (final activity in remaining) {
      final options = _validOptions(
        request.routeMatrix,
        state.currentLocation.id,
        activity.location.id,
      );
      if (options.isEmpty) continue;
      final optionScore =
          options.map((option) => _transportScore(request, option)).reduce(min);
      if (optionScore < bestNext) bestNext = optionScore;
    }
    var returnEstimate = 0.0;
    final returnOptions = _validOptions(
      request.routeMatrix,
      state.currentLocation.id,
      request.constraints.endLocation.id,
    );
    if (returnOptions.isNotEmpty) {
      returnEstimate = returnOptions
          .map((option) => _transportScore(request, option))
          .reduce(min);
    }
    return state.score +
        (bestNext.isFinite ? bestNext : 100000) +
        returnEstimate * .35;
  }

  List<TransportOption> _sortOptions(
    OptimizationRequest request,
    List<TransportOption> options,
  ) {
    final sorted = [...options]..sort((a, b) {
        var aScore = _transportScore(request, a);
        var bScore = _transportScore(request, b);
        final fastestTransit = options
            .where((option) => option.mode != TransportMode.walking)
            .map((option) => option.doorToDoorMinutes)
            .fold<int?>(
                null, (best, value) => best == null ? value : min(best, value));
        if (fastestTransit != null &&
            a.mode == TransportMode.walking &&
            a.doorToDoorMinutes - fastestTransit <=
                config.walkingTimeToleranceMinutes &&
            request.preferences.profile !=
                RouteOptimizationProfile.leastWalking) {
          aScore -= 8;
        }
        if (fastestTransit != null &&
            b.mode == TransportMode.walking &&
            b.doorToDoorMinutes - fastestTransit <=
                config.walkingTimeToleranceMinutes &&
            request.preferences.profile !=
                RouteOptimizationProfile.leastWalking) {
          bScore -= 8;
        }
        final comparison = aScore.compareTo(bScore);
        if (comparison != 0) return comparison;
        return a.mode.index.compareTo(b.mode.index);
      });
    return sorted;
  }

  _RouteState? _appendReturn(
    OptimizationRequest request,
    _RouteState state,
  ) {
    final options = _validOptions(
      request.routeMatrix,
      state.currentLocation.id,
      request.constraints.endLocation.id,
    );
    if (options.isEmpty) return null;
    for (final option in _sortOptions(request, options)) {
      if (state.totalWalking + option.walkingMinutes >
          request.preferences.maximumWalkingMinutes) {
        continue;
      }
      final arrival =
          state.currentTime.add(Duration(minutes: option.doorToDoorMinutes));
      if (arrival.compareTo(request.constraints.availableEndTime) > 0) {
        continue;
      }
      final leg = _leg(
        state.currentLocation.id,
        request.constraints.endLocation.id,
        state.currentTime,
        option,
        waitingMinutes: option.waitingMinutes,
        bufferMinutes: 0,
      );
      return state.copyWith(
        returnLeg: leg,
        totalTravel: state.totalTravel + option.doorToDoorMinutes,
        totalWalking: state.totalWalking + option.walkingMinutes,
        totalWaiting: state.totalWaiting + option.waitingMinutes,
        totalTransfers: state.totalTransfers + option.transferCount,
        totalCost: state.totalCost + option.estimatedCostYen,
        score: state.score + _transportScore(request, option),
        warnings: [
          ...state.warnings,
          if (option.isEstimated) 'Gün sonu dönüş rota verisi yaklaşıktır.',
        ],
      );
    }
    return null;
  }

  _RouteState _improveLocally(
    OptimizationRequest request,
    _RouteState initial,
  ) {
    var best = initial;
    for (var pass = 0; pass < config.localImprovementPasses; pass++) {
      _RouteState? improvement;
      final order = best.scheduled.map((item) => item.activity).toList();
      final candidates = <List<OptimizationActivity>>[];

      for (var i = 0; i < order.length; i++) {
        if (order[i].hasFixedSchedule) continue;
        for (var j = i + 1; j < order.length; j++) {
          if (order[j].hasFixedSchedule) continue;
          final swapped = [...order];
          final temporary = swapped[i];
          swapped[i] = swapped[j];
          swapped[j] = temporary;
          candidates.add(swapped);
        }
      }

      // 2-opt: iki esnek durak arasındaki parçayı ters çevir. Swap/move tek
      // başına bazı cluster sıralarını bulamıyor; bu küçük hamle özellikle
      // şehir içi “gidip geri dönme” rotalarını düzeltir.
      for (var i = 0; i < order.length - 2; i++) {
        if (order[i].hasFixedSchedule) continue;
        for (var j = i + 2; j < order.length; j++) {
          if (order[j].hasFixedSchedule) continue;
          final reversed = [
            ...order.sublist(0, i),
            ...order.sublist(i, j + 1).reversed,
            ...order.sublist(j + 1),
          ];
          candidates.add(reversed);
        }
      }
      for (var from = 0; from < order.length; from++) {
        if (order[from].hasFixedSchedule) continue;
        for (var to = 0; to < order.length; to++) {
          if (from == to) continue;
          final moved = [...order];
          final activity = moved.removeAt(from);
          moved.insert(to, activity);
          candidates.add(moved);
        }
      }

      for (final candidate in candidates) {
        final simulated = _simulateOrder(request, candidate);
        if (simulated == null || simulated.score >= best.score - .000001) {
          continue;
        }
        if (improvement == null ||
            simulated.score < improvement.score - .000001 ||
            (simulated.score == improvement.score &&
                simulated.routeKey.compareTo(improvement.routeKey) < 0)) {
          improvement = simulated;
        }
      }
      if (improvement == null) break;
      best = improvement;
    }
    return best;
  }

  _RouteState? _simulateOrder(
    OptimizationRequest request,
    List<OptimizationActivity> order,
  ) {
    var state = _RouteState.initial(
      currentTime: request.constraints.availableStartTime,
      currentLocation: request.constraints.startLocation,
    );
    for (var index = 0; index < order.length; index++) {
      final activity = order[index];
      final options = _sortOptions(
        request,
        _validOptions(
          request.routeMatrix,
          state.currentLocation.id,
          activity.location.id,
        ),
      );
      _RouteState? bestOption;
      for (final option in options) {
        final appended = _append(
          request,
          state,
          activity,
          option,
          remainingAfter: order.sublist(index + 1),
        );
        if (appended == null) continue;
        if (bestOption == null || appended.score < bestOption.score - .000001) {
          bestOption = appended;
        }
      }
      if (bestOption == null) return null;
      state = bestOption;
    }
    return _appendReturn(request, state);
  }

  OptimizationResult _toResult(
    OptimizationRequest request,
    _RouteState state, {
    required int evaluatedStates,
    required int prunedStates,
  }) {
    final legs = [
      ...state.scheduled.map((item) => item.inboundLeg),
      if (state.returnLeg != null) state.returnLeg!,
    ];
    final routeChanges = <String>[];
    for (var i = 0; i < state.scheduled.length; i++) {
      final originalIndex = request.activities
          .indexWhere((a) => a.id == state.scheduled[i].activityId);
      if (originalIndex != i) {
        routeChanges.add(
          '${state.scheduled[i].activity.name} ${originalIndex + 1}. sıradan ${i + 1}. sıraya taşındı.',
        );
      }
    }
    return OptimizationResult.success(
      activities: state.scheduled,
      legs: legs,
      metrics: OptimizationMetrics(
        totalTravelMinutes: state.totalTravel,
        totalWalkingMinutes: state.totalWalking,
        totalWaitingMinutes: state.totalWaiting,
        totalTransferCount: state.totalTransfers,
        estimatedTransportCostYen: state.totalCost,
        backtrackingMinutes: state.backtracking,
        routeEfficiencyScore: _efficiency(state.score, state.totalTravel),
        score: state.score,
        evaluatedStateCount: evaluatedStates,
        prunedStateCount: prunedStates,
        beamWidth: config.beamWidth,
      ),
      warnings: state.warnings.toSet().toList(),
      optimizationChanges: routeChanges,
    );
  }

  RouteLeg _leg(
    String from,
    String to,
    DateTime departure,
    TransportOption option, {
    required int waitingMinutes,
    required int bufferMinutes,
  }) =>
      RouteLeg(
        fromLocationId: from,
        toLocationId: to,
        mode: option.mode,
        departureTime: departure,
        arrivalTime: departure.add(Duration(minutes: option.doorToDoorMinutes)),
        travelDurationMinutes: option.doorToDoorMinutes,
        walkingDurationMinutes: option.walkingMinutes,
        waitingDurationMinutes: waitingMinutes,
        transferCount: option.transferCount,
        estimatedCostYen: option.estimatedCostYen,
        bufferMinutes: bufferMinutes,
        reliabilityScore: option.reliabilityScore,
        isEstimated: option.isEstimated,
      );

  double _efficiency(double score, int travelMinutes) {
    if (!score.isFinite) return 0;
    return (100 / (1 + max(0, score - travelMinutes) / 100))
        .clamp(0, 100)
        .toDouble();
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _RouteState {
  const _RouteState({
    required this.scheduled,
    required this.visitedIds,
    required this.currentTime,
    required this.currentLocation,
    required this.totalTravel,
    required this.totalWalking,
    required this.totalWaiting,
    required this.totalTransfers,
    required this.totalCost,
    required this.backtracking,
    required this.clusterBreak,
    required this.scheduleRisk,
    required this.fatigue,
    required this.complexity,
    required this.score,
    required this.closedClusters,
    required this.currentCluster,
    required this.previousLocation,
    required this.previousOption,
    required this.warnings,
    this.returnLeg,
  });

  factory _RouteState.initial({
    required DateTime currentTime,
    required TripLocation currentLocation,
  }) =>
      _RouteState(
        scheduled: const [],
        visitedIds: const {},
        currentTime: currentTime,
        currentLocation: currentLocation,
        totalTravel: 0,
        totalWalking: 0,
        totalWaiting: 0,
        totalTransfers: 0,
        totalCost: 0,
        backtracking: 0,
        clusterBreak: 0,
        scheduleRisk: 0,
        fatigue: 0,
        complexity: 0,
        score: 0,
        closedClusters: const {},
        currentCluster: currentLocation.clusterId ?? currentLocation.district,
        previousLocation: null,
        previousOption: null,
        warnings: const [],
      );

  final List<ScheduledActivity> scheduled;
  final Set<String> visitedIds;
  final DateTime currentTime;
  final TripLocation currentLocation;
  final int totalTravel;
  final int totalWalking;
  final int totalWaiting;
  final int totalTransfers;
  final int totalCost;
  final double backtracking;
  final double clusterBreak;
  final double scheduleRisk;
  final double fatigue;
  final double complexity;
  final double score;
  final Set<String> closedClusters;
  final String? currentCluster;
  final TripLocation? previousLocation;
  final TransportOption? previousOption;
  final List<String> warnings;
  final RouteLeg? returnLeg;

  String get routeKey =>
      scheduled.map((item) => item.activityId).join('\u0000');

  _RouteState copyWith({
    List<ScheduledActivity>? scheduled,
    Set<String>? visitedIds,
    DateTime? currentTime,
    TripLocation? currentLocation,
    int? totalTravel,
    int? totalWalking,
    int? totalWaiting,
    int? totalTransfers,
    int? totalCost,
    double? backtracking,
    double? clusterBreak,
    double? scheduleRisk,
    double? fatigue,
    double? complexity,
    double? score,
    Set<String>? closedClusters,
    String? currentCluster,
    TripLocation? previousLocation,
    TransportOption? previousOption,
    List<String>? warnings,
    RouteLeg? returnLeg,
  }) =>
      _RouteState(
        scheduled: scheduled ?? this.scheduled,
        visitedIds: visitedIds ?? this.visitedIds,
        currentTime: currentTime ?? this.currentTime,
        currentLocation: currentLocation ?? this.currentLocation,
        totalTravel: totalTravel ?? this.totalTravel,
        totalWalking: totalWalking ?? this.totalWalking,
        totalWaiting: totalWaiting ?? this.totalWaiting,
        totalTransfers: totalTransfers ?? this.totalTransfers,
        totalCost: totalCost ?? this.totalCost,
        backtracking: backtracking ?? this.backtracking,
        clusterBreak: clusterBreak ?? this.clusterBreak,
        scheduleRisk: scheduleRisk ?? this.scheduleRisk,
        fatigue: fatigue ?? this.fatigue,
        complexity: complexity ?? this.complexity,
        score: score ?? this.score,
        closedClusters: closedClusters ?? this.closedClusters,
        currentCluster: currentCluster ?? this.currentCluster,
        previousLocation: previousLocation ?? this.previousLocation,
        previousOption: previousOption ?? this.previousOption,
        warnings: warnings ?? this.warnings,
        returnLeg: returnLeg ?? this.returnLeg,
      );
}
