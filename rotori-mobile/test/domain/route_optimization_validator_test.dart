import 'package:flutter_test/flutter_test.dart';
import 'package:japan_trip/domain/itinerary_optimizer.dart';
import 'package:japan_trip/domain/route_matrix.dart';
import 'package:japan_trip/domain/route_optimization_validator.dart';

void main() {
  const validator = RouteOptimizationValidator();
  final day = DateTime(2026, 8, 3);
  const hotel = TripLocation(
    id: 'hotel',
    name: 'Hotel',
    latitude: 0,
    longitude: 0,
  );
  const poi = TripLocation(
    id: 'poi',
    name: 'POI',
    latitude: 1,
    longitude: 1,
  );
  final activity = OptimizationActivity(
    id: 'activity',
    name: 'Activity',
    day: day,
    location: poi,
    durationMinutes: 60,
    openingTime: DateTime(2026, 8, 3, 9),
    closingTime: DateTime(2026, 8, 3, 18),
  );
  final matrix = RouteMatrix(entries: [
    _entry('hotel', 'poi', 20),
    _entry('poi', 'hotel', 25),
  ]);
  final request = OptimizationRequest(
    activities: [activity],
    routeMatrix: matrix,
    constraints: DayRouteConstraints(
      startLocation: hotel,
      endLocation: hotel,
      availableStartTime: DateTime(2026, 8, 3, 9),
      availableEndTime: DateTime(2026, 8, 3, 20),
    ),
  );

  test('geçerli optimizer sonucunu kabul eder', () async {
    final result = await const BeamSearchItineraryOptimizer().optimize(request);
    expect(result.isSuccess, isTrue);
    expect(validator.validate(request, result), isEmpty);
  });

  test('çalışma saati ve aggregate metric ihlalini yakalar', () {
    final inbound = _leg('hotel', 'poi', DateTime(2026, 8, 3, 18), 20);
    final returned = _leg('poi', 'hotel', DateTime(2026, 8, 3, 20), 25);
    final result = OptimizationResult.success(
      activities: [
        ScheduledActivity(
          activity: activity,
          order: 1,
          startTime: DateTime(2026, 8, 3, 18, 20),
          endTime: DateTime(2026, 8, 3, 19, 20),
          inboundLeg: inbound,
          optimizationReason: 'test',
        ),
      ],
      legs: [inbound, returned],
      metrics: const OptimizationMetrics(
        totalTravelMinutes: 0,
        totalWalkingMinutes: 0,
        totalWaitingMinutes: 0,
        totalTransferCount: 0,
        estimatedTransportCostYen: 0,
        backtrackingMinutes: 0,
        routeEfficiencyScore: 0,
        score: 0,
        evaluatedStateCount: 1,
        prunedStateCount: 0,
        beamWidth: 7,
      ),
      warnings: const [],
      optimizationChanges: const [],
    );
    final codes =
        validator.validate(request, result).map((issue) => issue.code).toSet();
    expect(codes, contains(RouteValidationIssueCode.outsideOpeningWindow));
    expect(codes, contains(RouteValidationIssueCode.returnAfterDayEnd));
    expect(codes, contains(RouteValidationIssueCode.metricMismatch));
  });

  test('schedule ve dropping çakışmasını yakalar', () async {
    final solved = await const BeamSearchItineraryOptimizer().optimize(request);
    final result = OptimizationResult.success(
      activities: solved.activities,
      legs: solved.legs,
      metrics: solved.metrics!,
      warnings: solved.warnings,
      optimizationChanges: solved.optimizationChanges,
      droppedActivityIds: const ['activity'],
    );
    final codes =
        validator.validate(request, result).map((issue) => issue.code).toSet();
    expect(codes, contains(RouteValidationIssueCode.scheduledAndDropped));
  });
}

RouteMatrixEntry _entry(String from, String to, int minutes) =>
    RouteMatrixEntry(
      fromLocationId: from,
      toLocationId: to,
      options: [
        TransportOption(
          mode: TransportMode.train,
          doorToDoorMinutes: minutes,
          walkingMinutes: 4,
          waitingMinutes: 2,
          transferCount: 0,
          estimatedCostYen: 200,
          reliabilityScore: .9,
        ),
      ],
    );

RouteLeg _leg(String from, String to, DateTime departure, int minutes) =>
    RouteLeg(
      fromLocationId: from,
      toLocationId: to,
      mode: TransportMode.train,
      departureTime: departure,
      arrivalTime: departure.add(Duration(minutes: minutes)),
      travelDurationMinutes: minutes,
      walkingDurationMinutes: 4,
      waitingDurationMinutes: 2,
      transferCount: 0,
      estimatedCostYen: 200,
      bufferMinutes: 0,
      reliabilityScore: .9,
      isEstimated: false,
    );
