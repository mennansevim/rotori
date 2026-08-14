// LLM rota incelemesinin SAF katmanı: istek gövdesini kurar, dönen öneriyi
// plan motoruna uygular.
//
// Neden ayrı ve saf: ağ ve UI'dan bağımsız olduğu için testte gerçek bir
// öneriyi gerçek bir plana uygulayıp sonucu doğrulayabiliyoruz. v3 model
// sözleşmesi yalnız sıra üretir; saat alanı eski yanıtlarla geriye uyumludur.
//
// **Güvenlik duruşu:** LLM önerisi TAVSİYEDİR. Uygulama tek yol üzerinden
// yapılır — `PlanScheduleEngine`. Motor kilitli durağı reddeder, çakışma
// üretecek saati reddeder. Yani model hatalı bir şey önerse bile plan geçersiz
// hâle gelemez; öneri sessizce düşer.

import '../data/route_review_client.dart';
import 'destination_profiles.dart' show getDestinationForDate;
import 'itinerary_optimizer.dart' show OptimizationWeights;
import 'plan_schedule_engine.dart';
import 'types.dart';

/// Edge Function'a gönderilecek gövdeyi kurar.
///
Map<String, dynamic> buildRouteReviewPayload({
  required Trip trip,
  required String languageCode,
  Set<int>? dayNumbers,
}) {
  final destinations = [...trip.preferences.destinations]
    ..sort((a, b) => a.order.compareTo(b.order));

  return {
    'promptVersion': routeReviewPromptVersion,
    'language': languageCode,
    'cities': [
      for (final d in destinations)
        {
          'city': d.city,
          'arrival': d.arrivalDate,
          'departure': d.departureDate,
        },
    ],
    'hotels': [
      for (final hotel in trip.hotels)
        {
          'city': hotel.city,
          'name': hotel.name,
          'address': hotel.address,
          'checkIn': hotel.checkIn,
          'checkOut': hotel.checkOut,
        },
    ],
    'days': [
      for (final day in trip.days)
        if (dayNumbers == null || dayNumbers.contains(day.dayNumber))
          {
            'dayNumber': day.dayNumber,
            'date': day.date,
            'city': getDestinationForDate(destinations, day.date)?.city ?? '',
            'stops': [
              for (final item in day.items)
                {
                  'id': item.id,
                  'title': item.title,
                  'time': item.time ?? item.scheduledTime,
                  'durationMin': item.durationMin,
                  'lat': item.lat,
                  'lng': item.lng,
                  // Kilitli durak modele AÇIKÇA bildirilir; prompt onu
                  // oynatmamakla yükümlü, motor da zorlar.
                  'locked': item.isFixed,
                  'kind': item.kind?.name,
                },
            ],
          },
    ],
  };
}

/// LLM adayının deterministik tabana göre kabul edilme sonucu.
enum VerifiedRouteReviewStatus {
  skippedByPolicy,
  unavailable,
  noSuggestion,
  rejectedBySafety,
  rejectedBySnapshot,
  rejectedByScore,
  accepted,
}

/// Snapshot'lardan yeniden hesaplanan, profil-duyarlı karşılaştırma özeti.
class RouteReviewScore {
  const RouteReviewScore({
    required this.objective,
    required this.travelMinutes,
    required this.walkingMinutes,
    required this.waitingMinutes,
    required this.transfers,
    required this.partyCostYen,
    required this.snapshotDayCount,
  });

  final double objective;
  final int travelMinutes;
  final int walkingMinutes;
  final int waitingMinutes;
  final int transfers;
  final int partyCostYen;
  final int snapshotDayCount;

  static RouteReviewScore? forDays(Trip trip, Set<int> dayNumbers) {
    if (dayNumbers.isEmpty) return null;
    var objective = 0.0;
    var travel = 0;
    var walking = 0;
    var waiting = 0;
    var transfers = 0;
    var cost = 0;
    var coveredDays = 0;

    for (final dayNumber in dayNumbers) {
      final day = trip.days.where((d) => d.dayNumber == dayNumber).firstOrNull;
      final snapshot = day?.routeExecutionSnapshot;
      if (snapshot == null || snapshot.legs.isEmpty) return null;
      coveredDays++;
      final weights = OptimizationWeights.forProfile(snapshot.profile);
      for (final leg in snapshot.legs) {
        travel += leg.travelDurationMinutes;
        walking += leg.walkingDurationMinutes;
        waiting += leg.waitingDurationMinutes;
        transfers += leg.transferCount;
        cost += leg.partyTotalCostYen;
        objective += leg.travelDurationMinutes * weights.travel +
            leg.waitingDurationMinutes * weights.waiting +
            leg.transferCount * weights.transfer +
            leg.walkingDurationMinutes * weights.walking +
            (leg.partyTotalCostYen / 100) * weights.transportCost +
            leg.complexityPenalty * weights.complexity +
            (1 - leg.reliabilityScore).clamp(0.0, 1.0) *
                20 *
                weights.scheduleRisk;
      }
    }

    return RouteReviewScore(
      objective: objective,
      travelMinutes: travel,
      walkingMinutes: walking,
      waitingMinutes: waiting,
      transfers: transfers,
      partyCostYen: cost,
      snapshotDayCount: coveredDays,
    );
  }
}

