import 'package:rotori/domain/itinerary_optimizer.dart';
import 'package:rotori/domain/route_matrix.dart';

import 'route_plan_scenario.dart';
import 'route_time.dart';

/// Prompt sözleşmesine uyan bir rota planlayıcı — gerçek AI çağrısı ya da
/// deterministik BeamSearch mock'u aynı arayüzü uygular.
abstract interface class RoutePlannerAgent {
  /// Uygulanamaz senaryoda `null` (Section A: "Red şartları" → `{"error":...}`).
  Future<RoutePlanOutput?> plan(RoutePlanScenario scenario);
}

/// CI / offline default. Gerçek modele bağlanmadan `BeamSearchItineraryOptimizer`
/// çıktısını Section A çıktı şemasına dönüştürür. Rubric bu ajanı benchmark
/// olarak da kullanır.
class BeamSearchPlannerAgent implements RoutePlannerAgent {
  const BeamSearchPlannerAgent({
    this.optimizer = const BeamSearchItineraryOptimizer(
      config: OptimizerConfig(allowActivityDropping: true),
    ),
    this.preferences = const RoutePreferences(),
  });

  final BeamSearchItineraryOptimizer optimizer;
  final RoutePreferences preferences;

  @override
  Future<RoutePlanOutput?> plan(RoutePlanScenario scenario) async {
    final adapter = _ScenarioAdapter(scenario);
    final result = await optimizer.optimize(adapter.buildRequest(preferences));
    if (!result.isSuccess) return null;
    return adapter.toPromptOutput(result);
  }
}

/// BeamSearch üstünden benchmark metriklerini üretir. Aynı sonuç tekrar
/// tekrar hesaplanmasın diye ayrı bir tip.
Future<PromptOutputAndMetrics> planWithBeamSearch(
  RoutePlanScenario scenario, {
  BeamSearchItineraryOptimizer optimizer = const BeamSearchItineraryOptimizer(
    config: OptimizerConfig(allowActivityDropping: true),
  ),
  RoutePreferences preferences = const RoutePreferences(),
}) async {
  final adapter = _ScenarioAdapter(scenario);
  final result = await optimizer.optimize(adapter.buildRequest(preferences));
  return PromptOutputAndMetrics(
    output: result.isSuccess ? adapter.toPromptOutput(result) : null,
    result: result,
  );
}

class PromptOutputAndMetrics {
  const PromptOutputAndMetrics({required this.output, required this.result});

  final RoutePlanOutput? output;
  final OptimizationResult result;
}

class _ScenarioAdapter {
  _ScenarioAdapter(this.scenario);

  final RoutePlanScenario scenario;

  static const _hotelId = 'hotel';

  OptimizationRequest buildRequest(RoutePreferences preferences) {
    final hotelLocation = TripLocation(
      id: _hotelId,
      name: scenario.hotel.name,
      latitude: scenario.hotel.latitude,
      longitude: scenario.hotel.longitude,
      city: scenario.city,
      clusterId: scenario.hotel.cluster,
    );

    final activities = scenario.activities.map((activity) {
      final location = TripLocation(
        id: activity.id,
        name: activity.name,
        latitude: activity.latitude,
        longitude: activity.longitude,
        city: scenario.city,
        clusterId: activity.cluster,
      );
      return OptimizationActivity(
        id: activity.id,
        name: activity.name,
        day: scenario.dayStart,
        location: location,
        durationMinutes: activity.durationMinutes,
        minimumDurationMinutes:
            activity.minimumDurationMinutes ?? activity.durationMinutes,
        openingTime: activity.openingTime == null
            ? null
            : combineDateAndHhmm(scenario.date, activity.openingTime!),
        closingTime: activity.closingTime == null
            ? null
            : combineDateAndHhmm(scenario.date, activity.closingTime!),
        fixedStartTime: activity.fixedStartTime == null
            ? null
            : combineDateAndHhmm(scenario.date, activity.fixedStartTime!),
        fixedEndTime: activity.fixedEndTime == null
            ? null
            : combineDateAndHhmm(scenario.date, activity.fixedEndTime!),
        isFixed: activity.isFixed,
        isLocked: activity.isLocked,
        hasReservation: activity.hasReservation,
        preferredTime: switch (activity.preferredTime) {
          null => null,
          PromptTimePreference.morning => TimeOfDayPreference.morning,
          PromptTimePreference.afternoon => TimeOfDayPreference.afternoon,
          PromptTimePreference.evening => TimeOfDayPreference.evening,
        },
        category: activity.category.name,
      );
    }).toList();

    final matrixEntries = _buildMatrixEntries();
    return OptimizationRequest(
      activities: activities,
      routeMatrix:
          RouteMatrix(entries: matrixEntries, version: 'e2e-scenario'),
      constraints: DayRouteConstraints(
        startLocation: hotelLocation,
        endLocation: hotelLocation,
        availableStartTime: scenario.dayStart,
        availableEndTime: scenario.dayEnd,
      ),
      preferences: preferences,
    );
  }

