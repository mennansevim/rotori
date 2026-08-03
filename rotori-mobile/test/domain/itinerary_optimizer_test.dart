import 'package:flutter_test/flutter_test.dart';
import 'package:japan_trip/domain/itinerary_optimizer.dart';
import 'package:japan_trip/domain/route_matrix.dart';

final _day = DateTime(2026, 10, 12);

void main() {
  group('BeamSearchItineraryOptimizer', () {
    test('Tokyo kümelerini bölmeden deterministik bir akış kurar', () async {
      const hotel = TripLocation(
        id: 'hotel',
        name: 'Hotel',
        latitude: 35.66,
        longitude: 139.70,
        clusterId: 'west',
      );
      const locations = [
        TripLocation(
          id: 'shibuya',
          name: 'Shibuya Crossing',
          latitude: 35.6595,
          longitude: 139.7005,
          clusterId: 'west',
        ),
        TripLocation(
          id: 'harajuku',
          name: 'Harajuku',
          latitude: 35.6702,
          longitude: 139.7027,
          clusterId: 'west',
        ),
        TripLocation(
          id: 'meiji',
          name: 'Meiji Jingu',
          latitude: 35.6764,
          longitude: 139.6993,
          clusterId: 'west',
        ),
        TripLocation(
          id: 'shinjuku',
          name: 'Shinjuku',
          latitude: 35.6938,
          longitude: 139.7034,
          clusterId: 'west',
        ),
        TripLocation(
          id: 'asakusa',
          name: 'Asakusa',
          latitude: 35.7148,
          longitude: 139.7967,
          clusterId: 'east',
        ),
        TripLocation(
          id: 'ueno',
          name: 'Ueno',
          latitude: 35.7138,
          longitude: 139.7773,
          clusterId: 'east',
        ),
      ];
      final allLocations = [hotel, ...locations];
      final matrix = _completeMatrix(allLocations, (from, to) {
        if (from.clusterId == to.clusterId) return _walking(7);
        return _train(28);
      });
      final request = _request(
        locations,
        matrix,
        start: hotel,
        end: hotel,
        startHour: 8,
        endHour: 22,
      );
      const optimizer = BeamSearchItineraryOptimizer();

      final first = await optimizer.optimize(request);
      final second = await optimizer.optimize(request);

      expect(first.isSuccess, isTrue, reason: first.failure?.message);
      expect(second.isSuccess, isTrue);
      final ids = first.activities.map((item) => item.activityId).toList();
      expect(second.activities.map((item) => item.activityId).toList(), ids);
      expect(
          _indicesAreContiguous(ids, const {
            'shibuya',
            'harajuku',
            'meiji',
            'shinjuku',
          }),
          isTrue);
      expect(_indicesAreContiguous(ids, const {'asakusa', 'ueno'}), isTrue);
      expect(_containsSubsequence(ids, ['shibuya', 'asakusa', 'harajuku']),
          isFalse);
    });

    test('Osaka güney kümesini bir arada tutup Umeda yönünde bitirir',
        () async {
      const start = TripLocation(
        id: 'hotel-namba',
        name: 'Namba Hotel',
        latitude: 34.666,
        longitude: 135.501,
        clusterId: 'south',
      );
      const end = TripLocation(
        id: 'hotel-umeda',
        name: 'Umeda Hotel',
        latitude: 34.705,
        longitude: 135.498,
        clusterId: 'north',
      );
      const locations = [
        TripLocation(
          id: 'namba',
          name: 'Namba',
          latitude: 34.666,
          longitude: 135.501,
          clusterId: 'south',
        ),
        TripLocation(
          id: 'dotonbori',
          name: 'Dotonbori',
          latitude: 34.6687,
          longitude: 135.5013,
          clusterId: 'south',
        ),
        TripLocation(
          id: 'shinsaibashi',
          name: 'Shinsaibashi',
          latitude: 34.675,
          longitude: 135.5,
          clusterId: 'south',
        ),
        TripLocation(
          id: 'castle',
          name: 'Osaka Castle',
          latitude: 34.6873,
          longitude: 135.5262,
          clusterId: 'central',
        ),
        TripLocation(
          id: 'umeda',
          name: 'Umeda',
          latitude: 34.705,
          longitude: 135.498,
          clusterId: 'north',
        ),
      ];
      final matrix = _completeMatrix([start, end, ...locations], (from, to) {
        if (from.clusterId == to.clusterId) return _walking(6);
        return _train(18);
      });

      final result = await const BeamSearchItineraryOptimizer().optimize(
        _request(locations, matrix, start: start, end: end),
      );

      expect(result.isSuccess, isTrue, reason: result.failure?.message);
      final ids = result.activities.map((item) => item.activityId).toList();
      expect(
        _indicesAreContiguous(
          ids,
          const {'namba', 'dotonbori', 'shinsaibashi'},
        ),
        isTrue,
      );
      expect(ids.last, 'umeda');
      final umedaIndex = ids.indexOf('umeda');
      expect(
        ids.skip(umedaIndex + 1).any(
              (id) => const {'namba', 'dotonbori', 'shinsaibashi'}.contains(id),
            ),
        isFalse,
      );
    });

    test('14:00 rezervasyonu korur ve yetişmek için taksi seçer', () async {
      const hotel = TripLocation(
        id: 'hotel',
        name: 'Hotel',
        latitude: 35,
        longitude: 139,
        clusterId: 'hotel',
      );
      const preLocations = [
        TripLocation(
          id: 'pre-1',
          name: 'Pre 1',
          latitude: 35.01,
          longitude: 139.01,
          clusterId: 'before',
        ),
        TripLocation(
          id: 'pre-2',
          name: 'Pre 2',
          latitude: 35.02,
          longitude: 139.02,
          clusterId: 'before',
        ),
        TripLocation(
          id: 'pre-3',
          name: 'Pre 3',
          latitude: 35.03,
          longitude: 139.03,
          clusterId: 'before',
        ),
      ];
      const restaurant = TripLocation(
        id: 'restaurant',
        name: 'Restaurant',
        latitude: 35.08,
        longitude: 139.08,
        clusterId: 'reservation',
      );
      const postLocations = [
        TripLocation(
          id: 'post-1',
          name: 'Post 1',
          latitude: 35.09,
          longitude: 139.09,
          clusterId: 'after',
        ),
        TripLocation(
          id: 'post-2',
          name: 'Post 2',
          latitude: 35.10,
          longitude: 139.10,
          clusterId: 'after',
        ),
      ];
      final locations = [
        ...preLocations,
        restaurant,
        ...postLocations,
      ];
      final matrix = _completeMatrix([hotel, ...locations], (from, to) {
        if (to.id == 'restaurant' && from.id.startsWith('pre-')) {
          return null;
        }
        return from.clusterId == to.clusterId ? _walking(5) : _train(12);
      }, extraEntries: [
        for (final pre in preLocations)
          RouteMatrixEntry(
            fromLocationId: pre.id,
            toLocationId: restaurant.id,
            options: [_train(50), _taxi(15)],
          ),
      ]);
      final activities = [
        for (final location in preLocations)
          _activity(
            location,
            duration: 45,
            closing: DateTime(2026, 10, 12, 13, 20),
          ),
        _activity(
          restaurant,
          duration: 60,
          fixedStart: DateTime(2026, 10, 12, 14),
          fixedEnd: DateTime(2026, 10, 12, 15),
          reservation: true,
        ),
        for (final location in postLocations)
          _activity(
            location,
            duration: 45,
            opening: DateTime(2026, 10, 12, 15),
          ),
      ];
      final request = OptimizationRequest(
        activities: activities,
        routeMatrix: matrix,
        constraints: DayRouteConstraints(
          startLocation: hotel,
          endLocation: hotel,
          availableStartTime: DateTime(2026, 10, 12, 10),
          availableEndTime: DateTime(2026, 10, 12, 20),
        ),
      );

      final result =
          await const BeamSearchItineraryOptimizer().optimize(request);

      expect(result.isSuccess, isTrue, reason: result.failure?.message);
      final fixed = result.activities
          .singleWhere((item) => item.activityId == 'restaurant');
      expect(fixed.startTime, DateTime(2026, 10, 12, 14));
      expect(fixed.endTime, DateTime(2026, 10, 12, 15));
      expect(fixed.transportMode, TransportMode.taxi);
      expect(
        fixed.arrivalTime.isAfter(DateTime(2026, 10, 12, 13, 40)),
        isFalse,
      );
      expect(
        result.activities
            .takeWhile((item) => item.activityId != 'restaurant')
            .length,
        3,
      );
      expect(
        result.activities
            .skipWhile((item) => item.activityId != 'restaurant')
            .skip(1)
            .length,
        2,
      );
    });

    test('Balanced kısa farkta yürür; diğer profiller hedefe göre ayrışır',
        () async {
      const hotel = TripLocation(
        id: 'hotel',
        name: 'Hotel',
        latitude: 35,
        longitude: 139,
      );
      const place = TripLocation(
        id: 'place',
        name: 'Place',
        latitude: 35.01,
        longitude: 139.01,
      );
      final matrix = RouteMatrix(entries: [
        RouteMatrixEntry(
          fromLocationId: hotel.id,
          toLocationId: place.id,
          options: [
            _walking(19),
            _train(16, walking: 3, waiting: 2, cost: 180),
            _taxi(12, cost: 1400),
          ],
        ),
        RouteMatrixEntry(
          fromLocationId: place.id,
          toLocationId: hotel.id,
          options: [_walking(1)],
        ),
      ]);

      Future<TransportMode> selected(RouteOptimizationProfile profile) async {
        final result = await const BeamSearchItineraryOptimizer().optimize(
          _request(
            const [place],
            matrix,
            start: hotel,
            end: hotel,
            profile: profile,
          ),
        );
        expect(result.isSuccess, isTrue, reason: result.failure?.message);
        return result.activities.single.transportMode;
      }

      expect(await selected(RouteOptimizationProfile.balanced),
          TransportMode.walking);
      expect(
          await selected(RouteOptimizationProfile.fastest), TransportMode.taxi);
      expect(await selected(RouteOptimizationProfile.leastWalking),
          TransportMode.taxi);
      expect(await selected(RouteOptimizationProfile.cheapest),
          TransportMode.walking);
    });

    test('gün sonu dönüş maliyeti uzak noktayı sona bırakmaz', () async {
      const hotel = TripLocation(
        id: 'hotel',
        name: 'Hotel',
        latitude: 35,
        longitude: 139,
      );
      const remote = TripLocation(
        id: 'remote',
        name: 'Remote',
        latitude: 35.5,
        longitude: 139.5,
      );
      const nearby = TripLocation(
        id: 'nearby',
        name: 'Nearby',
        latitude: 35.01,
        longitude: 139.01,
      );
      final matrix = _completeMatrix(
        const [hotel, remote, nearby],
        (from, to) {
          if (to.id == 'hotel') {
            return _train(from.id == 'remote' ? 60 : 2);
          }
          if (from.id == 'hotel' && to.id == 'remote') return _train(10);
          if (from.id == 'hotel' && to.id == 'nearby') return _train(2);
          return _train(5);
        },
      );

      final result = await const BeamSearchItineraryOptimizer().optimize(
        _request(
          const [remote, nearby],
          matrix,
          start: hotel,
          end: hotel,
        ),
      );

      expect(result.isSuccess, isTrue, reason: result.failure?.message);
      expect(result.activities.last.activityId, 'nearby');
    });

    test('geri dönüş ve küme bölme cezası kısa zikzağı reddeder', () async {
      const hotel = TripLocation(
        id: 'hotel',
        name: 'Hotel',
        latitude: 35,
        longitude: 139,
        clusterId: 'a',
      );
      const a1 = TripLocation(
        id: 'a1',
        name: 'A1',
        latitude: 35.01,
        longitude: 139.01,
        clusterId: 'a',
      );
      const b = TripLocation(
        id: 'b',
        name: 'B',
        latitude: 35.02,
        longitude: 139.08,
        clusterId: 'b',
      );
      const a2 = TripLocation(
        id: 'z-a2',
        name: 'A2',
        latitude: 35.015,
        longitude: 139.015,
        clusterId: 'a',
      );
      final matrix = _completeMatrix(
        const [hotel, a1, b, a2],
        (from, to) {
          final splitEdge = (from.id == 'a1' && to.id == 'b') ||
              (from.id == 'b' && to.id == 'z-a2');
          if (splitEdge) return _train(1);
          if (from.clusterId == to.clusterId) return _walking(7);
          return _train(9);
        },
      );

      final result = await const BeamSearchItineraryOptimizer().optimize(
        _request(
          const [a1, b, a2],
          matrix,
          start: hotel,
          end: hotel,
        ),
      );

      expect(result.isSuccess, isTrue, reason: result.failure?.message);
      final ids = result.activities.map((item) => item.activityId).toList();
      expect(_indicesAreContiguous(ids, const {'a1', 'z-a2'}), isTrue);
    });

    test('benzer sürede daha az aktarmalı ulaşımı seçer', () async {
      const hotel = TripLocation(
        id: 'hotel',
        name: 'Hotel',
        latitude: 35,
        longitude: 139,
      );
      const place = TripLocation(
        id: 'place',
        name: 'Place',
        latitude: 35.1,
        longitude: 139.1,
      );
      final matrix = RouteMatrix(entries: [
        RouteMatrixEntry(
          fromLocationId: hotel.id,
          toLocationId: place.id,
          options: [
            _train(20, transfers: 2),
            _bus(24),
          ],
        ),
        RouteMatrixEntry(
          fromLocationId: place.id,
          toLocationId: hotel.id,
          options: [_bus(5)],
        ),
      ]);

      final result = await const BeamSearchItineraryOptimizer().optimize(
        _request(
          const [place],
          matrix,
          start: hotel,
          end: hotel,
        ),
      );

      expect(result.isSuccess, isTrue, reason: result.failure?.message);
      expect(result.activities.single.transportMode, TransportMode.bus);
      expect(result.metrics?.totalTransferCount, 0);
    });

    test('kilitli aktivite saat verisi olmadan taşınabilir kabul edilmez',
        () async {
      const hotel = TripLocation(
        id: 'hotel',
        name: 'Hotel',
        latitude: 35,
        longitude: 139,
      );
      const place = TripLocation(
        id: 'locked',
        name: 'Locked',
        latitude: 35.1,
        longitude: 139.1,
      );
      final matrix = _completeMatrix(
        const [hotel, place],
        (_, __) => _train(10),
      );
      final request = OptimizationRequest(
        activities: [
          OptimizationActivity(
            id: place.id,
            name: place.name,
            day: _day,
            location: place,
            durationMinutes: 60,
            isLocked: true,
          ),
        ],
        routeMatrix: matrix,
        constraints: DayRouteConstraints(
          startLocation: hotel,
          endLocation: hotel,
          availableStartTime: DateTime(2026, 10, 12, 9),
          availableEndTime: DateTime(2026, 10, 12, 18),
        ),
      );

      final result =
          await const BeamSearchItineraryOptimizer().optimize(request);

      expect(
        result.failure?.code,
        OptimizationFailureCode.fixedActivityMissingTime,
      );
    });

    test('kapanış, minimum süre ve gün sonu ihlallerini geçersiz sayar',
        () async {
      const hotel = TripLocation(
        id: 'hotel',
        name: 'Hotel',
        latitude: 35,
        longitude: 139,
      );
      const place = TripLocation(
        id: 'place',
        name: 'Place',
        latitude: 35.1,
        longitude: 139.1,
      );
      final matrix = _completeMatrix(
        const [hotel, place],
        (_, __) => _train(30),
      );
      final invalidDuration = OptimizationRequest(
        activities: [
          OptimizationActivity(
            id: place.id,
            name: place.name,
            day: _day,
            location: place,
            durationMinutes: 30,
            minimumDurationMinutes: 45,
          ),
        ],
        routeMatrix: matrix,
        constraints: DayRouteConstraints(
          startLocation: hotel,
          endLocation: hotel,
          availableStartTime: DateTime(2026, 10, 12, 9),
          availableEndTime: DateTime(2026, 10, 12, 18),
        ),
      );
      final closed = OptimizationRequest(
        activities: [
          _activity(
            place,
            duration: 60,
            closing: DateTime(2026, 10, 12, 9, 45),
          ),
        ],
        routeMatrix: matrix,
        constraints: DayRouteConstraints(
          startLocation: hotel,
          endLocation: hotel,
          availableStartTime: DateTime(2026, 10, 12, 9),
          availableEndTime: DateTime(2026, 10, 12, 10),
        ),
      );

      final durationResult =
          await const BeamSearchItineraryOptimizer().optimize(invalidDuration);
      final closedResult =
          await const BeamSearchItineraryOptimizer().optimize(closed);

      expect(
          durationResult.failure?.code, OptimizationFailureCode.invalidRequest);
      expect(
          closedResult.failure?.code, OptimizationFailureCode.noFeasibleRoute);
    });

    test('optional aktiviteyi preferred ve must-do öncesinde düşürür',
        () async {
      const hotel = TripLocation(
        id: 'hotel-drop',
        name: 'Hotel',
        latitude: 35,
        longitude: 139,
      );
      const optional = TripLocation(
        id: 'optional',
        name: 'Optional',
        latitude: 35.01,
        longitude: 139.01,
      );
      const preferred = TripLocation(
        id: 'preferred',
        name: 'Preferred',
        latitude: 35.02,
        longitude: 139.02,
      );
      const mustDo = TripLocation(
        id: 'must-do',
        name: 'Must Do',
        latitude: 35.03,
        longitude: 139.03,
      );
      final matrix = _completeMatrix(
        const [hotel, optional, preferred, mustDo],
        (_, __) => _walking(5),
      );
      final request = OptimizationRequest(
        activities: [
          _activity(optional,
              duration: 60, priority: ActivityPriority.optional),
          _activity(
            preferred,
            duration: 60,
            priority: ActivityPriority.preferred,
          ),
          _activity(mustDo, duration: 60, priority: ActivityPriority.mustDo),
        ],
        routeMatrix: matrix,
        constraints: DayRouteConstraints(
          startLocation: hotel,
          endLocation: hotel,
          availableStartTime: DateTime(2026, 10, 12, 9),
          availableEndTime: DateTime(2026, 10, 12, 11, 45),
        ),
      );

      final result = await const BeamSearchItineraryOptimizer(
        config: OptimizerConfig(allowActivityDropping: true),
      ).optimize(request);

      expect(result.isSuccess, isTrue, reason: result.failure?.message);
      expect(result.droppedActivityIds, ['optional']);
      expect(
          result.droppedActivities.single.priority, ActivityPriority.optional);
      expect(result.droppedActivities.single.reason, DropReason.userOptional);
      expect(
        result.activities.map((activity) => activity.activityId),
        containsAll(['preferred', 'must-do']),
      );
    });

    test('aynı öncelikte gezi durağını öğünden önce düşürür', () async {
      const hotel = TripLocation(
        id: 'hotel-meal-drop',
        name: 'Hotel',
        latitude: 35,
        longitude: 139,
      );
      const meal = TripLocation(
        id: 'meal',
        name: 'Lunch',
        latitude: 35.01,
        longitude: 139.01,
      );
      const sight = TripLocation(
        id: 'sight',
        name: 'Sight',
        latitude: 35.02,
        longitude: 139.02,
      );
      final request = OptimizationRequest(
        activities: [
          _activity(meal, duration: 60, category: 'meal'),
          _activity(sight, duration: 60),
        ],
        routeMatrix: _completeMatrix(
          const [hotel, meal, sight],
          (_, __) => _walking(5),
        ),
        constraints: DayRouteConstraints(
          startLocation: hotel,
          endLocation: hotel,
          availableStartTime: DateTime(2026, 10, 12, 9),
          availableEndTime: DateTime(2026, 10, 12, 10, 30),
        ),
      );

      final result = await const BeamSearchItineraryOptimizer(
        config: OptimizerConfig(allowActivityDropping: true),
      ).optimize(request);

      expect(result.isSuccess, isTrue, reason: result.failure?.message);
      expect(result.droppedActivityIds, ['sight']);
      expect(result.activities.single.activityId, 'meal');
    });

    test('imkansız must-do sessizce düşürülmez', () async {
      const hotel = TripLocation(
        id: 'hotel-protected',
        name: 'Hotel',
        latitude: 35,
        longitude: 139,
      );
      const place = TripLocation(
        id: 'protected',
        name: 'Protected',
        latitude: 35.1,
        longitude: 139.1,
      );
      final request = OptimizationRequest(
        activities: [
          _activity(place, duration: 180, priority: ActivityPriority.mustDo),
        ],
        routeMatrix: _completeMatrix(
          const [hotel, place],
          (_, __) => _walking(5),
        ),
        constraints: DayRouteConstraints(
          startLocation: hotel,
          endLocation: hotel,
          availableStartTime: DateTime(2026, 10, 12, 9),
          availableEndTime: DateTime(2026, 10, 12, 10),
        ),
      );

      final result = await const BeamSearchItineraryOptimizer(
        config: OptimizerConfig(allowActivityDropping: true),
      ).optimize(request);

      expect(result.isSuccess, isFalse);
      expect(
        result.failure?.code,
        OptimizationFailureCode.protectedActivityInfeasible,
      );
      expect(result.droppedActivityIds, isEmpty);
    });

    test('taşınan bagaj daha az yürüme ve aktarmalı seçeneğe yöneltir',
        () async {
      const hotel = TripLocation(
        id: 'hotel-luggage',
        name: 'Hotel',
        latitude: 35,
        longitude: 139,
      );
      const place = TripLocation(
        id: 'place-luggage',
        name: 'Place',
        latitude: 35.1,
        longitude: 139.1,
      );
      const train = TransportOption(
        mode: TransportMode.train,
        doorToDoorMinutes: 15,
        walkingMinutes: 5,
        waitingMinutes: 4,
        transferCount: 1,
        estimatedCostYen: 200,
        reliabilityScore: .95,
      );
      const taxi = TransportOption(
        mode: TransportMode.taxi,
        doorToDoorMinutes: 20,
        walkingMinutes: 1,
        waitingMinutes: 3,
        transferCount: 0,
        estimatedCostYen: 1800,
        reliabilityScore: .95,
        fareBasis: FareBasis.perVehicle,
      );
      final matrix = RouteMatrix(entries: [
        RouteMatrixEntry(
          fromLocationId: hotel.id,
          toLocationId: place.id,
          options: const [train, taxi],
        ),
        RouteMatrixEntry(
          fromLocationId: place.id,
          toLocationId: hotel.id,
          options: const [train, taxi],
        ),
      ]);
      OptimizationRequest request(LuggageState luggageState) =>
          OptimizationRequest(
            activities: [_activity(place)],
            routeMatrix: matrix,
            constraints: DayRouteConstraints(
              startLocation: hotel,
              endLocation: hotel,
              availableStartTime: DateTime(2026, 10, 12, 9),
              availableEndTime: DateTime(2026, 10, 12, 18),
            ),
            preferences: RoutePreferences(luggageState: luggageState),
          );

      final without = await const BeamSearchItineraryOptimizer()
          .optimize(request(LuggageState.none));
      final carried = await const BeamSearchItineraryOptimizer()
          .optimize(request(LuggageState.carried));

      expect(without.activities.single.transportMode, TransportMode.train);
      expect(carried.activities.single.transportMode, TransportMode.taxi);
    });

    test('schedule idle transit wait içine gizlenmeden ayrı ölçülür', () async {
      const hotel = TripLocation(
        id: 'hotel-idle',
        name: 'Hotel',
        latitude: 35,
        longitude: 139,
      );
      const place = TripLocation(
        id: 'place-idle',
        name: 'Place',
        latitude: 35.1,
        longitude: 139.1,
      );
      final request = OptimizationRequest(
        activities: [
          _activity(
            place,
            opening: DateTime(2026, 10, 12, 12),
          ),
        ],
        routeMatrix: _completeMatrix(
          const [hotel, place],
          (_, __) => _train(20, waiting: 4),
        ),
        constraints: DayRouteConstraints(
          startLocation: hotel,
          endLocation: hotel,
          availableStartTime: DateTime(2026, 10, 12, 9),
          availableEndTime: DateTime(2026, 10, 12, 18),
        ),
      );

      final result =
          await const BeamSearchItineraryOptimizer().optimize(request);
      expect(result.isSuccess, isTrue);
      expect(result.activities.single.inboundLeg.transitWaitMinutes, 4);
      expect(result.activities.single.inboundLeg.scheduleIdleMinutes,
          greaterThan(100));
      expect(result.metrics!.scheduleIdleMinutes, greaterThan(100));
      expect(result.metrics!.totalTransitWaitMinutes, 8);
    });
  });
}

