import 'dart:math';

import 'hard_constraint_checker.dart';
import 'japan_calendar.dart';
import 'japan_transit_realism.dart';
import 'route_field_context.dart';
import 'route_matrix.dart';

enum TimeOfDayPreference { morning, afternoon, evening }

enum ActivityPriority { optional, normal, preferred, mustDo }

enum DropReason {
  noRoute,
  openingWindowConflict,
  dayCapacity,
  walkingLimit,
  fixedActivityConflict,
  duplicate,
  userOptional,
}

class DroppedActivity {
  DroppedActivity({
    required this.activityId,
    required this.name,
    required this.priority,
    required this.reason,
    List<int> attemptedDayIndexes = const [],
    this.conflictingActivityId,
  }) : attemptedDayIndexes = List.unmodifiable(attemptedDayIndexes);

  final String activityId;
  final String name;
  final ActivityPriority priority;
  final DropReason reason;
  final List<int> attemptedDayIndexes;
  final String? conflictingActivityId;
}

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
    this.priority = ActivityPriority.normal,
    this.estimatedQueueMinutes = 0,
    this.requiredArrivalBufferMinutes = 0,
    this.preferredTime,
    this.category,
    this.cityId,
    this.closureRule,
    this.requiresHotelCheckIn = false,
    this.repeatRule = const RepeatRule(),
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
  final ActivityPriority priority;
  final int estimatedQueueMinutes;
  final int requiredArrivalBufferMinutes;
  final TimeOfDayPreference? preferredTime;
  final String? category;

  /// v3 — sezonluk kalabalık penceresi ve şehir kapsamlı kimlik için.
  final String? cityId;

  /// v3 — teishukubi (定休日) kapanış sözleşmesi. `null` ise kapanış kuralı
  /// yoktur (park, cadde, kavşak).
  final ClosureRule? closureRule;

  /// v3 — bu satır otele giriş anlamına geliyorsa check-in penceresi kesin
  /// kısıt olarak uygulanır.
  final bool requiresHotelCheckIn;

  /// v3 — ardışık gün tekrar politikası. Gün içi optimizer kararını
  /// etkilemez; plan seviyesindeki deduplication'a taşınır.
  final RepeatRule repeatRule;

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
            waiting: 3,
            transfer: 8,
            backtracking: 1.5,
            scheduleRisk: 2,
            walking: 1,
            clusterBreak: 1,
            complexity: 1,
            transportCost: .3,
          ),
        RouteOptimizationProfile.fastest => const OptimizationWeights(
            travel: 10,
            waiting: .1,
            transfer: .1,
            backtracking: .1,
            scheduleRisk: .5,
            walking: 0,
            clusterBreak: .1,
            complexity: .1,
            transportCost: 0,
          ),
        RouteOptimizationProfile.leastWalking => const OptimizationWeights(
            travel: .8,
            waiting: 3,
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
            waiting: 3,
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
    this.beamWidth = 6,
    this.simpleTransitionBufferMinutes = 10,
    this.complexTransitionBufferMinutes = 15,
    this.fixedActivityBufferMinutes = 20,
    this.preferredFixedActivityBufferMinutes = 30,
    this.walkingTimeToleranceMinutes = 5,
    this.walkingFatigueThresholdMinutes = 90,
    this.clusterReentryPenalty = 120,
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
    this.field,
  })  : activities = List.unmodifiable(activities),
        weights =
            weights ?? OptimizationWeights.forProfile(preferences.profile);

  final List<OptimizationActivity> activities;
  final RouteMatrix routeMatrix;
  final DayRouteConstraints constraints;
  final RoutePreferences preferences;
  final OptimizationWeights weights;

  /// v3 saha bağlamı. `null` iken motor v2 davranışını birebir korur —
  /// mevcut üretim kalite kapıları tek seferde değişmez.
  final FieldRealityContext? field;
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
    this.rideMinutes = 0,
    this.accessMinutes = 0,
    this.transitWaitMinutes = 0,
    this.scheduleIdleMinutes = 0,
    this.costPerPersonYen = 0,
    this.partyTotalCostYen = 0,
    this.vehicleCount = 0,
    this.fareBasis = FareBasis.perPerson,
    this.lineId,
    this.directionId,
    this.complexityPenalty = 0,
    this.providerId,
    this.stationNavigationBufferMinutes = 0,
    this.trafficRiskMultiplier = 1,
    this.effectiveShinkansenService,
    this.transitDisclaimers = const {},
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
  final int rideMinutes;
  final int accessMinutes;
  final int transitWaitMinutes;
  final int scheduleIdleMinutes;
  final int costPerPersonYen;
  final int partyTotalCostYen;
  final int vehicleCount;
  final FareBasis fareBasis;
  final String? lineId;
  final String? directionId;
  final double complexityPenalty;
  final String? providerId;

  /// v3 — dev ("labyrinth") istasyon navigasyon tamponu.
  final int stationNavigationBufferMinutes;

  /// v3 — otobüs/taksi için uygulanan trafik çarpanı (1.0 = uygulanmadı).
  final double trafficRiskMultiplier;

  /// v3 — pass kısıtından sonra fiilen kullanılan Shinkansen servisi.
  final ShinkansenService? effectiveShinkansenService;

  /// v3 — UI'a taşınacak uyarı anahtarları.
  final Set<TransitDisclaimer> transitDisclaimers;

  bool get hasTrafficRiskDisclaimer =>
      transitDisclaimers.contains(TransitDisclaimer.trafficRisk);
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
    this.totalTransitWaitMinutes = 0,
    this.scheduleIdleMinutes = 0,
    this.partyTotalTransportCostYen = 0,
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
  final int totalTransitWaitMinutes;
  final int scheduleIdleMinutes;
  final int partyTotalTransportCostYen;

  double get objectiveScore => score;
}