  RoutePlanOutput toPromptOutput(OptimizationResult result) {
    final timeline = <PromptTimelineEntry>[];
    for (final scheduled in result.activities) {
      timeline.add(PromptTimelineEntry.transit(
        startTime: formatHhmm(scheduled.inboundLeg.departureTime),
        endTime: formatHhmm(scheduled.inboundLeg.arrivalTime),
        fromId: _denormalizeId(scheduled.inboundLeg.fromLocationId),
        toId: _denormalizeId(scheduled.inboundLeg.toLocationId),
        mode: _mapMode(scheduled.inboundLeg.mode),
        doorToDoorMinutes: scheduled.inboundLeg.travelDurationMinutes,
        walkingMinutes: scheduled.inboundLeg.walkingDurationMinutes,
        transferCount: scheduled.inboundLeg.transferCount,
        yenCost: scheduled.inboundLeg.estimatedCostYen,
      ));
      if (scheduled.startTime.isAfter(scheduled.inboundLeg.arrivalTime)) {
        timeline.add(PromptTimelineEntry.idle(
          startTime: formatHhmm(scheduled.inboundLeg.arrivalTime),
          endTime: formatHhmm(scheduled.startTime),
          note: 'buffer',
        ));
      }
      timeline.add(PromptTimelineEntry.activity(
        startTime: formatHhmm(scheduled.startTime),
        endTime: formatHhmm(scheduled.endTime),
        activityId: scheduled.activityId,
      ));
    }
    final returnLeg = result.legs.isNotEmpty ? result.legs.last : null;
    if (returnLeg != null &&
        (result.activities.isEmpty ||
            returnLeg.fromLocationId !=
                result.activities.last.inboundLeg.fromLocationId ||
            returnLeg.toLocationId !=
                result.activities.last.inboundLeg.toLocationId)) {
      timeline.add(PromptTimelineEntry.transit(
        startTime: formatHhmm(returnLeg.departureTime),
        endTime: formatHhmm(returnLeg.arrivalTime),
        fromId: _denormalizeId(returnLeg.fromLocationId),
        toId: _denormalizeId(returnLeg.toLocationId),
        mode: _mapMode(returnLeg.mode),
        doorToDoorMinutes: returnLeg.travelDurationMinutes,
        walkingMinutes: returnLeg.walkingDurationMinutes,
        transferCount: returnLeg.transferCount,
        yenCost: returnLeg.estimatedCostYen,
      ));
    }

    final metrics = result.metrics;
    final hasLunch = _hasMealInWindow(result, 11 * 60 + 30, 14 * 60);
    return RoutePlanOutput(
      date: scenario.date,
      timeline: timeline,
      dropped: [
        for (final id in result.droppedActivityIds)
          PromptDropped(activityId: id, reason: PromptDropReason.duration),
      ],
      metrics: PromptMetrics(
        totalTransitMinutes: metrics?.totalTravelMinutes ?? 0,
        totalWalkingMinutes: metrics?.totalWalkingMinutes ?? 0,
        totalTransfers: metrics?.totalTransferCount ?? 0,
        totalYenCost: metrics?.estimatedTransportCostYen ?? 0,
        clusterEntries: _countClusterEntries(result),
        backtracking: _backtrackingSeverity(metrics?.backtrackingMinutes ?? 0),
        hasLunch: hasLunch,
        hasDinner: _hasMealInWindow(result, 18 * 60, 22 * 60),
      ),
      warnings: [
        ...result.warnings,
        // Section A Kural 7: öğle yemeği dinner gibi "SIKI" değildir — uygun
        // bir restoran yoksa (ör. tek mekan akşama fixed) modelin bunu açıkça
        // bildirmesi kabul edilir (synthetic:meal alternatifinin yerine).
        if (!hasLunch)
          'Öğle yemeği penceresinde (11:30–14:00) planlanabilir bir mekan bulunamadı.',
      ],
    );
  }

