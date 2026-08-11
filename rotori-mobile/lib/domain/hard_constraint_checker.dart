/// `BeamSearchItineraryOptimizer` çekirdeğinin iki ayrık sorumluluğu.
///
/// - [HardConstraintChecker] — **ikili** kapılar. Bir yerleşim ya olur ya
///   olmaz; ihlal, makine-okunur bir [HardConstraintViolation] döner ve durum
///   budanır (prune). Skor üretmez.
/// - [CostFunction] — **sürekli** maliyet. Yalnız uygulanabilir yerleşimler
///   puanlanır; hiçbir zaman fizibiliteyi değiştirmez.
///
/// Bu ayrım kasıtlıdır: v2'de her iki mantık `_append` içinde iç içeydi ve
/// yeni bir saha kuralı eklemek skorlamayı sessizce bozabiliyordu. Ayrıştıktan
/// sonra Pazartesi kayması, Nozomi kısıtı veya istasyon tamponu eklemek tek
/// bir sınıfa dokunur.
///
/// **Geriye uyumluluk sözleşmesi:** `field == null` iken her iki sınıf da v2
/// ile birebir aynı sonucu üretir. Saha kuralları yalnız bir
/// [FieldRealityContext] verildiğinde devreye girer.
library;

import 'dart:math' as math;

import 'itinerary_optimizer.dart';
import 'japan_calendar.dart';
import 'japan_transit_realism.dart';
import 'luggage_logistics.dart';
import 'route_field_context.dart';
import 'route_matrix.dart';

// ---------------------------------------------------------------------------
// İhlal sözleşmesi
// ---------------------------------------------------------------------------

enum HardConstraintViolationType {
  /// Sabit saatli rezervasyona zamanında varılamıyor.
  fixedReservationMissed,

  /// Aktivite açılış/kapanış penceresine sığmıyor.
  openingWindowConflict,

  /// Mekan o tarihte kapalı (teishukubi / Holiday Shift / yıl sonu).
  closedOnDate,

  /// Gün başlangıç/bitiş sınırı aşıldı.
  dayBoundaryExceeded,

  /// Minimum ziyaret süresi sağlanamıyor.
  minimumDurationNotMet,

  /// Günlük yürüme limiti aşıldı.
  walkingLimitExceeded,

  /// Bu aktiviteden sonra sıradaki sabit aktiviteye yetişilemiyor.
  unreachableFixedActivity,

  /// Otel check-in penceresi kapandı (varış > checkInEndTime).
  hotelCheckInWindowClosed,

  /// Kullanıcının pass'i bu servisi kapsamıyor (JR Pass + Nozomi/Mizuho).
  passExcludedTransit,
}

class HardConstraintViolation {
  const HardConstraintViolation({
    required this.type,
    required this.message,
    this.activityId,
    this.detail,
  });

  final HardConstraintViolationType type;
  final String message;
  final String? activityId;

  /// Makine-okunur ek bağlam (kapanış nedeni, servis adı vb.).
  final String? detail;

  @override
  String toString() =>
      'HardConstraintViolation(${type.name}${activityId == null ? '' : ', $activityId'})';
}

// ---------------------------------------------------------------------------
// Değerlendirme girdileri
// ---------------------------------------------------------------------------

/// Sıraya eklenmek istenen tek bir yerleşim adayı.
class PlacementCandidate {
  const PlacementCandidate({
    required this.activity,
    required this.arrival,
    required this.start,
    required this.end,
    required this.bufferMinutes,
    required this.totalWalkingMinutes,
    required this.effectiveOpeningTime,
    required this.effectiveClosingTime,
    this.nextFixedActivity,
    this.reachabilityProbe,
  });

  final OptimizationActivity activity;

  /// Ulaşım bittiğinde konuma varış saati (tampon hariç).
  final DateTime arrival;

  final DateTime start;
  final DateTime end;
  final int bufferMinutes;

  /// Bu yerleşim dahil günün toplam yürüme süresi.
  final int totalWalkingMinutes;

  /// Sezonluk/kapanış düzeltmesi sonrası fiilî açılış-kapanış.
  final DateTime? effectiveOpeningTime;
  final DateTime? effectiveClosingTime;

