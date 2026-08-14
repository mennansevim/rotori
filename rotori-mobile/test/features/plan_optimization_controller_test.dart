import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/data/route_matrix_remote.dart';
import 'package:rotori/domain/itinerary_optimizer.dart';
import 'package:rotori/domain/japan_transit_realism.dart';
import 'package:rotori/domain/luggage_logistics.dart';
import 'package:rotori/domain/plan_field_signals.dart';
import 'package:rotori/domain/route_execution.dart';
import 'package:rotori/domain/route_matrix.dart';
import 'package:rotori/domain/types.dart';
import 'package:rotori/features/plans/plan_optimization_controller.dart';

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

  group('improvesRoute — kazanç yoksa uygulanacak bir şey yok', () {
    // Sayfa her koşulda "Uygula" sunuyordu; gün zaten en iyi sıradayken
    // before/after birebir aynı çıkıyor ve kullanıcı boş bir işlem uygulayıp
    // planı "optimize edilmiş" diye işaretliyordu.
    PlanOptimizationPreview previewWith({
      required RouteSummary before,
      required RouteSummary after,
    }) {
      final trip = _tripWith();
      return PlanOptimizationPreview(
        originalTrip: trip,
        optimizedTrip: trip,
        dayNumber: 1,
        before: before,
        after: after,
        result: OptimizationResult.success(
          activities: const [],
          legs: const [],
          metrics: const OptimizationMetrics(
            totalTravelMinutes: 0,
            totalWalkingMinutes: 0,
            totalWaitingMinutes: 0,
            totalTransferCount: 0,
            estimatedTransportCostYen: 0,
            backtrackingMinutes: 0,
            routeEfficiencyScore: 1,
            score: 1,
            evaluatedStateCount: 1,
            prunedStateCount: 0,
            beamWidth: 1,
          ),
          warnings: const [],
          optimizationChanges: const [],
        ),
        cacheKey: 'k',
      );
    }

    RouteSummary summary({
      int travel = 60,
      int walking = 20,
      int transfers = 2,
      int cost = 1000,
    }) =>
        RouteSummary(
          totalTravelMinutes: travel,
          totalWalkingMinutes: walking,
          totalTransferCount: transfers,
          estimatedTransportCostYen: cost,
          isComplete: true,
        );

    test('birebir aynı özet → kazanç yok', () {
      final p = previewWith(before: summary(), after: summary());
      expect(p.improvesRoute, isFalse);
    });

    test('ulaşım süresi kısalıyorsa kazanç var', () {
      final p = previewWith(before: summary(), after: summary(travel: 45));
      expect(p.improvesRoute, isTrue);
    });

    test('ulaşım süresi UZUYORSA kazanç yok', () {
      final p = previewWith(before: summary(), after: summary(travel: 75));
      expect(p.improvesRoute, isFalse);
    });

    test('süre eşitse sırayla yürüyüş, aktarma, maliyete bakılır', () {
      expect(
        previewWith(before: summary(), after: summary(walking: 10)).improvesRoute,
        isTrue,
      );
      expect(
        previewWith(before: summary(), after: summary(transfers: 1))
            .improvesRoute,
        isTrue,
      );
      expect(
        previewWith(before: summary(), after: summary(cost: 800)).improvesRoute,
        isTrue,
      );
      // Yürüyüş kötüleşirken maliyet düşüyorsa: önce yürüyüşe bakılır → kazanç yok.
      expect(
        previewWith(before: summary(), after: summary(walking: 40, cost: 500))
            .improvesRoute,
        isFalse,
      );
    });
  });

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
    expect(preview.executionLegs, hasLength(3));
    expect(preview.executionLegs.first.kind, RouteExecutionLegKind.departure);
    expect(preview.executionLegs.last.kind, RouteExecutionLegKind.returnToBase);

    final confirmed = await container
        .read(planOptimizationControllerProvider.notifier)
        .confirm((trip) async => persisted = trip);

    expect(confirmed, isTrue);
    expect(persisted?.days.single.items.map((item) => item.id), ['a', 'b']);
    expect(persisted?.days.single.routeExecutionSnapshot, isNotNull);
    expect(
      persisted?.days.single.routeExecutionSnapshot?.matrixVersion,
      'matrix-v1',
    );
    expect(
      persisted?.days.single.routeExecutionSnapshot?.legs,
      hasLength(3),
    );
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

  test('field-aware infeasible gün saha kapılarını atlayan fallback üretmez',
      () async {
    final repository = FakeRouteMatrixRepository(matrix);
    final container = ProviderContainer(
      overrides: [
        routeMatrixRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(planOptimizationControllerProvider.notifier)
        .optimizeDay(_impossibleInput(hotel));

    final state = container.read(planOptimizationControllerProvider);
    expect(state.hasError, isTrue);
    expect(state.error, isA<PlanOptimizationException>());
  });

  test('üretim controllerı gün sinyallerinden FieldRealityContext kurar',
      () async {
    final capturing = _CapturingOptimizer();
    final container = ProviderContainer(
      overrides: [
        routeMatrixRepositoryProvider
            .overrideWithValue(FakeRouteMatrixRepository(matrix)),
        itineraryOptimizerProvider.overrideWithValue(capturing),
      ],
    );
    addTearDown(container.dispose);
    final input = _input(hotel);
    final day = input.trip.days.single;
    final first = day.items.first;
    day.items[0] = TimelineItem(
      id: first.id,
      title: first.title,
      lat: first.lat,
      lng: first.lng,
      durationMin: first.durationMin,
      cityId: 'Tokyo',
      closure: const ClosureSignals(
        weeklyClosedWeekdays: [DateTime.monday],
      ),
    );
    day.cityTransition = const CityTransitionPlan(
      fromCity: 'Osaka',
      toCity: 'Tokyo',
      mode: 'shinkansen',
      railPass: 'nationalJrPass',
    );
    day.luggage = const LuggageSignals(
      strategy: 'coinLocker',
      size: 'medium',
      bagCount: 2,
      arrivalHandlingMin: 20,
      retrievalMin: 10,
      advisories: ['hotelDetourExpensive'],
    );

    await container
        .read(planOptimizationControllerProvider.notifier)
        .optimizeDay(input);

    final request = capturing.lastRequest;
    expect(request, isNotNull);
    expect(request!.field, isNotNull);
    expect(request.field!.cityId, 'Tokyo');
    expect(
      request.field!.traveller.railPass,
      RailPassType.nationalJrPass,
    );
    expect(request.field!.traveller.luggageSize, LuggageSize.medium);
    expect(request.field!.traveller.bagCount, 2);
    expect(
      request.field!.luggagePlan?.strategy,
      LuggageHandlingStrategy.coinLocker,
    );
    expect(request.activities.first.closureRule, isNotNull);
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

  test('enjekte edilen rota kaynağı yokken offline paket önizleme üretir',
      () async {
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

  test('kullanıcı kilidi optimizasyonda gün ve saati korur', () async {
    // Kullanıcının kilitlediği durak "bileti alınmış" sayılır: optimizasyon
    // onu ne taşır, ne saatini değiştirir, ne de yer açmak için düşürür.
    final repository = FakeRouteMatrixRepository(matrix);
    final container = ProviderContainer(
      overrides: [
        routeMatrixRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    final input = _input(hotel);
    final pinned = input.trip.days.single.items.first;
    pinned
      ..time = '14:00'
      ..scheduledTime = '14:00';
    pinned.pinByUser(reason: 'Bilet alındı');

    await container
        .read(planOptimizationControllerProvider.notifier)
        .optimizeDay(input);

    final preview =
        container.read(planOptimizationControllerProvider).valueOrNull;
    expect(preview, isNotNull);

    final stops = preview!.optimizedTrip.days.single.items;
    // Düşürülmemiş.
    expect(
      stops.where((item) => item.id == pinned.id),
      hasLength(1),
      reason: 'kilitli durak optimizasyonda düşürüldü',
    );
    final optimized = stops.firstWhere((item) => item.id == pinned.id);
    expect(optimized.time, '14:00');
    expect(optimized.scheduledTime, '14:00');
    // Kilit optimizasyon turundan sağ çıkar.
    expect(optimized.isUserPinned, isTrue);
    expect(optimized.canReorder, isFalse);
  });

  test('öğle yemeği erken başlayan günde bile öğlen penceresine planlanır',
      () async {
    final repository = FakeRouteMatrixRepository(_mealMatrix);
    final container = ProviderContainer(
      overrides: [
        routeMatrixRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(planOptimizationControllerProvider.notifier)
        .optimizeDay(_mealInput(hotel));

    final preview =
        container.read(planOptimizationControllerProvider).valueOrNull;
    expect(preview, isNotNull);
    final lunch = preview!.optimizedTrip.days.single.items
        .firstWhere((item) => item.id == 'lunch');
    final minutes = _minutes(lunch.time);
    // Öğle yemeği 11:30 açılış penceresine çekilmeli; sabahın köründe
    // (06:xx) planlanmamalı.
    expect(minutes, greaterThanOrEqualTo(11 * 60 + 30),
        reason: 'öğle yemeği ${lunch.time} — çok erken planlandı');
    expect(minutes, lessThanOrEqualTo(14 * 60 + 30));
  });

  test('optimizasyon sonucu sabit olmayan saatler 5 dakika katına snap edilir',
      () async {
    final repository = FakeRouteMatrixRepository(_nonGridMatrix);
    final container = ProviderContainer(
      overrides: [
        routeMatrixRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(planOptimizationControllerProvider.notifier)
        .optimizeDay(_nonGridInput(hotel));

    final preview =
        container.read(planOptimizationControllerProvider).valueOrNull;
    expect(preview, isNotNull);
    final nonFixed = preview!.optimizedTrip.days.single.items
        .where((item) => !item.isFixed)
        .toList(growable: false);
    expect(nonFixed, isNotEmpty);
    for (final item in nonFixed) {
      expect(_minutes(item.time) % 5, 0,
          reason: '${item.title} saati ${item.time} — 5 dk katı değil');
    }
  });

  test(
      'başlığında öğle geçen aktivite akşam saatinde olsa da öğle penceresine çekilir',
      () async {
    final repository = FakeRouteMatrixRepository(_mealMatrix);
    final container = ProviderContainer(
      overrides: [
        routeMatrixRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(planOptimizationControllerProvider.notifier)
        .optimizeDay(_mealTitleInput(hotel));

    final preview =
        container.read(planOptimizationControllerProvider).valueOrNull;
    expect(preview, isNotNull);
    final lunch = preview!.optimizedTrip.days.single.items
        .firstWhere((item) => item.id == 'lunch');
    final minutes = _minutes(lunch.time);
    expect(minutes, greaterThanOrEqualTo(11 * 60 + 30),
        reason: 'öğle aktivitesi ${lunch.time} — öğlen aralığına çekilmedi');
    expect(minutes, lessThanOrEqualTo(14 * 60 + 30));
  });
}

int _minutes(String? hhmm) {
  if (hhmm == null) return -1;
  final parts = hhmm.split(':');
  return int.parse(parts[0]) * 60 + int.parse(parts[1]);
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

class _CapturingOptimizer implements ItineraryOptimizer {
  OptimizationRequest? lastRequest;

  @override
  Future<OptimizationResult> optimize(OptimizationRequest request) {
    lastRequest = request;
    return const BeamSearchItineraryOptimizer().optimize(request);
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

DayOptimizationInput _mealInput(TripLocation hotel) {
  final day = DateTime(2026, 9, 1);
  return DayOptimizationInput(
    trip: Trip(
      id: 'trip-meal',
      slug: 'trip-meal',
      title: 'Nara',
      timezone: 'Asia/Tokyo',
      tripStart: '2026-09-01',
      tripEnd: '2026-09-01',
      flights: TripFlights(),
      preferences: TripPreferences(
        travelDates: TravelDates(start: '2026-09-01', end: '2026-09-01'),
        pace: Pace.moderate,
      ),
      days: [
        DayPlan(
          dayNumber: 1,
          date: '2026-09-01',
          theme: 'Nara',
          items: [
            // Öğle yemeği coğrafi olarak en kuzeyde — düzeltme olmadan
            // nearest-neighbor onu ilk sıraya alıp 06:xx'e planlardı.
            TimelineItem(
              id: 'lunch',
              title: 'Öğle yemeği',
              lat: 35.9,
              lng: 139.5,
              durationMin: 60,
              kind: TimelineItemKind.meal,
              time: '13:00',
              scheduledTime: '13:00',
            ),
            TimelineItem(
              id: 'spot1',
              title: 'Isuien Bahçesi',
              lat: 35.5,
              lng: 139.5,
              durationMin: 90,
              kind: TimelineItemKind.activity,
            ),
            TimelineItem(
              id: 'spot2',
              title: 'Todai-ji',
              lat: 35.2,
              lng: 139.5,
              durationMin: 90,
              kind: TimelineItemKind.activity,
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
      // Gün 06:00'da başlar — gerçek uygulamadaki gibi.
      availableStartTime: DateTime(day.year, day.month, day.day, 6),
      availableEndTime: DateTime(day.year, day.month, day.day, 23),
    ),
  );
}

DayOptimizationInput _mealTitleInput(TripLocation hotel) {
  final day = DateTime(2026, 9, 1);
  return DayOptimizationInput(
    trip: Trip(
      id: 'trip-meal-title',
      slug: 'trip-meal-title',
      title: 'Nara',
      timezone: 'Asia/Tokyo',
      tripStart: '2026-09-01',
      tripEnd: '2026-09-01',
      flights: TripFlights(),
      preferences: TripPreferences(
        travelDates: TravelDates(start: '2026-09-01', end: '2026-09-01'),
        pace: Pace.moderate,
      ),
      days: [
        DayPlan(
          dayNumber: 1,
          date: '2026-09-01',
          theme: 'Nara',
          items: [
            // Başlık öğle yemeği dediği için 18:43'te kalsa da optimizer
            // bunu öğlen penceresine taşımalıdır.
            TimelineItem(
              id: 'lunch',
              title: 'Öğle yemeği molası',
              lat: 35.9,
              lng: 139.5,
              durationMin: 60,
              kind: TimelineItemKind.activity,
              time: '18:43',
              scheduledTime: '18:43',
            ),
            TimelineItem(
              id: 'spot1',
              title: 'Isuien Bahçesi',
              lat: 35.5,
              lng: 139.5,
              durationMin: 90,
              kind: TimelineItemKind.activity,
            ),
            TimelineItem(
              id: 'spot2',
              title: 'Todai-ji',
              lat: 35.2,
              lng: 139.5,
              durationMin: 90,
              kind: TimelineItemKind.activity,
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
      availableStartTime: DateTime(day.year, day.month, day.day, 6),
      availableEndTime: DateTime(day.year, day.month, day.day, 23),
    ),
  );
}

DayOptimizationInput _impossibleInput(TripLocation hotel) {
  final day = DateTime(2026, 9, 1);
  return DayOptimizationInput(
    trip: Trip(
      id: 'trip-impossible',
      slug: 'trip-impossible',
      title: 'Kyoto',
      timezone: 'Asia/Tokyo',
      tripStart: '2026-09-01',
      tripEnd: '2026-09-01',
      flights: TripFlights(),
      preferences: TripPreferences(
        travelDates: TravelDates(start: '2026-09-01', end: '2026-09-01'),
        pace: Pace.moderate,
      ),
      days: [
        DayPlan(
          dayNumber: 1,
          date: '2026-09-01',
          theme: 'Kyoto',
          items: [
            TimelineItem(
              id: 'a',
              title: 'A',
              lat: 35.1,
              lng: 139.1,
              durationMin: 60,
              time: '09:00',
              scheduledTime: '09:00',
            ),
            TimelineItem(
              id: 'b',
              title: 'B',
              lat: 35.2,
              lng: 139.2,
              durationMin: 60,
              time: '09:30',
              scheduledTime: '09:30',
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
      availableEndTime: DateTime(day.year, day.month, day.day, 10),
    ),
  );
}

DayOptimizationInput _nonGridInput(TripLocation hotel) {
  final day = DateTime(2026, 9, 1);
  final fixedTrain = TimelineItem(
    id: 'train',
    title: 'Osaka → Tokyo Shinkansen',
    lat: 35.1,
    lng: 139.1,
    durationMin: 30,
    kind: TimelineItemKind.transport,
    time: '07:56',
    scheduledTime: '07:56',
  )
    ..lockType = ActivityLockType.trainReservation
    ..fixedStartTime = '07:56'
    ..fixedEndTime = '08:26'
    ..canChangeTime = false
    ..canReorder = false;

  return DayOptimizationInput(
    trip: Trip(
      id: 'trip-non-grid',
      slug: 'trip-non-grid',
      title: 'Tokyo',
      timezone: 'Asia/Tokyo',
      tripStart: '2026-09-01',
      tripEnd: '2026-09-01',
      flights: TripFlights(),
      preferences: TripPreferences(
        travelDates: TravelDates(start: '2026-09-01', end: '2026-09-01'),
        pace: Pace.moderate,
      ),
      days: [
        DayPlan(
          dayNumber: 1,
          date: '2026-09-01',
          theme: 'Tokyo',
          items: [
            TimelineItem(
              id: 'spot',
              title: 'Shibuya Sky & Crossing',
              lat: 35.2,
              lng: 139.2,
              durationMin: 90,
              kind: TimelineItemKind.activity,
            ),
            fixedTrain,
          ],
        ),
      ],
    ),
    dayNumber: 1,
    planVersion: 1,
    constraints: DayRouteConstraints(
      startLocation: hotel,
      endLocation: hotel,
      availableStartTime: DateTime(day.year, day.month, day.day, 6),
      availableEndTime: DateTime(day.year, day.month, day.day, 23),
    ),
  );
}

final _mealMatrix = RouteMatrix(
  version: 'meal-matrix-v1',
  entries: [
    for (final pair in <List<String>>[
      ['hotel', 'lunch'],
      ['hotel', 'spot1'],
      ['hotel', 'spot2'],
      ['lunch', 'spot1'],
      ['lunch', 'spot2'],
      ['spot1', 'spot2'],
      ['spot1', 'lunch'],
      ['spot2', 'lunch'],
      ['spot2', 'spot1'],
      ['lunch', 'hotel'],
      ['spot1', 'hotel'],
      ['spot2', 'hotel'],
    ])
      _entry(pair[0], pair[1], 15),
  ],
);

final _nonGridMatrix = RouteMatrix(
  version: 'non-grid-matrix-v1',
  entries: [
    _entry('hotel', 'spot', 0),
    _entry('spot', 'train', 13),
    _entry('train', 'hotel', 0),
    _entry('hotel', 'train', 0),
    _entry('train', 'spot', 50),
    _entry('spot', 'hotel', 0),
  ],
);

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

Trip _tripWith() => Trip(
      id: 'opt-trip',
      slug: 'opt',
      title: 'Opt',
      timezone: 'Asia/Tokyo',
      tripStart: '2026-07-01',
      tripEnd: '2026-07-02',
      flights: TripFlights(),
      preferences: TripPreferences(
        travelDates: TravelDates(start: '2026-07-01', end: '2026-07-02'),
        pace: Pace.moderate,
      ),
      days: [DayPlan(dayNumber: 1, date: '2026-07-01', theme: 'g', items: [])],
    );