  List<RouteMatrixEntry> _buildMatrixEntries() {
    final grouped = <String, List<TransportOption>>{};
    for (final entry in scenario.routeMatrix) {
      final key = '${_normalizeId(entry.fromId)} ${_normalizeId(entry.toId)}';
      grouped
          .putIfAbsent(key, () => [])
          .add(_mapOption(entry));
    }
    final entries = <RouteMatrixEntry>[];
    for (final MapEntry(:key, :value) in grouped.entries) {
      final parts = key.split(' ');
      entries.add(RouteMatrixEntry(
        fromLocationId: parts[0],
        toLocationId: parts[1],
        options: value,
      ));
    }
    return entries;
  }

  String _normalizeId(String id) => id == scenario.hotel.id ? _hotelId : id;

  String _denormalizeId(String id) => id == _hotelId ? scenario.hotel.id : id;

  TransportOption _mapOption(PromptRouteEntry entry) => TransportOption(
        mode: switch (entry.mode) {
          PromptTransportMode.walking => TransportMode.walking,
          PromptTransportMode.train => TransportMode.train,
          PromptTransportMode.metro => TransportMode.metro,
          PromptTransportMode.bus => TransportMode.bus,
          PromptTransportMode.taxi => TransportMode.taxi,
          PromptTransportMode.shinkansen => TransportMode.shinkansen,
          PromptTransportMode.regional => TransportMode.regionalTrain,
        },
        doorToDoorMinutes: entry.doorToDoorMinutes,
        walkingMinutes: entry.walkingMinutes,
        waitingMinutes: 0,
        transferCount: entry.transferCount,
        estimatedCostYen: entry.yenCost,
        reliabilityScore: entry.reliability.clamp(0, 1),
      );

  PromptTransportMode _mapMode(TransportMode mode) => switch (mode) {
        TransportMode.walking => PromptTransportMode.walking,
        TransportMode.train => PromptTransportMode.train,
        TransportMode.metro => PromptTransportMode.metro,
        TransportMode.bus => PromptTransportMode.bus,
        TransportMode.taxi => PromptTransportMode.taxi,
        TransportMode.shinkansen => PromptTransportMode.shinkansen,
        TransportMode.regionalTrain => PromptTransportMode.regional,
      };

  int _countClusterEntries(OptimizationResult result) {
    String? current;
    var count = 0;
    for (final activity in result.activities) {
      final cluster = activity.routeCluster;
      if (cluster == null) continue;
      if (cluster != current) {
        count++;
        current = cluster;
      }
    }
    return count;
  }

  /// `backtrackingMinutes` domain'de sürekli bir ceza puanıdır (yön
  /// tersine dönüşü + aynı hat ters yön maliyetinin ağırlıklı toplamı),
  /// literal dakika değil. Section A'nın `0|1|2` şiddet skalasına göre
  /// eşiklenir: birkaç ufak dönüş (gerçek dağınık POI'lerde kaçınılmaz)
  /// "0" sayılır; yalnızca belirgin zikzak "1", ciddi geri dönüş "2" olur.
  int _backtrackingSeverity(double rawPenalty) {
    if (rawPenalty >= 40) return 2;
    if (rawPenalty >= 15) return 1;
    return 0;
  }

  bool _hasMealInWindow(OptimizationResult result, int startMin, int endMin) {
    for (final activity in result.activities) {
      if (activity.activity.category != 'meal') continue;
      final start =
          activity.startTime.hour * 60 + activity.startTime.minute;
      final end = activity.endTime.hour * 60 + activity.endTime.minute;
      if (start >= startMin && end <= endMin) return true;
    }
    return false;
  }
}