class VerifiedRouteReviewResult {
  const VerifiedRouteReviewResult({
    required this.trip,
    required this.status,
    this.appliedDays = const [],
    this.rejectedDays = const [],
    this.baselineScore,
    this.candidateScore,
    this.improvementPercent,
  });

  final Trip trip;
  final VerifiedRouteReviewStatus status;
  final List<int> appliedDays;
  final List<int> rejectedDays;
  final RouteReviewScore? baselineScore;
  final RouteReviewScore? candidateScore;
  final double? improvementPercent;

  bool get accepted => status == VerifiedRouteReviewStatus.accepted;
}

typedef RouteReviewCandidateOptimizer = Future<Trip> Function(
  Trip candidate,
  Set<int> affectedDays,
);

/// LLM önerisini ikinci bir rota gibi değerlendirir; model çıktısı hiçbir zaman
/// tek başına kabul kararı vermez.
Future<VerifiedRouteReviewResult> verifyRouteReviewCandidate({
  required Trip baseline,
  required RouteReview review,
  required RouteReviewCandidateOptimizer optimizeCandidate,
  double minimumImprovementPercent = 2,
}) async {
  final applied = applyRouteReview(trip: baseline, review: review);
  if (!applied.changedAnything) {
    return VerifiedRouteReviewResult(
      trip: baseline,
      status: review.hasSuggestions
          ? VerifiedRouteReviewStatus.rejectedBySafety
          : VerifiedRouteReviewStatus.noSuggestion,
      rejectedDays: applied.rejectedDays,
    );
  }

  final baselineIds = _activityIds(baseline);
  if (baselineIds.length != _activityCount(baseline) ||
      baselineIds.length != _activityCount(applied.trip) ||
      !_sameIds(baselineIds, _activityIds(applied.trip))) {
    return VerifiedRouteReviewResult(
      trip: baseline,
      status: VerifiedRouteReviewStatus.rejectedBySafety,
      appliedDays: applied.appliedDays,
      rejectedDays: applied.rejectedDays,
    );
  }

  final affectedDays = applied.appliedDays.toSet();
  final baselineScore = RouteReviewScore.forDays(baseline, affectedDays);
  if (baselineScore == null) {
    return VerifiedRouteReviewResult(
      trip: baseline,
      status: VerifiedRouteReviewStatus.rejectedBySnapshot,
      appliedDays: applied.appliedDays,
      rejectedDays: applied.rejectedDays,
    );
  }

  final candidate = await optimizeCandidate(applied.trip, affectedDays);
  final candidateIds = _activityIds(candidate);
  if (candidateIds.length != _activityCount(candidate) ||
      !_sameIds(baselineIds, candidateIds)) {
    return VerifiedRouteReviewResult(
      trip: baseline,
      status: VerifiedRouteReviewStatus.rejectedBySafety,
      appliedDays: applied.appliedDays,
      rejectedDays: applied.rejectedDays,
      baselineScore: baselineScore,
    );
  }

  final candidateScore = RouteReviewScore.forDays(candidate, affectedDays);
  if (candidateScore == null ||
      candidateScore.snapshotDayCount != baselineScore.snapshotDayCount) {
    return VerifiedRouteReviewResult(
      trip: baseline,
      status: VerifiedRouteReviewStatus.rejectedBySnapshot,
      appliedDays: applied.appliedDays,
      rejectedDays: applied.rejectedDays,
      baselineScore: baselineScore,
      candidateScore: candidateScore,
    );
  }

  final improvement = baselineScore.objective <= 0
      ? 0.0
      : (baselineScore.objective - candidateScore.objective) /
          baselineScore.objective *
          100;
  if (improvement < minimumImprovementPercent) {
    return VerifiedRouteReviewResult(
      trip: baseline,
      status: VerifiedRouteReviewStatus.rejectedByScore,
      appliedDays: applied.appliedDays,
      rejectedDays: applied.rejectedDays,
      baselineScore: baselineScore,
      candidateScore: candidateScore,
      improvementPercent: improvement,
    );
  }

  return VerifiedRouteReviewResult(
    trip: candidate,
    status: VerifiedRouteReviewStatus.accepted,
    appliedDays: applied.appliedDays,
    rejectedDays: applied.rejectedDays,
    baselineScore: baselineScore,
    candidateScore: candidateScore,
    improvementPercent: improvement,
  );
}

/// Model çağrısını yalnız ölçülebilir rota karmaşıklığı olan planlara sınırlar.
bool shouldRequestRouteReview(Trip trip) {
  return routeReviewCandidateDays(trip).isNotEmpty;
}

