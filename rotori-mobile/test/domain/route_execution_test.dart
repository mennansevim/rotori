import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/domain/itinerary_optimizer.dart';
import 'package:rotori/domain/route_execution.dart';
import 'package:rotori/domain/route_matrix.dart';
import 'package:rotori/domain/types.dart';

void main() {
  test('optimizer bacaklarını bilgi kaybetmeden saha modeline dönüştürür', () {
    final result = OptimizationResult.success(
      activities: const [],
      legs: [
        _leg(
          from: 'hotel',
          to: 'sensoji',
          departureHour: 8,
          lineId: 'ginza-line',
          directionId: 'asakusa-bound',
        ),
        _leg(
          from: 'sensoji',
          to: 'skytree',
          departureHour: 10,
          estimated: true,
        ),
        _leg(
          from: 'skytree',
          to: 'hotel',
          departureHour: 18,
        ),
      ],
      metrics: _metrics,
      warnings: const [],
      optimizationChanges: const [],
    );

    final legs = const RouteExecutionBuilder().build(
      result: result,
      startLocationId: 'hotel',
      endLocationId: 'hotel',
      locationNames: const {
        'hotel': 'Otel',
        'sensoji': 'Senso-ji',
        'skytree': 'Tokyo Skytree',
      },
    );

    expect(legs, hasLength(3));
    expect(legs.first.kind, RouteExecutionLegKind.departure);
    expect(legs[1].kind, RouteExecutionLegKind.betweenStops);
    expect(legs.last.kind, RouteExecutionLegKind.returnToBase);
    expect(legs.first.fromName, 'Otel');
    expect(legs.first.toName, 'Senso-ji');
    expect(legs.first.lineId, 'ginza-line');
    expect(legs.first.directionId, 'asakusa-bound');
    expect(legs.first.complexityPenalty, 2.5);
    expect(legs.first.partyTotalCostYen, 420);
    expect(legs[1].isEstimated, isTrue);
    expect(legs[1].dataQuality, RouteExecutionDataQuality.estimated);
  });

  test('başarısız optimizer sonucu saha adımı üretmez', () {
    final result = OptimizationResult.failure(
      const OptimizationFailure(
        code: OptimizationFailureCode.noFeasibleRoute,
        message: 'Uygulanabilir rota yok.',
      ),
    );

    final legs = const RouteExecutionBuilder().build(
      result: result,
      startLocationId: 'hotel',
      endLocationId: 'hotel',
      locationNames: const {},
    );

    expect(legs, isEmpty);
  });

  test('versioned rota snapshot JSON turunda bütün bacakları korur', () {
    final legs = const RouteExecutionBuilder().build(
      result: OptimizationResult.success(
        activities: const [],
        legs: [
          _leg(
            from: 'hotel',
            to: 'sensoji',
            departureHour: 8,
            lineId: 'G',
            directionId: 'Asakusa',
          ),
        ],
        metrics: _metrics,
        warnings: const [],
        optimizationChanges: const [],
      ),
      startLocationId: 'hotel',
      endLocationId: 'hotel',
      locationNames: const {'hotel': 'Otel', 'sensoji': 'Senso-ji'},
    );
    final snapshot = RouteExecutionSnapshot(
      planId: 'plan-1',
      dayNumber: 2,
      planVersion: 7,
      activityHash: 'abc123',
      matrixVersion: 'matrix-v4',
      generatedAt: DateTime.utc(2026, 8, 10, 12),
      profile: RouteOptimizationProfile.leastWalking,
      providerIds: const ['test-provider'],
      legs: legs,
    );

    final decoded = RouteExecutionSnapshot.tryFromJson(snapshot.toJson());

    expect(decoded, isNotNull);
    expect(decoded!.schemaVersion, RouteExecutionSnapshot.currentSchemaVersion);
    expect(decoded.activityHash, 'abc123');
    expect(decoded.profile, RouteOptimizationProfile.leastWalking);
    expect(decoded.providerIds, ['test-provider']);
    expect(decoded.legs.single.lineId, 'G');
    expect(decoded.legs.single.directionId, 'Asakusa');
    expect(decoded.legs.single.departureTime, DateTime(2026, 10, 15, 8));
  });

  test(
      'eski plan snapshot olmadan açılır, aktivite değişikliği snapshotı siler',
      () {
    final oldDay = DayPlan.fromJson({
      'dayNumber': 1,
      'date': '2026-10-15',
      'theme': 'Tokyo',
      'items': const <Object>[],
    });
    expect(oldDay.routeExecutionSnapshot, isNull);

    final snapshot = RouteExecutionSnapshot(
      planId: 'plan-1',
      dayNumber: 1,
      planVersion: 1,
      activityHash: 'hash',
      matrixVersion: 'matrix-v1',
      generatedAt: DateTime.utc(2026, 8, 10),
      profile: RouteOptimizationProfile.balanced,
      legs: const [],
    );
    final dayWithSnapshot = DayPlan(
      dayNumber: 1,
      date: '2026-10-15',
      theme: 'Tokyo',
      routeExecutionSnapshot: snapshot,
      items: [TimelineItem(id: 'a', title: 'A')],
    );

    expect(dayWithSnapshot.copyWith(theme: 'Yeni').routeExecutionSnapshot,
        same(snapshot));
    expect(
      dayWithSnapshot.copyWith(
          items: [TimelineItem(id: 'b', title: 'B')]).routeExecutionSnapshot,
      isNull,
    );
    expect(
      RouteExecutionSnapshot.tryFromJson({
        ...snapshot.toJson(),
        'schemaVersion': 999,
      }),
      isNull,
    );
  });
}

RouteLeg _leg({
  required String from,
  required String to,
  required int departureHour,
  String? lineId,
  String? directionId,
  bool estimated = false,
}) {
  final departure = DateTime(2026, 10, 15, departureHour);
  return RouteLeg(
    fromLocationId: from,
    toLocationId: to,
    mode: TransportMode.metro,
    departureTime: departure,
    arrivalTime: departure.add(const Duration(minutes: 24)),
    travelDurationMinutes: 24,
    walkingDurationMinutes: 6,
    waitingDurationMinutes: 4,
    transferCount: 1,
    estimatedCostYen: 210,
    bufferMinutes: 5,
    reliabilityScore: .91,
    isEstimated: estimated,
    rideMinutes: 14,
    accessMinutes: 6,
    transitWaitMinutes: 4,
    scheduleIdleMinutes: 3,
    costPerPersonYen: 210,
    partyTotalCostYen: 420,
    fareBasis: FareBasis.perPerson,
    lineId: lineId,
    directionId: directionId,
    complexityPenalty: 2.5,
    providerId: 'test-provider',
  );
}

const _metrics = OptimizationMetrics(
  totalTravelMinutes: 72,
  totalWalkingMinutes: 18,
  totalWaitingMinutes: 12,
  totalTransferCount: 3,
  estimatedTransportCostYen: 630,
  backtrackingMinutes: 0,
  routeEfficiencyScore: 90,
  score: 100,
  evaluatedStateCount: 4,
  prunedStateCount: 1,
  beamWidth: 6,
);