  final OptimizationActivity? nextFixedActivity;

  /// Sıradaki sabit aktiviteye yetişilebilirlik sınaması.
  ///
  /// **Tembeldir (lazy):** matris taraması pahalıdır ve daha ucuz kapılar
  /// çoğu adayı önce eler. `null` ise sınama atlanır.
  final bool Function()? reachabilityProbe;
}

/// Rotanın o ana kadarki durumundan maliyet fonksiyonunun ihtiyaç duyduğu
/// alt küme. Optimizer'ın özel durumunu (`_RouteState`) dışarı sızdırmaz.
class RouteProgress {
  const RouteProgress({
    required this.currentLocation,
    required this.closedClusters,
    required this.currentCluster,
    required this.fatigue,
    this.previousLocation,
    this.previousOption,
  });

  final TripLocation currentLocation;
  final Set<String> closedClusters;
  final String? currentCluster;
  final double fatigue;
  final TripLocation? previousLocation;
  final TransportOption? previousOption;
}

// ---------------------------------------------------------------------------
// HardConstraintChecker
// ---------------------------------------------------------------------------

class HardConstraintChecker {
  const HardConstraintChecker({
    required this.constraints,
    required this.preferences,
    this.field,
  });

  final DayRouteConstraints constraints;
  final RoutePreferences preferences;

  /// `null` ise yalnız v2 kapıları uygulanır.
  final FieldRealityContext? field;

  /// Tüm ikili kapılar. İlk ihlalde döner — sıralama en ucuzdan en pahalıya.
  HardConstraintViolation? check(PlacementCandidate candidate) {
    final activity = candidate.activity;

    // --- v2 kapıları (davranış birebir korunur) ---------------------------
    if (candidate.end.compareTo(candidate.start) <= 0 ||
        candidate.end.difference(candidate.start).inMinutes <
            activity.minimumDurationMinutes) {
      return HardConstraintViolation(
        type: HardConstraintViolationType.minimumDurationNotMet,
        activityId: activity.id,
        message: '${activity.name} için minimum ziyaret süresi sağlanamıyor.',
      );
    }
    if (candidate.start.compareTo(constraints.availableStartTime) < 0 ||
        candidate.end.compareTo(constraints.availableEndTime) > 0) {
      return HardConstraintViolation(
        type: HardConstraintViolationType.dayBoundaryExceeded,
        activityId: activity.id,
        message: '${activity.name} gün sınırının dışına taşıyor.',
      );
    }
    final closing = candidate.effectiveClosingTime;
    if (closing != null && candidate.end.compareTo(closing) > 0) {
      return HardConstraintViolation(
        type: HardConstraintViolationType.openingWindowConflict,
        activityId: activity.id,
        message: '${activity.name} kapanış saatinden önce tamamlanamıyor.',
      );
    }
    if (candidate.totalWalkingMinutes > preferences.maximumWalkingMinutes) {
      return HardConstraintViolation(
        type: HardConstraintViolationType.walkingLimitExceeded,
        activityId: activity.id,
        message: 'Günlük yürüme limiti aşıldı.',
      );
    }
    // --- v3 saha kapıları (ucuz olanlar) ----------------------------------
    final context = field;
    if (context != null) {
      final closure = checkClosure(activity, context);
      if (closure != null) return closure;

      final checkIn = checkHotelCheckInWindow(candidate, context);
      if (checkIn != null) return checkIn;
    }

    // --- En pahalı kapı en sonda: matris taraması gerektirir ---------------
    final probe = candidate.reachabilityProbe;
    if (probe != null && !probe()) {
      return HardConstraintViolation(
        type: HardConstraintViolationType.unreachableFixedActivity,
        activityId: candidate.nextFixedActivity?.id ?? activity.id,
        message: 'Sıradaki sabit saatli aktiviteye zamanında ulaşılamıyor.',
      );
    }
    return null;
  }

