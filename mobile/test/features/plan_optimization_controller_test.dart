import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:japan_trip/data/route_matrix_remote.dart';
import 'package:japan_trip/domain/itinerary_optimizer.dart';
import 'package:japan_trip/domain/route_matrix.dart';
import 'package:japan_trip/domain/types.dart';
import 'package:japan_trip/features/plans/plan_optimization_controller.dart';

void main() {
  const hotel = TripLocation(
    id: 'hotel',
    name: 'Otel',
    latitude: 35,
    longitude: 139,
  );
  final matrix = RouteMatrix(
    version: 'matrix-v1',
    entries: [
      _entry('hotel', 'a', 10),
      _entry('hotel', 'b', 50),
      _entry('a', 'b', 10),
      _entry('b', 'a', 50),
      _entry('a', 'hotel', 10),
      _entry('b', 'hotel', 10),
    ],
  );

  test('ön izleme planı kaydetmeden optimize eder, onayda kalıcılaştırır',
      () async {
    final repository = FakeRouteMatrixRepository(matrix);
    final container = ProviderContainer(
      overrides: [
        routeMatrixRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    Trip? persisted;

    await container
        .read(planOptimizationControllerProvider.notifier)
        .optimizeDay(_input(hotel));

    final preview =
        container.read(planOptimizationControllerProvider).valueOrNull;
    expect(preview, isNotNull);
    expect(preview!.originalTrip.days.single.items.map((item) => item.id),
        ['b', 'a']);
    expect(preview.optimizedTrip.days.single.items.map((item) => item.id),
        ['a', 'b']);
    expect(persisted, isNull);
    expect(preview.before.totalTravelMinutes, 110);
    expect(preview.after.totalTravelMinutes, 30);

    final confirmed = await container
        .read(planOptimizationControllerProvider.notifier)
        .confirm((trip) async => persisted = trip);

    expect(confirmed, isTrue);
    expect(persisted?.days.single.items.map((item) => item.id), ['a', 'b']);
    expect(
      container
          .read(planOptimizationControllerProvider)
          .valueOrNull
          ?.isConfirmed,
      isTrue,
    );
  });

  test('aynı plan sürümü ve rota matrisi için optimize sonucu cache kullanır',
      () async {
    final repository = FakeRouteMatrixRepository(matrix);
    final container = ProviderContainer(
      overrides: [
        routeMatrixRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    final controller =
        container.read(planOptimizationControllerProvider.notifier);

    await controller.optimizeDay(_input(hotel));
    expect(
      container.read(planOptimizationControllerProvider).valueOrNull?.fromCache,
      isFalse,
    );

    await controller.optimizeDay(_input(hotel));
    expect(
      container.read(planOptimizationControllerProvider).valueOrNull?.fromCache,
      isTrue,
    );
    expect(repository.callCount, 2);
  });

  test('koordinatı eksik aktivite rota API çağrısından önce reddedilir',
      () async {
    final repository = FakeRouteMatrixRepository(matrix);
    final container = ProviderContainer(
      overrides: [
        routeMatrixRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    final input = _input(hotel);
    input.trip.days.single.items.first.lat = null;

    await container
        .read(planOptimizationControllerProvider.notifier)
        .optimizeDay(input);

    expect(
      container.read(planOptimizationControllerProvider).hasError,
      isTrue,
    );
    expect(repository.callCount, 0);
  });

  test('rota backend yokken koordinat tahminiyle önizleme üretir', () async {
    final container = ProviderContainer(
      overrides: [
        routeMatrixRepositoryProvider
            .overrideWithValue(_UnavailableRepository()),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(planOptimizationControllerProvider.notifier)
        .optimizeDay(_input(hotel));

    final preview =
        container.read(planOptimizationControllerProvider).valueOrNull;
    expect(preview, isNotNull);
    expect(preview!.after.isComplete, isTrue);
    expect(preview.result.activities.map((activity) => activity.activityId),
        containsAll(<String>['a', 'b']));
    expect(preview.result.legs.every((leg) => leg.isEstimated), isTrue);
  });

  test('tahmini optimizasyon sabit aktivitenin saatini değiştirmez', () async {
    final container = ProviderContainer(
      overrides: [
        routeMatrixRepositoryProvider
            .overrideWithValue(_UnavailableRepository()),
      ],
    );
    addTearDown(container.dispose);
    final input = _input(hotel);
    final fixed = input.trip.days.single.items.first;
    fixed
      ..time = '14:00'
      ..scheduledTime = '14:00'
      ..fixedStartTime = '14:00'
      ..fixedEndTime = '15:00'
      ..canChangeTime = false
      ..canReorder = false;

    await container
        .read(planOptimizationControllerProvider.notifier)
        .optimizeDay(input);

    final preview =
        container.read(planOptimizationControllerProvider).valueOrNull;
    expect(preview, isNotNull);
    final optimizedFixed = preview!.optimizedTrip.days.single.items
        .firstWhere((item) => item.id == fixed.id);
    expect(optimizedFixed.time, '14:00');
    expect(optimizedFixed.scheduledTime, '14:00');
    expect(optimizedFixed.fixedStartTime, '14:00');
    expect(optimizedFixed.fixedEndTime, '15:00');
  });
}

class _UnavailableRepository implements RouteMatrixRepository {
  @override
  Future<RouteMatrix> getRouteMatrix({
    required List<TripLocation> locations,
    required DateTime day,
    required RoutePreferences preferences,
  }) {
    throw const RouteMatrixFailure(
      kind: RouteMatrixFailureKind.unavailable,
      message: 'test backend unavailable',
      retryable: false,
    );
  }
}

DayOptimizationInput _input(TripLocation hotel) {
  final day = DateTime(2026, 9, 1);
  return DayOptimizationInput(
    trip: Trip(
      id: 'trip-1',
      slug: 'trip-1',
      title: 'Tokyo',
      timezone: 'Asia/Tokyo',
      tripStart: '2026-09-01',
      tripEnd: '2026-09-01',
      flights: TripFlights(),
      preferences: TripPreferences(
        travelDates: TravelDates(
          start: '2026-09-01',
          end: '2026-09-01',
        ),
        pace: Pace.moderate,
      ),
      days: [
        DayPlan(
          dayNumber: 1,
          date: '2026-09-01',
          theme: 'Tokyo',
          items: [
            TimelineItem(
              id: 'b',
              title: 'Uzak başlangıç',
              lat: 35.2,
              lng: 139.2,
              durationMin: 60,
            ),
            TimelineItem(
              id: 'a',
              title: 'Yakın başlangıç',
              lat: 35.1,
              lng: 139.1,
              durationMin: 60,
            ),
          ],
        ),
      ],
    ),
    dayNumber: 1,
    planVersion: 1,
    constraints: DayRouteConstraints(
      startLocation: hotel,
      endLocation: hotel,
      availableStartTime: DateTime(day.year, day.month, day.day, 9),
      availableEndTime: DateTime(day.year, day.month, day.day, 20),
    ),
  );
}

RouteMatrixEntry _entry(String from, String to, int minutes) {
  return RouteMatrixEntry(
    fromLocationId: from,
    toLocationId: to,
    options: [
      TransportOption(
        mode: TransportMode.walking,
        doorToDoorMinutes: minutes,
        walkingMinutes: minutes,
        waitingMinutes: 0,
        transferCount: 0,
        estimatedCostYen: 0,
        reliabilityScore: 1,
      ),
    ],
  );
}