OptimizationRequest _request(
  List<TripLocation> locations,
  RouteMatrix matrix, {
  required TripLocation start,
  required TripLocation end,
  int startHour = 9,
  int endHour = 21,
  RouteOptimizationProfile profile = RouteOptimizationProfile.balanced,
}) =>
    OptimizationRequest(
      activities: locations.map(_activity).toList(),
      routeMatrix: matrix,
      constraints: DayRouteConstraints(
        startLocation: start,
        endLocation: end,
        availableStartTime: DateTime(2026, 10, 12, startHour),
        availableEndTime: DateTime(2026, 10, 12, endHour),
      ),
      preferences: RoutePreferences(
        profile: profile,
        maximumWalkingMinutes: 240,
      ),
    );

OptimizationActivity _activity(
  TripLocation location, {
  int duration = 45,
  DateTime? opening,
  DateTime? closing,
  DateTime? fixedStart,
  DateTime? fixedEnd,
  bool reservation = false,
  ActivityPriority priority = ActivityPriority.normal,
  String? category,
}) =>
    OptimizationActivity(
      id: location.id,
      name: location.name,
      day: _day,
      location: location,
      durationMinutes: duration,
      minimumDurationMinutes: duration,
      openingTime: opening,
      closingTime: closing,
      fixedStartTime: fixedStart,
      fixedEndTime: fixedEnd,
      isFixed: fixedStart != null,
      hasReservation: reservation,
      priority: priority,
      category: category,
    );