  /// Sabit saatli aktiviteye varış kapısı. `_append` bu kararı erken vermek
  /// zorunda olduğu için ayrı bir yüzey olarak sunulur.
  HardConstraintViolation? checkFixedArrival({
    required OptimizationActivity activity,
    required DateTime earliestPossibleStart,
  }) {
    if (!activity.hasFixedSchedule) return null;
    final fixedStart = activity.fixedStartTime!;
    if (earliestPossibleStart.compareTo(fixedStart) > 0) {
      return HardConstraintViolation(
        type: HardConstraintViolationType.fixedReservationMissed,
        activityId: activity.id,
        message: '${activity.name} rezervasyon saatine yetişilemiyor.',
      );
    }
    return null;
  }

  /// Teishukubi (定休日) + Holiday Shift kapısı.
  ///
  /// Japon müzelerinin çoğu Pazartesi kapalıdır; **ama** Pazartesi resmî
  /// tatilse müze açılır ve kapanış tatil olmayan ilk güne kayar. Kural tek
  /// yerde ([ClosureResolver]) tanımlıdır; burada yalnız uygulanır.
  HardConstraintViolation? checkClosure(
    OptimizationActivity activity,
    FieldRealityContext context,
  ) {
    final rule = activity.closureRule;
    if (rule == null || !rule.hasAnyClosure) return null;
    final verdict = context.closureResolver.evaluate(rule, activity.day);
    if (!verdict.isClosed) return null;
    return HardConstraintViolation(
      type: HardConstraintViolationType.closedOnDate,
      activityId: activity.id,
      message: switch (verdict.cause!) {
        ClosureCause.weeklyClosure =>
          '${activity.name} bu gün haftalık kapanış günündedir.',
        ClosureCause.shiftedClosure =>
          '${activity.name} resmî tatil kayması nedeniyle bu gün kapalıdır.',
        ClosureCause.yearEndClosure =>
          '${activity.name} yıl sonu kapanışındadır.',
        ClosureCause.exceptionalClosure =>
          '${activity.name} bu tarihte özel olarak kapalıdır.',
      },
      detail: verdict.cause!.name,
    );
  }

  /// Otel check-in penceresi (`checkInStartTime` … `checkInEndTime`) kesin
  /// kısıttır: pencere kapandıktan sonra varış planı uygulanamaz.
  HardConstraintViolation? checkHotelCheckInWindow(
    PlacementCandidate candidate,
    FieldRealityContext context,
  ) {
    if (!context.enforceHotelCheckInWindow) return null;
    if (!candidate.activity.requiresHotelCheckIn) return null;
    final status = evaluateHotelCheckIn(
      arrival: candidate.arrival,
      policy: context.hotelPolicy,
    );
    if (status != HotelCheckInStatus.afterWindow) return null;
    return HardConstraintViolation(
      type: HardConstraintViolationType.hotelCheckInWindowClosed,
      activityId: candidate.activity.id,
      message: 'Otel check-in penceresi kapandıktan sonra varılıyor.',
      detail: status.name,
    );
  }

  /// Ulaşım seçeneğini saha gerçekliğine göre yeniden değerler.
  ///
  /// Dönen `null`, seçeneğin **uygulanamaz** olduğunu bildirir (ör. JR Pass
  /// sahibi için Nozomi). Aksi halde süre/yürüme/aktarma düzeltmeleri
  /// uygulanmış bir kopya ve UI uyarıları döner.
  RealisedTransit? realiseTransit({
    required TransportOption option,
    required DateTime departure,
    required TripLocation from,
    required TripLocation to,
  }) {
    final context = field;
    if (context == null) {
      return RealisedTransit(option: option, disclaimers: const {});
    }
    final outcome = context.transitModel.evaluate(
      option,
      departure: departure,
      railPass: context.traveller.railPass,
      fromLocationId: from.id,
      fromName: from.name,
      toLocationId: to.id,
      toName: to.name,
      walkingMultiplier: context.walkingCrowdMultiplier,
      passCoversThisLeg: context.passCoversAllLegs,
    );
    if (!outcome.isFeasible) return null;
    return RealisedTransit(
      option: option.copyWith(
        doorToDoorMinutes: outcome.doorToDoorMinutes,
        walkingMinutes: outcome.walkingMinutes,
        transferCount: outcome.transferCount,
        estimatedCostYen: option.estimatedCostYen + outcome.surchargeYen,
      ),
      disclaimers: outcome.disclaimers,
      stationNavigationBufferMinutes: outcome.stationNavigationBufferMinutes,
      trafficRiskMultiplier: outcome.trafficRiskMultiplier,
      effectiveService: outcome.effectiveService,
    );
  }
}

