import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/domain/itinerary_optimizer.dart';
import 'package:rotori/domain/route_matrix.dart';
import 'package:rotori/domain/route_optimization_validator.dart';

final _day = DateTime(2026, 10, 15);

void main() {
  test('rota refactor sözleşmesi: deterministik, doğrulanmış ve kayıpsızdır',
      () async {
    const hotel = TripLocation(
      id: 'hotel',
      name: 'Otel',
      latitude: 35.68,
      longitude: 139.76,
      clusterId: 'base',
    );
    const firstStop = TripLocation(
      id: 'sensoji',
      name: 'Senso-ji',
      latitude: 35.71,
      longitude: 139.79,
      clusterId: 'east',
    );
    const reservation = TripLocation(
      id: 'skytree',
      name: 'Tokyo Skytree',
      latitude: 35.71,
      longitude: 139.81,
      clusterId: 'east',
    );

    final request = OptimizationRequest(
      activities: [
        OptimizationActivity(
          id: firstStop.id,
          name: firstStop.name,
          day: _day,
          location: firstStop,
          durationMinutes: 60,
          minimumDurationMinutes: 60,
          priority: ActivityPriority.preferred,
        ),
        OptimizationActivity(
          id: reservation.id,
          name: reservation.name,
          day: _day,
          location: reservation,
          durationMinutes: 60,
          minimumDurationMinutes: 60,
          fixedStartTime: DateTime(2026, 10, 15, 14),
          fixedEndTime: DateTime(2026, 10, 15, 15),
          isFixed: true,
          hasReservation: true,
          priority: ActivityPriority.mustDo,
        ),
      ],
      routeMatrix: _matrix([hotel, firstStop, reservation]),
      constraints: DayRouteConstraints(
        startLocation: hotel,
        endLocation: hotel,
        availableStartTime: DateTime(2026, 10, 15, 9),
        availableEndTime: DateTime(2026, 10, 15, 20),
      ),
    );
    const optimizer = BeamSearchItineraryOptimizer();

    final first = await optimizer.optimize(request);
    final second = await optimizer.optimize(request);

    expect(first.isSuccess, isTrue, reason: first.failure?.message);
    expect(second.isSuccess, isTrue, reason: second.failure?.message);
    expect(first.metrics?.beamWidth, 6);
    expect(first.droppedActivityIds, isEmpty);
    expect(first.activities.map((item) => item.activityId),
        second.activities.map((item) => item.activityId));
    expect(first.legs.map(_semanticLeg), second.legs.map(_semanticLeg));
    expect(first.metrics?.score, second.metrics?.score);
    expect(first.legs, hasLength(first.activities.length + 1));
    expect(first.legs.last.toLocationId, hotel.id);
    expect(first.legs.every((leg) => leg.lineId != null), isTrue);
    expect(first.legs.every((leg) => leg.directionId != null), isTrue);
    expect(first.legs.every((leg) => leg.complexityPenalty == 1.5), isTrue);

    final fixed = first.activities.singleWhere(
      (item) => item.activityId == reservation.id,
    );
    expect(fixed.startTime, DateTime(2026, 10, 15, 14));
    expect(fixed.endTime, DateTime(2026, 10, 15, 15));
    expect(
        const RouteOptimizationValidator().validate(request, first), isEmpty);
  });
}

String _semanticLeg(RouteLeg leg) => [
      leg.fromLocationId,
      leg.toLocationId,
      leg.mode.name,
      leg.departureTime.toIso8601String(),
      leg.arrivalTime.toIso8601String(),
      leg.lineId,
      leg.directionId,
    ].join('|');

RouteMatrix _matrix(List<TripLocation> locations) {
  final entries = <RouteMatrixEntry>[];
  for (final from in locations) {
    for (final to in locations) {
      if (from.id == to.id) continue;
      final sameCluster = from.clusterId == to.clusterId;
      final minutes = sameCluster ? 12 : 24;
      entries.add(
        RouteMatrixEntry(
          fromLocationId: from.id,
          toLocationId: to.id,
          options: [
            TransportOption(
              mode: sameCluster ? TransportMode.walking : TransportMode.metro,
              doorToDoorMinutes: minutes,
              walkingMinutes: sameCluster ? minutes : 6,
              waitingMinutes: sameCluster ? 0 : 4,
              transferCount: 0,
              estimatedCostYen: sameCluster ? 0 : 210,
              reliabilityScore: .95,
              lineId: 'line-${from.id}-${to.id}',
              directionId: 'toward-${to.id}',
              complexityPenalty: 1.5,
              rideMinutes: sameCluster ? 0 : 14,
              accessMinutes: sameCluster ? minutes : 6,
              transitWaitMinutes: sameCluster ? 0 : 4,
              providerId: 'contract-fixture',
            ),
          ],
        ),
      );
    }
  }
  return RouteMatrix(version: 'contract-v1', entries: entries);
}
