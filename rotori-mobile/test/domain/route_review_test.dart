// LLM rota incelemesi — payload ve öneri uygulama.
//
// En kritik sözleşme: öneri plan motorundan geçer. Model kilitli bir durağı
// oynatmak isterse ya da çakışma üretirse öneri SESSİZCE düşer, plan bozulmaz.

import 'package:flutter_test/flutter_test.dart';

import 'package:rotori/data/route_review_client.dart';
import 'package:rotori/domain/plan_generation.dart';
import 'package:rotori/domain/route_execution.dart';
import 'package:rotori/domain/route_matrix.dart';
import 'package:rotori/domain/route_review.dart';
import 'package:rotori/domain/types.dart';

void main() {
  Trip weekTrip() => buildTripFromCities(
        cityKeys: const ['tokyo'],
        startYmd: '2026-10-15',
        endYmd: '2026-10-21',
      );

  /// En az iki duraklı, hiçbiri sistem kilitli olmayan bir gün bulur.
  DayPlan freeDay(Trip trip) => trip.days.firstWhere(
        (d) =>
            d.items.length >= 2 &&
            d.items.every((i) => !i.isFixed),
        orElse: () => fail('uygun gün bulunamadı'),
      );

  RouteExecutionLeg leg(int travelMinutes) => RouteExecutionLeg(
        kind: RouteExecutionLegKind.betweenStops,
        fromLocationId: 'a',
        fromName: 'A',
        toLocationId: 'b',
        toName: 'B',
        mode: TransportMode.train,
        departureTime: DateTime(2026, 10, 15, 9),
        arrivalTime:
            DateTime(2026, 10, 15, 9).add(Duration(minutes: travelMinutes)),
        travelDurationMinutes: travelMinutes,
        rideMinutes: travelMinutes - 10,
        accessMinutes: 10,
        walkingDurationMinutes: 10,
        waitingDurationMinutes: 5,
        transitWaitMinutes: 5,
        scheduleIdleMinutes: 0,
        transferCount: 1,
        costPerPersonYen: 300,
        partyTotalCostYen: 300,
        vehicleCount: 1,
        fareBasis: FareBasis.perPerson,
        reliabilityScore: .95,
        dataQuality: RouteExecutionDataQuality.estimated,
        complexityPenalty: 0,
      );

  void attachSnapshot(Trip trip, int dayNumber, int travelMinutes) {
    final day = trip.days.firstWhere((d) => d.dayNumber == dayNumber);
    day.routeExecutionSnapshot = RouteExecutionSnapshot(
      planId: trip.id,
      dayNumber: dayNumber,
      planVersion: 1,
      activityHash: 'test-$dayNumber-$travelMinutes',
      matrixVersion: 'test',
      generatedAt: DateTime.utc(2026, 8, 14),
      profile: RouteOptimizationProfile.balanced,
      legs: [leg(travelMinutes)],
    );
  }

  group('payload', () {
    test('gün, durak, kilit ve otel bilgisini taşır', () {
      final trip = weekTrip();
      trip.hotels.add(HotelStay(
        id: 'h1',
        name: 'Shinjuku Granbell',
        city: 'Tokyo',
        address: '2-14-5 Kabukicho',
        checkIn: '2026-10-15',
        checkOut: '2026-10-18',
      ));
      final day = freeDay(trip);
      _lockAsTicketed(day.items.first);

      final payload = buildRouteReviewPayload(
        trip: trip,
        languageCode: 'tr',
      );

      expect(payload['language'], 'tr');
      expect((payload['cities'] as List), isNotEmpty);
      expect((payload['hotels'] as List).single['name'], 'Shinjuku Granbell');

      final days = payload['days'] as List;
      expect(days.length, trip.days.length);

      final sent = days
          .cast<Map<String, dynamic>>()
          .firstWhere((d) => d['dayNumber'] == day.dayNumber);
      expect(sent['city'], isNotEmpty);
      final stops = (sent['stops'] as List).cast<Map<String, dynamic>>();
      expect(stops.length, day.items.length);
      // Kilit modele AÇIKÇA bildirilir.
      expect(stops.first['locked'], isTrue);
      expect(stops.first['id'], day.items.first.id);
    });

    test('hava tahmini yoksa weather alanı hiç yazılmaz', () {
      final payload = buildRouteReviewPayload(
        trip: weekTrip(),
        languageCode: 'en',
      );
      for (final day
          in (payload['days'] as List).cast<Map<String, dynamic>>()) {
        expect(day.containsKey('weather'), isFalse);
      }
    });
  });

  group('öneriyi uygulama', () {
    test('geçerli sıra önerisi uygulanır', () {
      final trip = weekTrip();
      final day = freeDay(trip);
      final ids = day.items.map((i) => i.id).toList();
      // Baştaki iki durağın yerini değiştir.
      final proposed = [ids[1], ids[0], ...ids.skip(2)];

      final outcome = applyRouteReview(
        trip: trip,
        review: RouteReview(
          notes: const ['yakın duraklar gruplandı'],
          days: [
            RouteReviewDay(
              dayNumber: day.dayNumber,
              order: proposed,
              times: const {},
            ),
          ],
        ),
      );

      expect(outcome.changedAnything, isTrue);
      expect(outcome.appliedDays, contains(day.dayNumber));
      final applied = outcome.trip.days
          .firstWhere((d) => d.dayNumber == day.dayNumber)
          .items
          .map((i) => i.id)
          .toList();
      expect(applied.first, ids[1]);
      // Durak sayısı korunur — hiçbir şey düşmedi.
      expect(applied.length, ids.length);
      expect(applied.toSet(), ids.toSet());
    });

    test('kilitli durağı oynatan öneri reddedilir ve plan bozulmaz', () {
      final trip = weekTrip();
      final day = freeDay(trip);
      final ids = day.items.map((i) => i.id).toList();
      // İlk durağı kilitle, sonra onu 2. sıraya taşımayı öner.
      _lockAsTicketed(day.items.first);
      final before = [...ids];

      final outcome = applyRouteReview(
        trip: trip,
        review: RouteReview(
          notes: const [],
          days: [
            RouteReviewDay(
              dayNumber: day.dayNumber,
              order: [ids[1], ids[0], ...ids.skip(2)],
              times: const {},
            ),
          ],
        ),
      );

      expect(outcome.changedAnything, isFalse);
      expect(outcome.rejectedDays, contains(day.dayNumber));
      final after = outcome.trip.days
          .firstWhere((d) => d.dayNumber == day.dayNumber)
          .items
          .map((i) => i.id)
          .toList();
      expect(after, before, reason: 'plan öneri reddedilince değişmemeli');
    });

    test('kilitli durağın saatini değiştiren öneri yutulur', () {
      final trip = weekTrip();
      final day = freeDay(trip);
      final locked = day.items.first;
      _lockAsTicketed(locked);
      final lockedTime = locked.time ?? locked.scheduledTime;

      final outcome = applyRouteReview(
        trip: trip,
        review: RouteReview(
          notes: const [],
          days: [
            RouteReviewDay(
              dayNumber: day.dayNumber,
              order: const [],
              times: {locked.id: '07:05'},
            ),
          ],
        ),
      );

      final after = outcome.trip.days
          .firstWhere((d) => d.dayNumber == day.dayNumber)
          .items
          .firstWhere((i) => i.id == locked.id);
      expect(after.time ?? after.scheduledTime, lockedTime);
    });

    test('bilinmeyen gün ve bozuk saat sessizce düşer', () {
      final trip = weekTrip();

      final outcome = applyRouteReview(
        trip: trip,
        review: const RouteReview(
          notes: [],
          days: [
            RouteReviewDay(dayNumber: 999, order: [], times: {}),
          ],
        ),
      );

      expect(outcome.changedAnything, isFalse);
      expect(outcome.rejectedDays, contains(999));
      expect(outcome.trip.days.length, trip.days.length);
    });

    test('eksik id içeren sıra önerisi uygulanmaz', () {
      final trip = weekTrip();
      final day = freeDay(trip);
      final ids = day.items.map((i) => i.id).toList();

      final outcome = applyRouteReview(
        trip: trip,
        review: RouteReview(
          notes: const [],
          days: [
            // Bir durak eksik → permütasyon değil, sıra hiç denenmez.
            RouteReviewDay(
              dayNumber: day.dayNumber,
              order: ids.take(ids.length - 1).toList(),
              times: const {},
            ),
          ],
        ),
      );

      expect(outcome.changedAnything, isFalse);
      final after = outcome.trip.days
          .firstWhere((d) => d.dayNumber == day.dayNumber)
          .items
          .map((i) => i.id)
          .toList();
      expect(after, ids);
    });
  });

  group('client çözümlemesi', () {
    test('boş/bozuk gövde öneri üretmez', () {
      expect(RouteReview.fromJson(const {}).hasSuggestions, isFalse);
      // Model beklenmeyen tip döndürebilir; fırlatmak yerine "öneri yok".
      expect(
        RouteReview.fromJson(const {'days': 'not-a-list'}).hasSuggestions,
        isFalse,
      );
      expect(RouteReview.fromJson(const {'days': 7}).hasSuggestions, isFalse);
      expect(RouteReview.fromJson(const {'notes': 3}).notes, isEmpty);
      expect(
        RouteReview.fromJson(const {
          'days': [
            {
              'dayNumber': 'iki',
              'order': ['a']
            }
          ],
        }).hasSuggestions,
        isFalse,
      );
      expect(
        RouteReview.fromJson(const {
          'days': [
            {'dayNumber': 1, 'order': 'nope', 'times': 'nope'}
          ],
        }).hasSuggestions,
        isFalse,
      );
      // order ve times birlikte boşsa gün atılır.
      expect(
        RouteReview.fromJson(const {
          'days': [
            {'dayNumber': 1, 'order': <String>[], 'times': <String, String>{}}
          ],
        }).hasSuggestions,
        isFalse,
      );
    });

    test('geçerli gövde çözümlenir, notlar taşınır', () {
      final review = RouteReview.fromJson(const {
        'verdict': 'improve',
        'notes': ['yağış 14:00 sonrası', 'müze içeriye alındı'],
        'days': [
          {
            'dayNumber': 2,
            'order': ['b', 'a'],
            'times': {'a': '10:30'},
          },
        ],
      });

      expect(review.hasSuggestions, isTrue);
      expect(review.notes, hasLength(2));
      expect(review.days.single.dayNumber, 2);
      expect(review.days.single.order, ['b', 'a']);
      expect(review.days.single.times['a'], '10:30');
    });
  });

  group('hibrit aday doğrulaması', () {
    test(
        'yalnız skoru anlamlı biçimde iyileşen ve snapshot üreten aday kabul edilir',
        () async {
      final baseline = weekTrip();
      final day = freeDay(baseline);
      final ids = day.items.map((item) => item.id).toList();
      attachSnapshot(baseline, day.dayNumber, 100);

      final result = await verifyRouteReviewCandidate(
        baseline: baseline,
        review: RouteReview(
          notes: const [],
          days: [
            RouteReviewDay(
              dayNumber: day.dayNumber,
              order: [ids[1], ids[0], ...ids.skip(2)],
              times: const {},
            ),
          ],
        ),
        optimizeCandidate: (candidate, affectedDays) async {
          expect(affectedDays, {day.dayNumber});
          attachSnapshot(candidate, day.dayNumber, 70);
          return candidate;
        },
      );

      expect(result.status, VerifiedRouteReviewStatus.accepted);
      expect(result.improvementPercent, greaterThan(2));
      expect(
          result.trip.days
              .firstWhere((d) => d.dayNumber == day.dayNumber)
              .routeExecutionSnapshot,
          isNotNull);
    });

    test('geçerli ama daha kötü aday reddedilir ve taban snapshot korunur',
        () async {
      final baseline = weekTrip();
      final day = freeDay(baseline);
      final ids = day.items.map((item) => item.id).toList();
      attachSnapshot(baseline, day.dayNumber, 80);

      final result = await verifyRouteReviewCandidate(
        baseline: baseline,
        review: RouteReview(
          notes: const [],
          days: [
            RouteReviewDay(
              dayNumber: day.dayNumber,
              order: [ids[1], ids[0], ...ids.skip(2)],
              times: const {},
            ),
          ],
        ),
        optimizeCandidate: (candidate, affectedDays) async {
          attachSnapshot(candidate, day.dayNumber, 110);
          return candidate;
        },
      );

      expect(result.status, VerifiedRouteReviewStatus.rejectedByScore);
      expect(result.trip, same(baseline));
      expect(
          baseline.days
              .firstWhere((d) => d.dayNumber == day.dayNumber)
              .routeExecutionSnapshot,
          isNotNull);
    });

    test('yeniden optimize edilmeyen ve snapshot üretmeyen aday reddedilir',
        () async {
      final baseline = weekTrip();
      final day = freeDay(baseline);
      final ids = day.items.map((item) => item.id).toList();
      attachSnapshot(baseline, day.dayNumber, 80);

      final result = await verifyRouteReviewCandidate(
        baseline: baseline,
        review: RouteReview(
          notes: const [],
          days: [
            RouteReviewDay(
              dayNumber: day.dayNumber,
              order: [ids[1], ids[0], ...ids.skip(2)],
              times: const {},
            ),
          ],
        ),
        optimizeCandidate: (candidate, affectedDays) async => candidate,
      );

      expect(result.status, VerifiedRouteReviewStatus.rejectedBySnapshot);
      expect(result.trip, same(baseline));
    });

    test('model yalnız ölçülebilir karmaşıklığı olan günler için çağrılır', () {
      final trip = weekTrip();
      final day = trip.days.firstWhere((d) => d.items.length >= 4);
      attachSnapshot(trip, day.dayNumber, 130);

      expect(routeReviewCandidateDays(trip), {day.dayNumber});
      expect(shouldRequestRouteReview(trip), isTrue);
    });

    test('model bütçesi en karmaşık üç günle sınırlanır', () {
      final trip = weekTrip();
      final days =
          trip.days.where((day) => day.items.length >= 4).take(4).toList();
      expect(days, hasLength(4));
      for (var i = 0; i < days.length; i++) {
        attachSnapshot(trip, days[i].dayNumber, 120 + i * 20);
      }

      final candidates = routeReviewCandidateDays(trip);
      expect(candidates, hasLength(3));
      expect(candidates, isNot(contains(days.first.dayNumber)));
      expect(candidates, contains(days.last.dayNumber));
    });
  });
}

void _lockAsTicketed(TimelineItem item) {
  item.lockType = ActivityLockType.ticketedEvent;
  item.canChangeDay = false;
  item.canChangeTime = false;
  item.canReorder = false;
  item.canDelete = false;
  item.lockReason = 'Bilet alındı';
}