/// Saha düzeltmesi uygulanmış ulaşım seçeneği + UI sinyalleri.
class RealisedTransit {
  const RealisedTransit({
    required this.option,
    required this.disclaimers,
    this.stationNavigationBufferMinutes = 0,
    this.trafficRiskMultiplier = 1,
    this.effectiveService,
  });

  final TransportOption option;
  final Set<TransitDisclaimer> disclaimers;
  final int stationNavigationBufferMinutes;
  final double trafficRiskMultiplier;
  final ShinkansenService? effectiveService;

  bool get hasTrafficRiskDisclaimer =>
      disclaimers.contains(TransitDisclaimer.trafficRisk);
}

// ---------------------------------------------------------------------------
// CostFunction
// ---------------------------------------------------------------------------

/// Rotanın sürekli maliyet modeli. Hiçbir metodu fizibiliteyi değiştirmez.
class CostFunction {
  const CostFunction({
    required this.weights,
    required this.config,
    required this.preferences,
    this.field,
  });

  final OptimizationWeights weights;
  final OptimizerConfig config;
  final RoutePreferences preferences;
  final FieldRealityContext? field;

  /// Tek bir ulaşım seçeneğinin taban maliyeti.
  double transportScore(TransportOption option) {
    final partyCost = option.costForParty(preferences.partySize);
    var score = option.doorToDoorMinutes * weights.travel +
        option.waitingMinutes * weights.waiting +
        option.transferCount * weights.transfer +
        option.walkingMinutes * weights.walking +
        (partyCost.partyTotalCostYen / 100) * weights.transportCost;

    if (preferences.effectiveLuggageState == LuggageState.carried) {
      score += option.walkingMinutes * 1.5 +
          option.transferCount * 12 +
          option.complexityPenalty * 2;
      if (option.mode == TransportMode.taxi) score -= 10;
    } else if (preferences.effectiveLuggageState == LuggageState.forwarded) {
      score += option.transferCount * 2;
    }

    if (option.mode == TransportMode.taxi) {
      score += switch (preferences.profile) {
        RouteOptimizationProfile.fastest => 0,
        RouteOptimizationProfile.leastWalking => 3,
        RouteOptimizationProfile.balanced => 12,
        RouteOptimizationProfile.cheapest => 30,
      };
    }
    if (option.reliabilityScore < .9) {
      score += (1 - option.reliabilityScore) * 20 * weights.scheduleRisk;
    }

    // v3: bagaj fiilen taşınıyorsa yürüme ve aktarma daha pahalıdır.
    // `LuggageState` kaba bir bayraktır; saha planı boyut bilgisi taşır.
    final plan = field?.luggagePlan;
    if (plan != null) {
      final discomfort =
          luggageDiscomfortFactor(plan.strategy, field!.traveller.luggageSize);
      if (discomfort > 0) {
        score += (option.walkingMinutes * discomfort) +
            (option.transferCount * 6 * discomfort);
      }
    }
    return score;
  }

  /// Yürünebilir mesafede transit varken yürüyüşü ödüllendiren düzeltme.
  double modeChoiceAdjustment(
    TransportOption option,
    List<TransportOption> alternatives,
  ) {
    if (option.mode != TransportMode.walking ||
        preferences.profile == RouteOptimizationProfile.leastWalking ||
        preferences.profile == RouteOptimizationProfile.fastest) {
      return 0;
    }
    final nonWalkingMinutes = alternatives
        .where((candidate) =>
            candidate.mode != TransportMode.walking &&
            candidate.mode != TransportMode.taxi)
        .map((candidate) => candidate.doorToDoorMinutes);
    if (nonWalkingMinutes.isEmpty) return 0;
    final fastest = nonWalkingMinutes.reduce(math.min);
    if (option.doorToDoorMinutes - fastest >
        config.walkingTimeToleranceMinutes) {
      return 0;
    }
    return preferences.profile == RouteOptimizationProfile.cheapest ? -35 : -25;
  }