Set<int> routeReviewCandidateDays(Trip trip) {
  final candidates = <({int dayNumber, double complexity})>[];
  for (final day in trip.days) {
    final snapshot = day.routeExecutionSnapshot;
    if (snapshot == null || day.items.length < 4) continue;
    final score = RouteReviewScore.forDays(trip, {day.dayNumber});
    if (score == null) continue;
    if (score.travelMinutes >= 120 ||
        score.walkingMinutes >= 90 ||
        score.transfers >= 3) {
      candidates.add((
        dayNumber: day.dayNumber,
        complexity: score.travelMinutes +
            score.walkingMinutes * 1.5 +
            score.transfers * 30,
      ));
    }
  }
  candidates.sort((a, b) {
    final byComplexity = b.complexity.compareTo(a.complexity);
    return byComplexity != 0
        ? byComplexity
        : a.dayNumber.compareTo(b.dayNumber);
  });
  return candidates.take(3).map((candidate) => candidate.dayNumber).toSet();
}

Set<String> _activityIds(Trip trip) => {
      for (final day in trip.days)
        for (final item in day.items) item.id,
    };

int _activityCount(Trip trip) =>
    trip.days.fold(0, (total, day) => total + day.items.length);

bool _sameIds(Set<String> first, Set<String> second) =>
    first.length == second.length && first.containsAll(second);

/// Bir incelemenin plana uygulanma sonucu.
class RouteReviewOutcome {
  const RouteReviewOutcome({
    required this.trip,
    required this.appliedDays,
    required this.rejectedDays,
  });

  /// Uygulanabilen değişikliklerle güncellenmiş plan. Hiçbiri geçmediyse
  /// girdi planının aynısı.
  final Trip trip;

  /// En az bir değişikliği kabul edilen gün numaraları.
  final List<int> appliedDays;

  /// Motorun reddettiği gün numaraları.
  final List<int> rejectedDays;

  bool get changedAnything => appliedDays.isNotEmpty;
}

/// Öneriyi plan motoru üzerinden uygular.
///
/// Her gün BAĞIMSIZ değerlendirilir: bir gün reddedilirse diğerleri yine
/// uygulanır. Bir gün içindeki tek bir adım reddedilirse o günün tamamı geri
/// alınır — yarı uygulanmış sıra, hiç uygulanmamıştan kötüdür.
RouteReviewOutcome applyRouteReview({
  required Trip trip,
  required RouteReview review,
  PlanScheduleEngine engine = const PlanScheduleEngine(),
}) {
  var current = trip;
  final applied = <int>[];
  final rejected = <int>[];

  for (final suggestion in review.days) {
    final day = current.days
        .where((d) => d.dayNumber == suggestion.dayNumber)
        .firstOrNull;
    if (day == null) {
      rejected.add(suggestion.dayNumber);
      continue;
    }

    var dayTrip = current;
    var ok = true;
    var touched = false;

    // 1) Sıra. Hedef indekse tek tek taşıyoruz; motor kilitli durakta ya da
    //    çakışmada reddeder.
    if (suggestion.order.length == day.items.length) {
      for (var target = 0; target < suggestion.order.length; target++) {
        final id = suggestion.order[target];
        final live = dayTrip.days
            .where((d) => d.dayNumber == suggestion.dayNumber)
            .first;
        final currentIndex = live.items.indexWhere((i) => i.id == id);
        if (currentIndex < 0) {
          ok = false;
          break;
        }
        if (currentIndex == target) continue;
        final result = engine.apply(
          dayTrip,
          MoveActivityWithinDay(
            dayNumber: suggestion.dayNumber,
            activityId: id,
            targetIndex: target,
            preserveExistingTimes: true,
          ),
        );
        if (!result.isSuccess) {
          ok = false;
          break;
        }
        dayTrip = result.trip!;
        touched = true;
      }
    }

    // 2) Saatler.
    if (ok) {
      for (final entry in suggestion.times.entries) {
        final minutes = _minutesFromHhmm(entry.value);
        if (minutes == null) continue;
        final result = engine.apply(
          dayTrip,
          UpdateActivityTime(
            dayNumber: suggestion.dayNumber,
            activityId: entry.key,
            startMinutes: minutes,
          ),
        );
        // Tek bir saat reddedilirse günü topluca düşürmüyoruz: sıra değişikliği
        // kendi başına değerli. Ama saat uygulanmamış sayılır.
        if (result.isSuccess) {
          dayTrip = result.trip!;
          touched = true;
        }
      }
    }

    if (ok && touched) {
      current = dayTrip;
      applied.add(suggestion.dayNumber);
    } else {
      rejected.add(suggestion.dayNumber);
    }
  }

  return RouteReviewOutcome(
    trip: current,
    appliedDays: applied,
    rejectedDays: rejected,
  );
}

int? _minutesFromHhmm(String value) {
  final parts = value.split(':');
  if (parts.length != 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  if (h < 0 || h > 23 || m < 0 || m > 59) return null;
  return h * 60 + m;
}