class OptimizationDelta {
  const OptimizationDelta({
    required this.travelDeltaMinutes,
    required this.walkingDeltaMinutes,
    required this.idleDeltaMinutes,
    required this.transferDelta,
    required this.partyCostDeltaYen,
    required this.backtrackingDelta,
    required this.objectiveScoreDelta,
    required this.objectiveImprovementPct,
  });

  final int travelDeltaMinutes;
  final int walkingDeltaMinutes;
  final int idleDeltaMinutes;
  final int transferDelta;
  final int partyCostDeltaYen;
  final double backtrackingDelta;
  final double objectiveScoreDelta;
  final double objectiveImprovementPct;
}

enum OptimizationFailureCode {
  invalidRequest,
  duplicateActivityId,
  fixedActivityMissingTime,
  fixedTimeConflict,
  routeDataMissing,
  noFeasibleRoute,
  protectedActivityInfeasible,
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
    List<DroppedActivity> droppedActivities = const [],
    this.delta,
    this.metrics,
    this.failure,
  })  : activities = List.unmodifiable(activities),
        legs = List.unmodifiable(legs),
        warnings = List.unmodifiable(warnings),
        optimizationChanges = List.unmodifiable(optimizationChanges),
        droppedActivities = List.unmodifiable(droppedActivities),
        droppedActivityIds = List.unmodifiable(
          droppedActivities.isEmpty
              ? droppedActivityIds
              : droppedActivities.map((activity) => activity.activityId),
        );

  factory OptimizationResult.success({
    required List<ScheduledActivity> activities,
    required List<RouteLeg> legs,
    required OptimizationMetrics metrics,
    required List<String> warnings,
    required List<String> optimizationChanges,
    List<String> droppedActivityIds = const [],
    List<DroppedActivity> droppedActivities = const [],
    OptimizationDelta? delta,
  }) =>
      OptimizationResult._(
        feasibilityStatus: FeasibilityStatus.feasible,
        activities: activities,
        legs: legs,
        metrics: metrics,
        warnings: warnings,
        optimizationChanges: optimizationChanges,
        droppedActivityIds: droppedActivityIds,
        droppedActivities: droppedActivities,
        delta: delta,
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
  final OptimizationDelta? delta;

  /// `OptimizerConfig.allowActivityDropping` açıkken, tam aktivite kümesi
  /// sığmadığı için çıkarılan sabit-olmayan aktivite id'leri. Varsayılan
  /// (kapalı) modda her zaman boştur.
  final List<String> droppedActivityIds;
  final List<DroppedActivity> droppedActivities;

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
  /// çağrılır. `mustDo` ve sabit aktiviteler asla çıkarılmaz. Diğer adaylar
  /// lexicographic olarak optional → normal → preferred sırasıyla denenir;
  /// aynı öncelikte uzun süreli aday önce kapasite açar, ID deterministik
  /// tie-break sağlar.
  Future<OptimizationResult> _solveWithDropping(
    OptimizationRequest original,
  ) async {
    var current = original.activities;
    final dropped = <DroppedActivity>[];

    while (true) {
      final droppable = current
          .where((activity) =>
              !activity.hasFixedSchedule &&
              activity.priority != ActivityPriority.mustDo)
          .toList()
        ..sort(_compareDropCandidates);
      if (droppable.isEmpty) {
        return OptimizationResult.failure(
          const OptimizationFailure(
            code: OptimizationFailureCode.protectedActivityInfeasible,
            message:
                'Must-do veya sabit aktiviteler gün sınırı içinde planlanamadı.',
          ),
        );
      }
      final lowestPriority = droppable.first.priority;
      final candidatePool = droppable
          .where((activity) => activity.priority == lowestPriority)
          .toList();
      final nonMealCandidates = candidatePool
          .where((activity) => activity.category != 'meal')
          .toList();
      final mealCandidates = candidatePool
          .where((activity) => activity.category == 'meal')
          .toList();

      OptimizationResult? bestSuccess;
      OptimizationActivity? bestDrop;
      for (final pool in [nonMealCandidates, mealCandidates]) {
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
        if (bestSuccess != null) break;
      }

      if (bestSuccess != null && bestDrop != null) {
        dropped.add(_dropped(bestDrop));
        return OptimizationResult.success(
          activities: bestSuccess.activities,
          legs: bestSuccess.legs,
          metrics: bestSuccess.metrics!,
          warnings: bestSuccess.warnings,
          optimizationChanges: bestSuccess.optimizationChanges,
          droppedActivities: dropped,
          delta: bestSuccess.delta,
        );
      }

      final worst = nonMealCandidates.isNotEmpty
          ? nonMealCandidates.first
          : mealCandidates.first;
      dropped.add(_dropped(worst));
      current = current.where((activity) => activity.id != worst.id).toList();
    }
  }

  int _compareDropCandidates(
    OptimizationActivity a,
    OptimizationActivity b,
  ) {
    final priority = a.priority.index.compareTo(b.priority.index);
    if (priority != 0) return priority;
    final duration = b.durationMinutes.compareTo(a.durationMinutes);
    if (duration != 0) return duration;
    return a.id.compareTo(b.id);
  }

  DroppedActivity _dropped(OptimizationActivity activity) => DroppedActivity(
        activityId: activity.id,
        name: activity.name,
        priority: activity.priority,
        reason: activity.priority == ActivityPriority.optional
            ? DropReason.userOptional
            : DropReason.dayCapacity,
      );

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

  /// İstek başına bir kez kurulan çekirdek. Hard kısıtlar ve maliyet modeli
  /// artık motorun içinde değil; motor yalnız arama stratejisini yönetir.
  _Kernel _kernelFor(OptimizationRequest request) => _Kernel(
        request: request,
        checker: HardConstraintChecker(
          constraints: request.constraints,
          preferences: request.preferences,
          field: request.field,
        ),
        cost: CostFunction(
          weights: request.weights,
          config: config,
          preferences: request.preferences,
          field: request.field,
        ),
      );

  Future<OptimizationResult> _solve(OptimizationRequest request) async {
    final validation = _validate(request);
    if (validation != null) return OptimizationResult.failure(validation);

    final kernel = _kernelFor(request);

    if (request.activities.isEmpty) {
      return _emptyResult(kernel);
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
              kernel,
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
        final scoreComparison = _rank(kernel, a).compareTo(_rank(kernel, b));
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
      final withReturn = _appendReturn(kernel, state);
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
    best = _improveLocally(kernel, best);

    return _toResult(
      kernel,
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

  OptimizationResult _emptyResult(_Kernel kernel) {
    final request = kernel.request;
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
    final option = _sortOptions(kernel, options).first;
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
      kernel,
      request.constraints.startLocation.id,
      request.constraints.endLocation.id,
      request.constraints.availableStartTime,
      option,
      waitingMinutes: 0,
      bufferMinutes: 0,
    );
    final score = kernel.cost.transportScore(option);
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
        routeEfficiencyScore:
            kernel.cost.efficiency(score, option.doorToDoorMinutes),
        score: score,
        evaluatedStateCount: 1,
        prunedStateCount: 0,
        beamWidth: config.beamWidth,
        totalTransitWaitMinutes: option.resolvedTransitWaitMinutes,
        scheduleIdleMinutes: 0,
        partyTotalTransportCostYen: option
            .costForParty(request.preferences.partySize)
            .partyTotalCostYen,
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

  /// Bir aday aktiviteyi rotaya ekler.
  ///
  /// Akış: **saha düzeltmesi → zamanlama → hard kısıt kapıları → maliyet**.
  /// Bu sıra bilinçlidir; süre düzeltmesi uygulanmadan kısıt kontrol etmek
  /// (ör. Sakura'da uzayan ziyaret) yanlış "uygulanabilir" verdiktleri üretir.
  _RouteState? _append(
    _Kernel kernel,
    _RouteState state,
    OptimizationActivity activity,
    TransportOption option, {
    required List<OptimizationActivity> remainingAfter,
  }) {
    final request = kernel.request;
    final field = request.field;
    final departure = state.currentTime;

    // --- 1) Saha gerçekliği: pass kısıtı, trafik riski, istasyon tamponu ---
    final realised = kernel.checker.realiseTransit(
      option: option,
      departure: departure,
      from: state.currentLocation,
      to: activity.location,
    );
    if (realised == null) return null;
    final effective = realised.option;

    final arrival =
        departure.add(Duration(minutes: effective.doorToDoorMinutes));
    var buffer = kernel.cost.transitionBuffer(activity, effective);

    // Bagaj tamponu yalnız günün ilk yerleşiminde ve strateji bypass
    // etmiyorken uygulanır (Yamato ile gönderilen bagaj yolcuda değildir).
    final luggagePlan = field?.luggagePlan;
    var luggageBuffer = 0;
    if (luggagePlan != null &&
        state.scheduled.isEmpty &&
        !luggagePlan.bypassesStationLuggageBuffer) {
      luggageBuffer = luggagePlan.arrivalHandlingMinutes;
      buffer += luggageBuffer;
    }

    var start = arrival.add(Duration(minutes: buffer));

    // --- 2) Zamanlama ------------------------------------------------------
    if (activity.hasFixedSchedule) {
      if (kernel.checker.checkFixedArrival(
            activity: activity,
            earliestPossibleStart: start,
          ) !=
          null) {
        return null;
      }
      start = activity.fixedStartTime!;
    } else if (activity.openingTime != null &&
        start.compareTo(activity.openingTime!) < 0) {
      start = activity.openingTime!;
    }

    final plannedDuration = field == null
        ? activity.durationMinutes
        : field.inflateDuration(
            activity.durationMinutes,
            category: activity.category,
          );
    final end = activity.fixedEndTime ??
        start.add(Duration(
          minutes: plannedDuration + activity.estimatedQueueMinutes,
        ));

    final totalWalking = state.totalWalking + effective.walkingMinutes;
    final nextFixed = _earliestFixed(remainingAfter);

    // --- 3) Hard kısıt kapıları -------------------------------------------
    final violation = kernel.checker.check(PlacementCandidate(
      activity: activity,
      arrival: arrival,
      start: start,
      end: end,
      bufferMinutes: buffer,
      totalWalkingMinutes: totalWalking,
      effectiveOpeningTime: activity.openingTime,
      effectiveClosingTime: activity.closingTime,
      nextFixedActivity: nextFixed,
      reachabilityProbe: nextFixed == null
          ? null
          : () => _canReachFixed(kernel, activity.location, end, nextFixed),
    ));
    if (violation != null) return null;

    // --- 4) Maliyet --------------------------------------------------------
    final idleWaiting = max(0, start.difference(arrival).inMinutes - buffer);
    final progress = _progressOf(state);
    final scheduleRisk =
        kernel.cost.scheduleRisk(activity, arrival, buffer - luggageBuffer);
    if (!scheduleRisk.isFinite) return null;
    final backtracking =
        kernel.cost.backtrackingPenalty(progress, activity, effective);
    final clusterBreak = kernel.cost.clusterBreakPenalty(progress, activity);
    final fatigue = kernel.cost.fatigue(totalWalking);
    final complexity = kernel.cost.complexity(effective);
    final availableOptions = _validOptions(
      request.routeMatrix,
      state.currentLocation.id,
      activity.location.id,
    );
    final increment = kernel.cost.transportScore(effective) +
        kernel.cost.modeChoiceAdjustment(effective, availableOptions) +
        idleWaiting * request.weights.waiting +
        backtracking * request.weights.backtracking +
        scheduleRisk * request.weights.scheduleRisk +
        (fatigue - state.fatigue) * request.weights.walking +
        clusterBreak * request.weights.clusterBreak +
        complexity * request.weights.complexity +
        kernel.cost.preferredTimePenalty(activity, start);

    final leg = _leg(
      kernel,
      state.currentLocation.id,
      activity.location.id,
      departure,
      effective,
      waitingMinutes: idleWaiting + effective.waitingMinutes,
      bufferMinutes: buffer,
      scheduleIdleMinutes: idleWaiting,
      realised: realised,
    );
    final warningList = <String>[
      if (effective.isEstimated)
        '${activity.name} geçişinde yaklaşık rota verisi kullanıldı.',
      if (effective.reliabilityScore < .75)
        '${activity.name} geçişinin güvenilirliği düşük.',
      if (realised.hasTrafficRiskDisclaimer)
        '${activity.name} geçişinde varış saati trafiğe bağlı değişebilir.',
      if (realised.disclaimers.contains(TransitDisclaimer.railPassDowngrade))
        '${activity.name} geçişi pass kapsamındaki daha yavaş servise alındı.',
      if (realised.stationNavigationBufferMinutes > 0)
        '${activity.name} geçişine büyük istasyon aktarma payı eklendi.',
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
      optimizationReason: _reason(state, activity, effective, clusterBreak),
      warnings: warningList,
    );
    return state.copyWith(
      scheduled: [...state.scheduled, scheduled],
      visitedIds: {...state.visitedIds, activity.id},
      currentTime: end,
      currentLocation: activity.location,
      totalTravel: state.totalTravel + effective.doorToDoorMinutes,
      totalWalking: totalWalking,
      totalWaiting: state.totalWaiting + idleWaiting + effective.waitingMinutes,
      totalTransfers: state.totalTransfers + effective.transferCount,
      totalCost: state.totalCost + effective.estimatedCostYen,
      backtracking: state.backtracking + backtracking,
      clusterBreak: state.clusterBreak + clusterBreak,
      scheduleRisk: state.scheduleRisk + scheduleRisk,
      fatigue: fatigue,
      complexity: state.complexity + complexity,
      score: state.score + increment,
      closedClusters: closedClusters,
      currentCluster: nextCluster,
      previousLocation: state.currentLocation,
      previousOption: effective,
      warnings: [...state.warnings, ...warningList],
    );
  }

  RouteProgress _progressOf(_RouteState state) => RouteProgress(
        currentLocation: state.currentLocation,
        closedClusters: state.closedClusters,
        currentCluster: state.currentCluster,
        fatigue: state.fatigue,
        previousLocation: state.previousLocation,
        previousOption: state.previousOption,
      );

  bool _canReachFixed(
    _Kernel kernel,
    TripLocation from,
    DateTime departure,
    OptimizationActivity fixed,
  ) {
    final options =
        _validOptions(kernel.request.routeMatrix, from.id, fixed.location.id);
    return options.any((option) {
      final realised = kernel.checker.realiseTransit(
        option: option,
        departure: departure,
        from: from,
        to: fixed.location,
      );
      if (realised == null) return false;
      final buffer = kernel.cost.transitionBuffer(fixed, realised.option);
      final arrival = departure.add(
        Duration(minutes: realised.option.doorToDoorMinutes + buffer),
      );
      return arrival.compareTo(fixed.fixedStartTime!) <= 0;
    });
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

  double _rank(_Kernel kernel, _RouteState state) {
    final request = kernel.request;
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
      final optionScore = options
          .map((option) => kernel.cost.transportScore(option))
          .reduce(min);
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
          .map((option) => kernel.cost.transportScore(option))
          .reduce(min);
    }
    return state.score +
        (bestNext.isFinite ? bestNext : 100000) +
        returnEstimate * .35;
  }

  List<TransportOption> _sortOptions(
    _Kernel kernel,
    List<TransportOption> options,
  ) {
    final profile = kernel.request.preferences.profile;
    final sorted = [...options]..sort((a, b) {
        var aScore = kernel.cost.transportScore(a);
        var bScore = kernel.cost.transportScore(b);
        final fastestTransit = options
            .where((option) => option.mode != TransportMode.walking)
            .map((option) => option.doorToDoorMinutes)
            .fold<int?>(
                null, (best, value) => best == null ? value : min(best, value));
        if (fastestTransit != null &&
            a.mode == TransportMode.walking &&
            a.doorToDoorMinutes - fastestTransit <=
                config.walkingTimeToleranceMinutes &&
            profile != RouteOptimizationProfile.leastWalking &&
            profile != RouteOptimizationProfile.fastest) {
          aScore -= 8;
        }
        if (fastestTransit != null &&
            b.mode == TransportMode.walking &&
            b.doorToDoorMinutes - fastestTransit <=
                config.walkingTimeToleranceMinutes &&
            profile != RouteOptimizationProfile.leastWalking &&
            profile != RouteOptimizationProfile.fastest) {
          bScore -= 8;
        }
        final comparison = aScore.compareTo(bScore);
        if (comparison != 0) return comparison;
        return a.mode.index.compareTo(b.mode.index);
      });
    return sorted;
  }

  _RouteState? _appendReturn(_Kernel kernel, _RouteState state) {
    final request = kernel.request;
    final options = _validOptions(
      request.routeMatrix,
      state.currentLocation.id,
      request.constraints.endLocation.id,
    );
    if (options.isEmpty) return null;

    // Coin locker kullanıldıysa gün sonunda bagajı almak için ek süre gerekir.
    final luggagePlan = request.field?.luggagePlan;
    final retrieval = luggagePlan == null ? 0 : luggagePlan.retrievalMinutes;

    for (final option in _sortOptions(kernel, options)) {
      final realised = kernel.checker.realiseTransit(
        option: option,
        departure: state.currentTime,
        from: state.currentLocation,
        to: request.constraints.endLocation,
      );
      if (realised == null) continue;
      final effective = realised.option;

      if (state.totalWalking + effective.walkingMinutes >
          request.preferences.maximumWalkingMinutes) {
        continue;
      }
      final arrival = state.currentTime.add(
        Duration(minutes: effective.doorToDoorMinutes + retrieval),
      );
      if (arrival.compareTo(request.constraints.availableEndTime) > 0) {
        continue;
      }
      final leg = _leg(
        kernel,
        state.currentLocation.id,
        request.constraints.endLocation.id,
        state.currentTime,
        effective,
        waitingMinutes: effective.waitingMinutes,
        bufferMinutes: retrieval,
        realised: realised,
      );
      return state.copyWith(
        returnLeg: leg,
        totalTravel: state.totalTravel + effective.doorToDoorMinutes,
        totalWalking: state.totalWalking + effective.walkingMinutes,
        totalWaiting: state.totalWaiting + effective.waitingMinutes,
        totalTransfers: state.totalTransfers + effective.transferCount,
        totalCost: state.totalCost + effective.estimatedCostYen,
        score: state.score + kernel.cost.transportScore(effective),
        warnings: [
          ...state.warnings,
          if (effective.isEstimated) 'Gün sonu dönüş rota verisi yaklaşıktır.',
        ],
      );
    }
    return null;
  }

  _RouteState _improveLocally(_Kernel kernel, _RouteState initial) {
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
        final simulated = _simulateOrder(kernel, candidate);
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
    _Kernel kernel,
    List<OptimizationActivity> order,
  ) {
    var state = _RouteState.initial(
      currentTime: kernel.request.constraints.availableStartTime,
      currentLocation: kernel.request.constraints.startLocation,
    );
    for (var index = 0; index < order.length; index++) {
      final activity = order[index];
      final options = _sortOptions(
        kernel,
        _validOptions(
          kernel.request.routeMatrix,
          state.currentLocation.id,
          activity.location.id,
        ),
      );
      _RouteState? bestOption;
      for (final option in options) {
        final appended = _append(
          kernel,
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
    return _appendReturn(kernel, state);
  }

  OptimizationResult _toResult(
    _Kernel kernel,
    _RouteState state, {
    required int evaluatedStates,
    required int prunedStates,
  }) {
    final request = kernel.request;
    final legs = [
      ...state.scheduled.map((item) => item.inboundLeg),
      if (state.returnLeg != null) state.returnLeg!,
    ];
    final routeChanges = <String>[];
    final baseline = _simulateOrder(kernel, request.activities);
    final baselineLegs = baseline == null
        ? const <RouteLeg>[]
        : [
            ...baseline.scheduled.map((item) => item.inboundLeg),
            if (baseline.returnLeg != null) baseline.returnLeg!,
          ];
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
        routeEfficiencyScore:
            kernel.cost.efficiency(state.score, state.totalTravel),
        score: state.score,
        evaluatedStateCount: evaluatedStates,
        prunedStateCount: prunedStates,
        beamWidth: config.beamWidth,
        totalTransitWaitMinutes: legs.fold<int>(
          0,
          (sum, leg) => sum + leg.transitWaitMinutes,
        ),
        scheduleIdleMinutes: legs.fold<int>(
          0,
          (sum, leg) => sum + leg.scheduleIdleMinutes,
        ),
        partyTotalTransportCostYen: legs.fold<int>(
          0,
          (sum, leg) => sum + leg.partyTotalCostYen,
        ),
      ),
      warnings: state.warnings.toSet().toList(),
      optimizationChanges: routeChanges,
      delta: baseline == null
          ? null
          : OptimizationDelta(
              travelDeltaMinutes: state.totalTravel - baseline.totalTravel,
              walkingDeltaMinutes: state.totalWalking - baseline.totalWalking,
              idleDeltaMinutes: legs.fold<int>(
                    0,
                    (sum, leg) => sum + leg.scheduleIdleMinutes,
                  ) -
                  baselineLegs.fold<int>(
                    0,
                    (sum, leg) => sum + leg.scheduleIdleMinutes,
                  ),
              transferDelta: state.totalTransfers - baseline.totalTransfers,
              partyCostDeltaYen: legs.fold<int>(
                    0,
                    (sum, leg) => sum + leg.partyTotalCostYen,
                  ) -
                  baselineLegs.fold<int>(
                    0,
                    (sum, leg) => sum + leg.partyTotalCostYen,
                  ),
              backtrackingDelta: state.backtracking - baseline.backtracking,
              objectiveScoreDelta: state.score - baseline.score,
              objectiveImprovementPct: baseline.score == 0
                  ? 0
                  : (baseline.score - state.score) / baseline.score * 100,
            ),
    );
  }

  RouteLeg _leg(
    _Kernel kernel,
    String from,
    String to,
    DateTime departure,
    TransportOption option, {
    required int waitingMinutes,
    required int bufferMinutes,
    int scheduleIdleMinutes = 0,
    RealisedTransit? realised,
  }) {
    final cost = option.costForParty(kernel.request.preferences.partySize);
    return RouteLeg(
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
      rideMinutes: option.resolvedRideMinutes,
      accessMinutes: option.resolvedAccessMinutes,
      transitWaitMinutes: option.resolvedTransitWaitMinutes,
      scheduleIdleMinutes: scheduleIdleMinutes,
      costPerPersonYen: cost.costPerPersonYen,
      partyTotalCostYen: cost.partyTotalCostYen,
      vehicleCount: cost.vehicleCount,
      fareBasis: cost.fareBasis,
      lineId: option.lineId,
      directionId: option.directionId,
      complexityPenalty: option.complexityPenalty,
      providerId: option.providerId,
      stationNavigationBufferMinutes:
          realised?.stationNavigationBufferMinutes ?? 0,
      trafficRiskMultiplier: realised?.trafficRiskMultiplier ?? 1,
      effectiveShinkansenService: realised?.effectiveService,
      transitDisclaimers: realised?.disclaimers ?? const {},
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

/// İstek başına kurulan çekirdek: arama stratejisi (motor), fizibilite
/// (checker) ve maliyet (cost) tek yerde bağlanır.
class _Kernel {
  const _Kernel({
    required this.request,
    required this.checker,
    required this.cost,
  });

  final OptimizationRequest request;
  final HardConstraintChecker checker;
  final CostFunction cost;
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