  /// Sabit aktiviteye erken/geç varış riski. `infinity` = uygulanamaz;
  /// çağıran bunu hard kısıt olarak yorumlar.
  double scheduleRisk(
    OptimizationActivity activity,
    DateTime arrival,
    int requiredBuffer,
  ) {
    if (!activity.hasFixedSchedule) {
      if (activity.closingTime == null) return 0;
      final remaining = activity.closingTime!.difference(arrival).inMinutes;
      return math.max(0, 30 - remaining).toDouble();
    }
    final actualBuffer = activity.fixedStartTime!.difference(arrival).inMinutes;
    if (actualBuffer < requiredBuffer) return double.infinity;
    return math
        .max(0, config.preferredFixedActivityBufferMinutes - actualBuffer)
        .toDouble();
  }

  double preferredTimePenalty(OptimizationActivity activity, DateTime start) {
    final preferred = activity.preferredTime;
    if (preferred == null) return 0;
    final isPreferred = switch (preferred) {
      TimeOfDayPreference.morning => start.hour < 12,
      TimeOfDayPreference.afternoon => start.hour >= 12 && start.hour < 17,
      TimeOfDayPreference.evening => start.hour >= 17,
    };
    return isPreferred ? 0 : 12;
  }

  double clusterBreakPenalty(
    RouteProgress progress,
    OptimizationActivity activity,
  ) {
    final cluster = activity.clusterId;
    if (cluster == null || !progress.closedClusters.contains(cluster)) return 0;
    return config.clusterReentryPenalty;
  }

  double backtrackingPenalty(
    RouteProgress progress,
    OptimizationActivity next,
    TransportOption option,
  ) {
    var penalty = 0.0;
    final previous = progress.previousLocation;
    if (previous != null) {
      final ax = progress.currentLocation.longitude - previous.longitude;
      final ay = progress.currentLocation.latitude - previous.latitude;
      final bx = next.location.longitude - progress.currentLocation.longitude;
      final by = next.location.latitude - progress.currentLocation.latitude;
      final aLength = math.sqrt(ax * ax + ay * ay);
      final bLength = math.sqrt(bx * bx + by * by);
      if (aLength > 0 && bLength > 0) {
        final cosine = (ax * bx + ay * by) / (aLength * bLength);
        if (cosine < -.25) {
          penalty += option.doorToDoorMinutes * -cosine;
        }
      }
    }
    final previousOption = progress.previousOption;
    if (previousOption?.lineId != null &&
        previousOption!.lineId == option.lineId &&
        previousOption.directionId != null &&
        option.directionId != null &&
        previousOption.directionId != option.directionId) {
      penalty += option.doorToDoorMinutes.toDouble();
    }
    if (next.hasFixedSchedule) penalty *= .35;
    return penalty;
  }

  /// Geçiş tamponu. Sabit/rezervasyonlu aktivitelerde en geniş tampon
  /// uygulanır; aktarmalı veya raylı geçişlerde "karmaşık" tampon geçerlidir.
  int transitionBuffer(OptimizationActivity activity, TransportOption option) {
    if (activity.hasFixedSchedule || activity.hasReservation) {
      return math.max(
        config.fixedActivityBufferMinutes,
        activity.requiredArrivalBufferMinutes,
      );
    }
    if (option.transferCount > 0 ||
        option.mode == TransportMode.shinkansen ||
        option.mode == TransportMode.regionalTrain ||
        option.complexityPenalty > 0) {
      return config.complexTransitionBufferMinutes;
    }
    return config.simpleTransitionBufferMinutes;
  }

  /// Yürüme yorgunluğu — eşiği aşan dakikalar cezalandırılır.
  double fatigue(int totalWalkingMinutes) => math
      .max(0, totalWalkingMinutes - config.walkingFatigueThresholdMinutes)
      .toDouble();

  double complexity(TransportOption option) =>
      option.complexityPenalty + math.max(0, option.transferCount - 1) * 3;

  /// Rota verimlilik skoru (0-100).
  double efficiency(double score, int travelMinutes) {
    if (!score.isFinite) return 0;
    return (100 / (1 + math.max(0, score - travelMinutes) / 100))
        .clamp(0, 100)
        .toDouble();
  }
}