RouteMatrix _completeMatrix(
  List<TripLocation> locations,
  TransportOption? Function(TripLocation from, TripLocation to) optionFor, {
  List<RouteMatrixEntry> extraEntries = const [],
}) {
  final extras = {
    for (final entry in extraEntries)
      '${entry.fromLocationId}\u0000${entry.toLocationId}': entry,
  };
  final entries = <RouteMatrixEntry>[];
  for (final from in locations) {
    for (final to in locations) {
      if (from.id == to.id) continue;
      final key = '${from.id}\u0000${to.id}';
      final extra = extras[key];
      if (extra != null) {
        entries.add(extra);
        continue;
      }
      final option = optionFor(from, to);
      if (option == null) continue;
      entries.add(
        RouteMatrixEntry(
          fromLocationId: from.id,
          toLocationId: to.id,
          options: [option],
        ),
      );
    }
  }
  return RouteMatrix(entries: entries, version: 'scenario-v1');
}

TransportOption _walking(int minutes) => TransportOption(
      mode: TransportMode.walking,
      doorToDoorMinutes: minutes,
      walkingMinutes: minutes,
      waitingMinutes: 0,
      transferCount: 0,
      estimatedCostYen: 0,
      reliabilityScore: 1,
    );

TransportOption _train(
  int minutes, {
  int walking = 5,
  int waiting = 4,
  int cost = 180,
  int transfers = 0,
}) =>
    TransportOption(
      mode: TransportMode.train,
      doorToDoorMinutes: minutes,
      walkingMinutes: walking,
      waitingMinutes: waiting,
      transferCount: transfers,
      estimatedCostYen: cost,
      reliabilityScore: .95,
    );

TransportOption _bus(int minutes) => TransportOption(
      mode: TransportMode.bus,
      doorToDoorMinutes: minutes,
      walkingMinutes: 3,
      waitingMinutes: 3,
      transferCount: 0,
      estimatedCostYen: 210,
      reliabilityScore: .92,
    );

TransportOption _taxi(int minutes, {int cost = 1800}) => TransportOption(
      mode: TransportMode.taxi,
      doorToDoorMinutes: minutes,
      walkingMinutes: 1,
      waitingMinutes: 3,
      transferCount: 0,
      estimatedCostYen: cost,
      reliabilityScore: .9,
    );

bool _indicesAreContiguous(List<String> ids, Set<String> cluster) {
  final indices = <int>[
    for (var i = 0; i < ids.length; i++)
      if (cluster.contains(ids[i])) i,
  ];
  if (indices.isEmpty) return true;
  return indices.last - indices.first + 1 == indices.length;
}

bool _containsSubsequence(List<String> values, List<String> pattern) {
  var patternIndex = 0;
  for (final value in values) {
    if (value == pattern[patternIndex]) {
      patternIndex++;
      if (patternIndex == pattern.length) return true;
    }
  }
  return false;
}
