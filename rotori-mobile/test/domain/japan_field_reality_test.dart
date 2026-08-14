// Saha gerçekliği katmanının zorunlu edge-case kapıları.
//
// Bu dosya, brief'te adı geçen dört senaryoyu doğrular:
//   Test 1 — JR Pass varken Nozomi seçilmez ve süre uzar.
//   Test 2 — Pazartesi resmî tatilse müze Pazartesi AÇIK, Salı KAPALI.
//   Test 3 — Shinjuku gibi dev istasyonda stationNavigationBuffer eklenir.
//   Test 4 — Büyük bagaj + uzun mesafe → Yamato; coin locker süresi iptal.
//
// Ek olarak her katmanın kendi sözleşmesi (kanonik kimlik, tekrar politikası,
// sezonluk süre) ve v2 geriye uyumluluğu regresyona bağlanır.

import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/domain/activity_identity.dart';
import 'package:rotori/domain/city_transfers.dart';
import 'package:rotori/domain/hard_constraint_checker.dart';
import 'package:rotori/domain/itinerary_optimizer.dart';
import 'package:rotori/domain/japan_calendar.dart';
import 'package:rotori/domain/japan_transit_realism.dart';
import 'package:rotori/domain/luggage_logistics.dart';
import 'package:rotori/domain/place_identity_resolver.dart';
import 'package:rotori/domain/plan_field_signals.dart';
import 'package:rotori/domain/route_field_context.dart';
import 'package:rotori/domain/route_matrix.dart';
import 'package:rotori/domain/types.dart';

// ---------------------------------------------------------------------------
// Sabitler ve yardımcılar
// ---------------------------------------------------------------------------

/// 12 Ekim 2026 — Pazartesi VE スポーツの日 (Sports Day) resmî tatili.
/// Holiday Shift testinin çekirdek tarihi.
final DateTime kHolidayMonday = DateTime(2026, 10, 12);
final DateTime kShiftedTuesday = DateTime(2026, 10, 13);
final DateTime kOrdinaryMonday = DateTime(2026, 10, 19);
final DateTime kOrdinaryTuesday = DateTime(2026, 10, 20);

const TripLocation _shinjuku = TripLocation(
  id: 'shinjuku-station',
  name: 'Shinjuku Station',
  latitude: 35.6896,
  longitude: 139.7006,
  clusterId: 'west',
);

const TripLocation _quietStop = TripLocation(
  id: 'yanaka-ginza',
  name: 'Yanaka Ginza',
  latitude: 35.7276,
  longitude: 139.7663,
  clusterId: 'north',
);

const TripLocation _hotel = TripLocation(
  id: 'hotel-base',
  name: 'Hotel Base',
  latitude: 35.6812,
  longitude: 139.7671,
  clusterId: 'base',
);

TransportOption _trainOption({
  int doorToDoor = 30,
  int walking = 10,
  int transfers = 1,
}) =>
    TransportOption(
      mode: TransportMode.train,
      doorToDoorMinutes: doorToDoor,
      walkingMinutes: walking,
      waitingMinutes: 4,
      transferCount: transfers,
      estimatedCostYen: 200,
      reliabilityScore: .97,
      lineId: 'jy',
      directionId: 'outer',
    );

TransportOption _shinkansenOption({
  required String service,
  int doorToDoor = 150,
}) =>
    TransportOption(
      mode: TransportMode.shinkansen,
      doorToDoorMinutes: doorToDoor,
      walkingMinutes: 12,
      waitingMinutes: 10,
      transferCount: 0,
      estimatedCostYen: 14170,
      reliabilityScore: .99,
      lineId: service,
    );

RouteMatrix _matrix(List<TripLocation> locations,
    {List<TransportOption>? options}) {
  final entries = <RouteMatrixEntry>[];
  for (final from in locations) {
    for (final to in locations) {
      if (from.id == to.id) continue;
      entries.add(RouteMatrixEntry(
        fromLocationId: from.id,
        toLocationId: to.id,
        options: options ?? [_trainOption()],
      ));
    }
  }
  return RouteMatrix(entries: entries, version: 'test-v3');
}

void main() {
  // =========================================================================
  // TEST 1 — JR Pass + Nozomi
  // =========================================================================
  group('Test 1 — JR Pass varken Nozomi geçersiz, süre uzar', () {
    test('Nozomi, JR Pass sahibi için infeasible sayılır', () {
      final model = TransitRealismModel();
      final outcome = model.evaluate(
        _shinkansenOption(service: 'nozomi'),
        departure: DateTime(2026, 10, 15, 9),
        railPass: RailPassType.nationalJrPass,
      );
      expect(outcome.isFeasible, isFalse);
      expect(
        outcome.infeasibilityReason,
        TransitInfeasibilityReason.passExcludedService,
      );
    });

    test('Bölgesel JR Pass de Nozomi/Mizuho kısıtına tabidir', () {
      final model = TransitRealismModel();
      for (final service in ['nozomi', 'mizuho']) {
        final outcome = model.evaluate(
          _shinkansenOption(service: service),
          departure: DateTime(2026, 10, 15, 9),
          railPass: RailPassType.regionalJrPass,
        );
        expect(outcome.isFeasible, isFalse, reason: service);
      }
    });

    test('Hikari geçerlidir ve pass olmadan Nozomi de geçerlidir', () {
      final model = TransitRealismModel();
      final hikari = model.evaluate(
        _shinkansenOption(service: 'hikari'),
        departure: DateTime(2026, 10, 15, 9),
        railPass: RailPassType.nationalJrPass,
      );
      final noPassNozomi = model.evaluate(
        _shinkansenOption(service: 'nozomi'),
        departure: DateTime(2026, 10, 15, 9),
        railPass: RailPassType.none,
      );
      expect(hikari.isFeasible, isTrue);
      expect(noPassNozomi.isFeasible, isTrue);
      expect(noPassNozomi.effectiveService, ShinkansenService.nozomi);
    });

    test('Tokyo→Kyoto geçiş satırı Nozomi yerine Hikari olur ve süre %20 uzar',
        () {
      const passless = RailPassType.none;
      final base = suggestionForModeWithPass(
        'shinkansen',
        'Tokyo',
        'Kyoto',
        1,
        2,
        railPass: passless,
      );
      final withPass = suggestionForModeWithPass(
        'shinkansen',
        'Tokyo',
        'Kyoto',
        1,
        2,
        railPass: RailPassType.nationalJrPass,
      );

      // Pass yokken bilinen Nozomi kaydı korunur: 2s 15dk.
      expect(base.transfer.mode, contains('Nozomi'));
      expect(cityTransferDurationMinutes(base.transfer), 135);

      // Pass varken servis Hikari'ye düşer ve süre uzar.
      expect(withPass.transfer.mode, contains('Hikari'));
      expect(withPass.transfer.mode, isNot(contains('Nozomi')));
      final adjusted = cityTransferDurationMinutes(withPass.transfer);
      expect(adjusted, 162); // ceil(135 * 1.20)
      expect(adjusted, greaterThan(cityTransferDurationMinutes(base.transfer)));
    });

    test('picker seçenekleri Nozomi\'yi gösterir ama seçilemez işaretler', () {
      final options = cityTransitionOptionsFor(
        fromCity: 'Tokyo',
        toCity: 'Kyoto',
        railPass: RailPassType.nationalJrPass,
      );
      final shinkansen = options.firstWhere((o) => o.mode == 'shinkansen');
      expect(shinkansen.isBlockedByPass, isTrue);
      expect(shinkansen.serviceLabel, 'Hikari');
      expect(shinkansen.disclaimers, contains('railPassDowngrade'));

      final withoutPass = cityTransitionOptionsFor(
        fromCity: 'Tokyo',
        toCity: 'Kyoto',
        railPass: RailPassType.none,
      ).firstWhere((o) => o.mode == 'shinkansen');
      expect(withoutPass.isBlockedByPass, isFalse);
    });

    test('optimizer JR Pass altında Nozomi bacağını budar', () async {
      final nozomiOnly = _matrix(
        [_hotel, _quietStop],
        options: [_shinkansenOption(service: 'nozomi', doorToDoor: 40)],
      );
      final day = DateTime(2026, 10, 15);
      final request = OptimizationRequest(
        activities: [
          OptimizationActivity(
            id: _quietStop.id,
            name: _quietStop.name,
            day: day,
            location: _quietStop,
            durationMinutes: 60,
            minimumDurationMinutes: 60,
          ),
        ],
        routeMatrix: nozomiOnly,
        constraints: DayRouteConstraints(
          startLocation: _hotel,
          endLocation: _hotel,
          availableStartTime: DateTime(2026, 10, 15, 9),
          availableEndTime: DateTime(2026, 10, 15, 20),
        ),
        field: FieldRealityContext(
          travelDate: day,
          cityId: 'tokyo',
          traveller:
              const TravellerProfile(railPass: RailPassType.nationalJrPass),
        ),
      );

      final result =
          await const BeamSearchItineraryOptimizer().optimize(request);
      expect(result.isSuccess, isFalse);
      expect(result.failure?.code, OptimizationFailureCode.noFeasibleRoute);
    });
  });

  // =========================================================================
  // TEST 2 — Holiday Shift (Pazartesi sendromu)
  // =========================================================================
  group('Test 2 — Holiday Shift: tatil Pazartesi açık, Salı kapalı', () {
    final resolver = ClosureResolver();
    final museum = ClosureRule(weeklyClosedWeekdays: {DateTime.monday});

    test('12 Ekim 2026 hem Pazartesi hem resmî tatildir', () {
      expect(kHolidayMonday.weekday, DateTime.monday);
      final holiday = JapanPublicHolidayCalendar().holidayOn(kHolidayMonday);
      expect(holiday, isNotNull);
      expect(holiday!.id, 'sports-no-hi');
    });

    test('resmî tatil Pazartesi müze AÇIK kalır', () {
      final verdict = resolver.evaluate(museum, kHolidayMonday);
      expect(verdict.isOpen, isTrue);
    });

    test('kapanış ertesi güne (Salı) KAYAR', () {
      final verdict = resolver.evaluate(museum, kShiftedTuesday);
      expect(verdict.isClosed, isTrue);
      expect(verdict.cause, ClosureCause.shiftedClosure);
      expect(verdict.shiftedFrom, kHolidayMonday);
    });

    test('tatil olmayan haftada kural değişmez: Pazartesi kapalı, Salı açık',
        () {
      expect(resolver.evaluate(museum, kOrdinaryMonday).isClosed, isTrue);
      expect(
        resolver.evaluate(museum, kOrdinaryMonday).cause,
        ClosureCause.weeklyClosure,
      );
      expect(resolver.evaluate(museum, kOrdinaryTuesday).isOpen, isTrue);
    });

    test('ardışık tatil zinciri kapanışı tatil olmayan ilk güne iter', () {
      // 4 May 2026 Pazartesi (みどりの日), 5 May (こどもの日), 6 May (振替休日).
      // Kapanış 7 Mayıs Perşembe'ye kayar.
      expect(resolver.evaluate(museum, DateTime(2026, 5, 4)).isOpen, isTrue);
      expect(resolver.evaluate(museum, DateTime(2026, 5, 5)).isOpen, isTrue);
      expect(resolver.evaluate(museum, DateTime(2026, 5, 6)).isOpen, isTrue);
      final shifted = resolver.evaluate(museum, DateTime(2026, 5, 7));
      expect(shifted.isClosed, isTrue);
      expect(shifted.cause, ClosureCause.shiftedClosure);
    });

    test('HardConstraintChecker müzeyi tatil Pazartesi kabul, Salı reddeder',
        () {
      HardConstraintViolation? verdictFor(DateTime date) {
        final field = FieldRealityContext(travelDate: date, cityId: 'tokyo');
        final checker = HardConstraintChecker(
          constraints: DayRouteConstraints(
            startLocation: _hotel,
            endLocation: _hotel,
            availableStartTime: DateTime(date.year, date.month, date.day, 9),
            availableEndTime: DateTime(date.year, date.month, date.day, 20),
          ),
          preferences: const RoutePreferences(),
          field: field,
        );
        final activity = OptimizationActivity(
          id: 'tokyo-national-museum',
          name: 'Tokyo National Museum',
          day: date,
          location: _quietStop,
          durationMinutes: 90,
          minimumDurationMinutes: 60,
          category: 'museum',
          closureRule: ClosureRule(weeklyClosedWeekdays: {DateTime.monday}),
        );
        return checker.check(PlacementCandidate(
          activity: activity,
          arrival: DateTime(date.year, date.month, date.day, 10),
          start: DateTime(date.year, date.month, date.day, 10),
          end: DateTime(date.year, date.month, date.day, 11, 30),
          bufferMinutes: 10,
          totalWalkingMinutes: 20,
          effectiveOpeningTime: null,
          effectiveClosingTime: null,
        ));
      }

      expect(verdictFor(kHolidayMonday), isNull,
          reason: 'resmî tatil Pazartesi müze açık olmalı');

      final tuesday = verdictFor(kShiftedTuesday);
      expect(tuesday, isNotNull, reason: 'kayan kapanış Salı reddedilmeli');
      expect(tuesday!.type, HardConstraintViolationType.closedOnDate);
      expect(tuesday.detail, 'shiftedClosure');

      final ordinaryMonday = verdictFor(kOrdinaryMonday);
      expect(ordinaryMonday, isNotNull);
      expect(ordinaryMonday!.detail, 'weeklyClosure');
    });

    test('optimizer kapalı günde müzeyi rotaya koymaz', () async {
      Future<bool> canSchedule(DateTime date) async {
        final activity = OptimizationActivity(
          id: 'museum',
          name: 'Tokyo National Museum',
          day: date,
          location: _quietStop,
          durationMinutes: 90,
          minimumDurationMinutes: 60,
          category: 'museum',
          closureRule: ClosureRule(weeklyClosedWeekdays: {DateTime.monday}),
        );
        final result = await const BeamSearchItineraryOptimizer().optimize(
          OptimizationRequest(
            activities: [activity],
            routeMatrix: _matrix([_hotel, _quietStop]),
            constraints: DayRouteConstraints(
              startLocation: _hotel,
              endLocation: _hotel,
              availableStartTime: DateTime(date.year, date.month, date.day, 9),
              availableEndTime: DateTime(date.year, date.month, date.day, 20),
            ),
            field: FieldRealityContext(travelDate: date, cityId: 'tokyo'),
          ),
        );
        return result.isSuccess;
      }

      expect(await canSchedule(kHolidayMonday), isTrue);
      expect(await canSchedule(kShiftedTuesday), isFalse);
      expect(await canSchedule(kOrdinaryMonday), isFalse);
      expect(await canSchedule(kOrdinaryTuesday), isTrue);
    });

    test('dropping fallback saha bağlamını kaybedip kapalı must-do ekleyemez',
        () async {
      final result = await const BeamSearchItineraryOptimizer(
        config: OptimizerConfig(allowActivityDropping: true),
      ).optimize(
        OptimizationRequest(
          activities: [
            OptimizationActivity(
              id: 'closed-must-do',
              name: 'Tokyo National Museum',
              day: kShiftedTuesday,
              location: _quietStop,
              durationMinutes: 90,
              minimumDurationMinutes: 60,
              priority: ActivityPriority.mustDo,
              closureRule: ClosureRule(
                weeklyClosedWeekdays: {DateTime.monday},
              ),
            ),
            OptimizationActivity(
              id: 'optional',
              name: 'Optional stop',
              day: kShiftedTuesday,
              location: _shinjuku,
              durationMinutes: 60,
              minimumDurationMinutes: 30,
              priority: ActivityPriority.optional,
            ),
          ],
          routeMatrix: _matrix([_hotel, _quietStop, _shinjuku]),
          constraints: DayRouteConstraints(
            startLocation: _hotel,
            endLocation: _hotel,
            availableStartTime: DateTime(2026, 10, 13, 9),
            availableEndTime: DateTime(2026, 10, 13, 20),
          ),
          field: FieldRealityContext(
            travelDate: kShiftedTuesday,
            cityId: 'tokyo',
          ),
        ),
      );

      expect(result.isSuccess, isFalse);
      expect(
        result.failure?.code,
        OptimizationFailureCode.protectedActivityInfeasible,
      );
      expect(result.activities, isEmpty);
    });
  });

  // =========================================================================
  // TEST 3 — Dev istasyon navigasyon tamponu
  // =========================================================================
  group('Test 3 — Shinjuku stationNavigationBuffer', () {
    test('Shinjuku labyrinth, Yanaka Ginza normal sınıflanır', () {
      final registry = StationComplexityRegistry();
      expect(
        registry.resolve(locationId: _shinjuku.id, name: _shinjuku.name),
        StationComplexity.labyrinth,
      );
      expect(
        registry.resolve(locationId: _quietStop.id, name: _quietStop.name),
        StationComplexity.normal,
      );
      expect(StationComplexity.labyrinth.navigationBufferMinutes, 15);
      expect(StationComplexity.normal.navigationBufferMinutes, 0);
    });

    test('Japonca Shinjuku aliasları labyrinth olarak çözülür', () {
      final registry = StationComplexityRegistry();
      expect(
        registry.resolve(name: '新宿'),
        StationComplexity.labyrinth,
      );
      expect(
        registry.resolve(name: '新宿駅'),
        StationComplexity.labyrinth,
      );
      expect(
        registry.resolve(name: '東京国立博物館'),
        StationComplexity.normal,
        reason: 'şehir adını içeren her Japonca mekan istasyon değildir',
      );
    });

    test('tek labyrinth istasyonda yürümeye +15 dk eklenir', () {
      final model = TransitRealismModel();
      final outcome = model.evaluate(
        _trainOption(doorToDoor: 30, walking: 10),
        departure: DateTime(2026, 10, 15, 11),
        fromLocationId: _shinjuku.id,
        fromName: _shinjuku.name,
        toLocationId: _quietStop.id,
        toName: _quietStop.name,
      );
      expect(outcome.isFeasible, isTrue);
      expect(outcome.stationNavigationBufferMinutes, 15);
      expect(outcome.walkingMinutes, 25); // 10 + 15
      expect(outcome.doorToDoorMinutes, 45); // 30 + 15
      expect(
        outcome.disclaimers,
        contains(TransitDisclaimer.stationNavigationBuffer),
      );
    });

    test('iki labyrinth istasyon arasında tampon toplanır (+30)', () {
      final model = TransitRealismModel();
      final outcome = model.evaluate(
        _trainOption(doorToDoor: 30, walking: 10),
        departure: DateTime(2026, 10, 15, 11),
        fromLocationId: 'shinjuku-station',
        fromName: 'Shinjuku Station',
        toLocationId: 'tokyo-station',
        toName: 'Tokyo Station',
      );
      expect(outcome.stationNavigationBufferMinutes, 30);
      expect(outcome.doorToDoorMinutes, 60);
    });

    test('taksi ve yürüyüşte istasyon tamponu uygulanmaz', () {
      final model = TransitRealismModel();
      for (final mode in [TransportMode.taxi, TransportMode.walking]) {
        final outcome = model.evaluate(
          TransportOption(
            mode: mode,
            doorToDoorMinutes: 25,
            walkingMinutes: mode == TransportMode.walking ? 25 : 2,
            waitingMinutes: 0,
            transferCount: 0,
            estimatedCostYen: mode == TransportMode.taxi ? 2400 : 0,
            reliabilityScore: .9,
          ),
          departure: DateTime(2026, 10, 15, 11),
          fromLocationId: _shinjuku.id,
          fromName: _shinjuku.name,
          toLocationId: _quietStop.id,
          toName: _quietStop.name,
        );
        expect(outcome.stationNavigationBufferMinutes, 0, reason: mode.name);
      }
    });

    test('optimizer Shinjuku başlangıcında tamponu rotaya yansıtır', () async {
      final day = DateTime(2026, 10, 15);
      Future<RouteLeg> firstLeg({required bool withField}) async {
        final request = OptimizationRequest(
          activities: [
            OptimizationActivity(
              id: _quietStop.id,
              name: _quietStop.name,
              day: day,
              location: _quietStop,
              durationMinutes: 60,
              minimumDurationMinutes: 60,
            ),
          ],
          routeMatrix: _matrix([_shinjuku, _quietStop]),
          constraints: DayRouteConstraints(
            startLocation: _shinjuku,
            endLocation: _shinjuku,
            availableStartTime: DateTime(2026, 10, 15, 9),
            availableEndTime: DateTime(2026, 10, 15, 20),
          ),
          field: withField
              ? FieldRealityContext(travelDate: day, cityId: 'tokyo')
              : null,
        );
        final result =
            await const BeamSearchItineraryOptimizer().optimize(request);
        expect(result.isSuccess, isTrue);
        return result.activities.first.inboundLeg;
      }

      final withoutField = await firstLeg(withField: false);
      final withField = await firstLeg(withField: true);

      expect(withoutField.stationNavigationBufferMinutes, 0);
      expect(withoutField.travelDurationMinutes, 30);

      expect(withField.stationNavigationBufferMinutes, 15);
      expect(withField.travelDurationMinutes, 45);
      expect(withField.walkingDurationMinutes, 25);
      expect(
        withField.transitDisclaimers,
        contains(TransitDisclaimer.stationNavigationBuffer),
      );
    });
  });

  // =========================================================================
  // TEST 4 — Yamato vs Coin Locker
  // =========================================================================
  group('Test 4 — büyük bagaj + uzun mesafe → Yamato, coin locker iptal', () {
    const resolver = LuggageStrategyResolver();

    LuggageContext tokyoToKyoto({
      LuggageSize size = LuggageSize.large,
      int transferMinutes = 135,
      int arrivalHour = 12,
      int nights = 3,
      int? departureHour = 9,
    }) =>
        LuggageContext(
          size: size,
          bagCount: 2,
          arrivalAtDestination: DateTime(2026, 10, 15, arrivalHour),
          intercityTransferMinutes: transferMinutes,
          nightsAtDestination: nights,
          originHotelDepartureTime: departureHour == null
              ? null
              : DateTime(2026, 10, 15, departureHour),
        );

    test('Yamato seçilir; varış tarafı bagaj süresi SIFIR', () {
      final plan = resolver.resolve(tokyoToKyoto());
      expect(plan.strategy, LuggageHandlingStrategy.yamatoForward);
      expect(plan.arrivalHandlingMinutes, 0,
          reason: 'coin locker / otel bırakma süresi iptal edilmeli');
      expect(plan.retrievalMinutes, 0);
      expect(plan.originHandoverMinutes, 20);
      expect(plan.baggageAvailableAfterDays, 1);
      expect(plan.bypassesStationLuggageBuffer, isTrue);
      expect(plan.advisories,
          contains(LuggageAdvisory.yamatoOvernightBagRequired));
      expect(plan.reasonCode, 'yamato-forward');
    });

    test('kısa mesafede (Kyoto→Osaka 30dk) Yamato SEÇİLMEZ', () {
      final context = tokyoToKyoto(transferMinutes: 30);
      expect(
        resolver.yamatoRejectionFor(context),
        LuggageAdvisory.yamatoDistanceTooShort,
      );
      final plan = resolver.resolve(context);
      expect(plan.strategy, isNot(LuggageHandlingStrategy.yamatoForward));
    });

    test('kabin boy bagajda Yamato SEÇİLMEZ', () {
      final context = tokyoToKyoto(size: LuggageSize.cabin);
      expect(resolver.yamatoRejectionFor(context), isNotNull);
      expect(
        resolver.resolve(context).strategy,
        isNot(LuggageHandlingStrategy.yamatoForward),
      );
    });

    test('kargo son teslim saati (10:00) kaçırılırsa Yamato SEÇİLMEZ', () {
      final context = tokyoToKyoto(departureHour: 13);
      expect(
        resolver.yamatoRejectionFor(context),
        LuggageAdvisory.yamatoCutoffMissed,
      );
      expect(
        resolver.resolve(context).strategy,
        isNot(LuggageHandlingStrategy.yamatoForward),
      );
    });

    test('tek gece kalışta Yamato SEÇİLMEZ', () {
      expect(
        resolver.yamatoRejectionFor(tokyoToKyoto(nights: 1)),
        LuggageAdvisory.yamatoStayTooShort,
      );
    });

    test('Yamato uygun değilken erken varış coin locker/otel drop üretir', () {
      // Büyük bagaj coin locker'a sığmaz → otele erken bırakma seçilir.
      final large = resolver.resolve(tokyoToKyoto(transferMinutes: 30));
      expect(large.strategy, LuggageHandlingStrategy.hotelEarlyDrop);
      expect(large.advisories, contains(LuggageAdvisory.arrivedBeforeCheckIn));
      expect(
          large.advisories, contains(LuggageAdvisory.oversizedForCoinLocker));

      // Otel istasyona uzaksa coin locker kazanır ve +20 dk eklenir.
      const farHotel = LuggageStrategyResolver(
        policy: LuggagePolicy(
          hotel: HotelLuggagePolicy(detourMinutesFromStation: 35),
        ),
      );
      final locker = farHotel.resolve(LuggageContext(
        size: LuggageSize.medium,
        bagCount: 1,
        arrivalAtDestination: DateTime(2026, 10, 15, 12),
        intercityTransferMinutes: 30,
      ));
      expect(locker.strategy, LuggageHandlingStrategy.coinLocker);
      expect(locker.arrivalHandlingMinutes, 20);
      expect(locker.retrievalMinutes, 10);
      expect(locker.advisories, contains(LuggageAdvisory.hotelDetourExpensive));
    });

    test('check-in penceresi açıkken doğrudan otele girilir', () {
      final plan = resolver.resolve(tokyoToKyoto(
        transferMinutes: 30,
        arrivalHour: 16,
      ));
      expect(plan.strategy, LuggageHandlingStrategy.hotelCheckIn);
      expect(plan.reasonCode, 'hotel-check-in-window');
    });

    test('check-in penceresi kapandıktan sonra varış hard ihlaldir', () {
      expect(
        evaluateHotelCheckIn(arrival: DateTime(2026, 10, 15, 23, 30)),
        HotelCheckInStatus.afterWindow,
      );
      expect(
        evaluateHotelCheckIn(arrival: DateTime(2026, 10, 15, 12)),
        HotelCheckInStatus.beforeWindow,
      );
      expect(
        evaluateHotelCheckIn(arrival: DateTime(2026, 10, 15, 16)),
        HotelCheckInStatus.withinWindow,
      );

      final checker = HardConstraintChecker(
        constraints: DayRouteConstraints(
          startLocation: _hotel,
          endLocation: _hotel,
          availableStartTime: DateTime(2026, 10, 15, 9),
          availableEndTime: DateTime(2026, 10, 16, 1),
        ),
        preferences: const RoutePreferences(),
        field: FieldRealityContext(travelDate: DateTime(2026, 10, 15)),
      );
      final violation = checker.check(PlacementCandidate(
        activity: OptimizationActivity(
          id: 'hotel-checkin',
          name: 'Hotel Check-in',
          day: DateTime(2026, 10, 15),
          location: _hotel,
          durationMinutes: 20,
          minimumDurationMinutes: 10,
          requiresHotelCheckIn: true,
        ),
        arrival: DateTime(2026, 10, 15, 23, 30),
        start: DateTime(2026, 10, 15, 23, 30),
        end: DateTime(2026, 10, 15, 23, 50),
        bufferMinutes: 0,
        totalWalkingMinutes: 10,
        effectiveOpeningTime: null,
        effectiveClosingTime: null,
      ));
      expect(violation, isNotNull);
      expect(
        violation!.type,
        HardConstraintViolationType.hotelCheckInWindowClosed,
      );
    });

    test('optimizer: Yamato günü bagaj tamponu yok, coin locker günü var',
        () async {
      final day = DateTime(2026, 10, 15);
      Future<int> firstBuffer(LuggagePlan plan) async {
        final result = await const BeamSearchItineraryOptimizer().optimize(
          OptimizationRequest(
            activities: [
              OptimizationActivity(
                id: _quietStop.id,
                name: _quietStop.name,
                day: day,
                location: _quietStop,
                durationMinutes: 60,
                minimumDurationMinutes: 60,
              ),
            ],
            routeMatrix: _matrix([_hotel, _quietStop]),
            constraints: DayRouteConstraints(
              startLocation: _hotel,
              endLocation: _hotel,
              availableStartTime: DateTime(2026, 10, 15, 9),
              availableEndTime: DateTime(2026, 10, 15, 20),
            ),
            field: FieldRealityContext(
              travelDate: day,
              cityId: 'kyoto',
              traveller: const TravellerProfile(
                luggageSize: LuggageSize.large,
                bagCount: 2,
              ),
              luggagePlan: plan,
            ),
          ),
        );
        expect(result.isSuccess, isTrue);
        return result.activities.first.inboundLeg.bufferMinutes;
      }

      final coinLocker = const LuggageStrategyResolver()
          .resolve(tokyoToKyoto(transferMinutes: 30, size: LuggageSize.medium));
      expect(coinLocker.strategy, LuggageHandlingStrategy.coinLocker);

      final yamato = const LuggageStrategyResolver().resolve(tokyoToKyoto());
      expect(yamato.strategy, LuggageHandlingStrategy.yamatoForward);

      final lockerBuffer = await firstBuffer(coinLocker);
      final yamatoBuffer = await firstBuffer(yamato);

      // Coin locker günü: karmaşık geçiş tamponu (15) + locker (20) = 35.
      expect(lockerBuffer, 35);
      // Yamato günü: yalnız geçiş tamponu — bagaj yolcuda değil.
      expect(yamatoBuffer, 15);
      expect(lockerBuffer - yamatoBuffer, coinLocker.arrivalHandlingMinutes);
    });

    test('resolveTransitionLuggagePlan Tokyo→Kyoto senaryosunu çözer', () {
      final plan = resolveTransitionLuggagePlan(
        transitionMinutes: 135,
        arrivalMinutes: 12 * 60,
        size: LuggageSize.large,
        bagCount: 2,
        nightsAtDestination: 3,
        originDepartureMinutes: 9 * 60,
      );
      expect(plan.strategy, LuggageHandlingStrategy.yamatoForward);

      // Yamato'da timeline'a bagaj satırı EKLENMEZ.
      expect(
        luggageHandlingTimelineItem(
          dayNumber: 3,
          plan: plan,
          atMinutes: 12 * 60,
          cityId: 'Kyoto',
        ),
        isNull,
      );

      final lockerPlan = resolveTransitionLuggagePlan(
        transitionMinutes: 30,
        arrivalMinutes: 12 * 60,
        size: LuggageSize.medium,
        bagCount: 1,
        policy: const LuggagePolicy(
          hotel: HotelLuggagePolicy(detourMinutesFromStation: 35),
        ),
      );
      final row = luggageHandlingTimelineItem(
        dayNumber: 3,
        plan: lockerPlan,
        atMinutes: 12 * 60,
        cityId: 'Kyoto',
      );
      expect(row, isNotNull);
      expect(row!.durationMin, 20);
      expect(row.kind, TimelineItemKind.hotel);
      expect(row.time, '12:00');
    });
  });

  // =========================================================================
  // Trafik risk matrisi
  // =========================================================================
  group('otoyol otobüsü / taksi trafik belirsizliği', () {
    final model = TransitRealismModel();

    TransportOption busOption() => const TransportOption(
          mode: TransportMode.bus,
          doorToDoorMinutes: 100,
          walkingMinutes: 6,
          waitingMinutes: 10,
          transferCount: 0,
          estimatedCostYen: 2200,
          reliabilityScore: .8,
        );

    test('peak saatte 1.3x, peak dışında 1.1x uygulanır', () {
      final peak = model.evaluate(
        busOption(),
        departure: DateTime(2026, 10, 15, 8),
      );
      final offPeak = model.evaluate(
        busOption(),
        departure: DateTime(2026, 10, 15, 13),
      );
      expect(peak.trafficRiskMultiplier, 1.30);
      expect(peak.doorToDoorMinutes, 130);
      expect(offPeak.trafficRiskMultiplier, 1.10);
      expect(offPeak.doorToDoorMinutes, 110);
    });

    test('hafta sonu ve resmî tatilde leisure çarpanı 1.15x uygulanır', () {
      final weekend = model.evaluate(
        busOption(),
        departure: DateTime(2026, 10, 17, 8), // Cumartesi
      );
      final publicHoliday = model.evaluate(
        busOption(),
        departure: DateTime(2026, 10, 12, 8),
        isPublicHoliday: true,
      );
      expect(weekend.trafficRiskMultiplier, 1.15);
      expect(weekend.doorToDoorMinutes, 115);
      expect(publicHoliday.trafficRiskMultiplier, 1.15);
      expect(publicHoliday.doorToDoorMinutes, 115);
    });

    test('hasTrafficRiskDisclaimer her iki durumda da set edilir', () {
      for (final hour in [8, 13, 18]) {
        final outcome = model.evaluate(busOption(),
            departure: DateTime(2026, 10, 15, hour));
        expect(outcome.hasTrafficRiskDisclaimer, isTrue, reason: '$hour:00');
      }
    });

    test('raylı sistemde trafik çarpanı uygulanmaz', () {
      final outcome = model.evaluate(
        _trainOption(doorToDoor: 30, walking: 0),
        departure: DateTime(2026, 10, 15, 8),
      );
      expect(outcome.trafficRiskMultiplier, 1);
      expect(outcome.hasTrafficRiskDisclaimer, isFalse);
      expect(outcome.doorToDoorMinutes, 30);
    });

    test('checker aynı bacak ve kalkış için saha sonucunu yeniden kullanır',
        () {
      final day = DateTime(2026, 10, 15);
      final checker = HardConstraintChecker(
        constraints: DayRouteConstraints(
          startLocation: _hotel,
          endLocation: _hotel,
          availableStartTime: DateTime(2026, 10, 15, 7),
          availableEndTime: DateTime(2026, 10, 15, 22),
        ),
        preferences: const RoutePreferences(),
        field: FieldRealityContext(travelDate: day),
      );
      final option = busOption();
      final departure = DateTime(2026, 10, 15, 8);

      final first = checker.realiseTransit(
        option: option,
        departure: departure,
        from: _hotel,
        to: _quietStop,
      );
      final repeated = checker.realiseTransit(
        option: option,
        departure: departure,
        from: _hotel,
        to: _quietStop,
      );
      final anotherDeparture = checker.realiseTransit(
        option: option,
        departure: departure.add(const Duration(minutes: 1)),
        from: _hotel,
        to: _quietStop,
      );

      expect(identical(first, repeated), isTrue);
      expect(identical(first, anotherDeparture), isFalse);
    });

    test('picker otobüs seçeneğine trafik uyarısı ekler', () {
      final bus = cityTransitionOptionsFor(
        fromCity: 'Tokyo',
        toCity: 'Kyoto',
        departureMinutes: 8 * 60,
      ).firstWhere((o) => o.mode == 'bus');
      expect(bus.hasTrafficRiskDisclaimer, isTrue);
      expect(bus.disclaimers, contains('trafficRisk'));
    });
  });

  // =========================================================================
  // Sezonluk yoğunluk
  // =========================================================================
  group('Golden Week / Sakura süre uzaması', () {
    final crowd = JapanCrowdModel();

    test('sezon pencereleri doğru tespit edilir', () {
      expect(crowd.seasonFor(DateTime(2027, 5, 2), cityId: 'kyoto'),
          CrowdSeason.goldenWeek);
      expect(crowd.seasonFor(DateTime(2027, 4, 2), cityId: 'tokyo'),
          CrowdSeason.sakura);
      expect(crowd.seasonFor(DateTime(2027, 8, 14), cityId: 'tokyo'),
          CrowdSeason.obon);
      expect(crowd.seasonFor(DateTime(2027, 1, 1), cityId: 'tokyo'),
          CrowdSeason.newYear);
      expect(crowd.seasonFor(DateTime(2027, 6, 15), cityId: 'tokyo'),
          CrowdSeason.normal);
      // Sapporo'da sakura çok geç açar — Nisan başı normaldir.
      expect(crowd.seasonFor(DateTime(2027, 4, 2), cityId: 'sapporo'),
          CrowdSeason.normal);
    });

    test('Kyoto tapınağı Golden Week\'te %25 uzar', () {
      final multiplier = crowd.durationMultiplier(
        date: DateTime(2027, 5, 2),
        cityId: 'kyoto',
        sensitivity: CrowdSensitivity.high,
      );
      expect(multiplier, closeTo(1.25, 0.0001));
      expect(applyCrowdMultiplier(120, multiplier), 150);
    });

    test('kalabalıktan etkilenmeyen kategori uzamaz', () {
      expect(
        crowd.durationMultiplier(
          date: DateTime(2027, 5, 2),
          cityId: 'kyoto',
          sensitivity: CrowdSensitivity.none,
        ),
        1,
      );
      expect(crowdSensitivityForCategory('Tapınak'), CrowdSensitivity.high);
      expect(
        crowdSensitivityForCategory('themepark'),
        CrowdSensitivity.none,
      );
      expect(crowdSensitivityForCategory('Otel'), CrowdSensitivity.none);
      expect(crowdSensitivityForCategory('Müze'), CrowdSensitivity.moderate);
    });

    test('FieldRealityContext süreyi tapınakta uzatır, otelde uzatmaz', () {
      final field = FieldRealityContext(
        travelDate: DateTime(2027, 5, 2),
        cityId: 'kyoto',
      );
      expect(field.season, CrowdSeason.goldenWeek);
      expect(field.inflateDuration(120, category: 'temple'), 150);
      expect(field.inflateDuration(120, category: 'hotel'), 120);
      expect(field.walkingCrowdMultiplier, closeTo(1.15, 0.0001));
    });

    test('optimizer uzayan süreyi programa yansıtır', () async {
      final day = DateTime(2027, 5, 2);
      Future<Duration> visitLength({required bool withField}) async {
        final result = await const BeamSearchItineraryOptimizer().optimize(
          OptimizationRequest(
            activities: [
              OptimizationActivity(
                id: 'kiyomizu',
                name: 'Kiyomizu-dera',
                day: day,
                location: _quietStop,
                durationMinutes: 120,
                minimumDurationMinutes: 60,
                category: 'temple',
              ),
            ],
            routeMatrix: _matrix([_hotel, _quietStop]),
            constraints: DayRouteConstraints(
              startLocation: _hotel,
              endLocation: _hotel,
              availableStartTime: DateTime(2027, 5, 2, 9),
              availableEndTime: DateTime(2027, 5, 2, 20),
            ),
            field: withField
                ? FieldRealityContext(travelDate: day, cityId: 'kyoto')
                : null,
          ),
        );
        expect(result.isSuccess, isTrue);
        final visit = result.activities.first;
        return visit.endTime.difference(visit.startTime);
      }

      expect(await visitLength(withField: false), const Duration(minutes: 120));
      expect(await visitLength(withField: true), const Duration(minutes: 150));
    });
  });

  // =========================================================================
  // Kanonik kimlik (i18n)
  // =========================================================================
  group('PlaceIdentityResolver — Kanji/Kana/Romaji', () {
    final resolver = PlaceIdentityResolver();

    test('清水寺 varyantları tek anahtara iner', () {
      final keys = [
        '清水寺',
        'きよみずでら',
        'キヨミズデラ',
        'Kiyomizu-dera',
        'Kiyomizudera',
        'Kiyomizu dera',
      ].map((t) => resolver.resolve(title: t, cityId: 'kyoto').key).toSet();
      expect(keys, hasLength(1));
      expect(keys.single, 'kyoto:kiyomizudera');
    });

    test('kana → Hepburn romaji dönüşümü', () {
      expect(kanaToRomaji('しんじゅく'), 'shinjuku');
      expect(kanaToRomaji('なんば'), 'namba'); // ん + b → m
      expect(kanaToRomaji('きょうと'), 'kyouto'); // digraph きょ
      expect(kanaToRomaji('スカイツリー'), 'sukaitsuri'); // katakana + ー
      expect(kanaToRomaji('いっぱい'), 'ippai'); // 促音 っ
      expect(kanaToRomaji('まっちゃ'), 'matcha'); // っ + ch → tch
    });

    test('macron ve Türkçe karakterler katlanır', () {
      expect(
        resolver.resolve(title: 'Tōkyō Tawā', cityId: 'tokyo').key,
        resolver.resolve(title: 'Tokyo Tawa', cityId: 'tokyo').key,
      );
      expect(
        resolver.normalize('Şibuya Kavşağı'),
        'sibuyakavsagi',
      );
    });

    test('kanonik hash kararlıdır ve şehir kapsamlıdır', () {
      final kyoto = resolver.resolve(title: '清水寺', cityId: 'kyoto');
      final osaka = resolver.resolve(title: '清水寺', cityId: 'osaka');
      expect(kyoto.hash, isNotEmpty);
      expect(kyoto.hash,
          resolver.resolve(title: 'Kiyomizudera', cityId: 'kyoto').hash);
      expect(kyoto.hash, isNot(osaka.hash));
      expect(stableHash('kyoto:kiyomizudera'), kyoto.hash);
    });

    test('placeId taşıyan iki güvenilir kayıt bulanık birleştirilmez', () {
      final a = resolver.resolve(
          title: 'Ueno Park', placeId: 'tk-ueno', cityId: 'tokyo');
      final b = resolver.resolve(
          title: 'Ueno Zoo', placeId: 'tk-ueno-zoo', cityId: 'tokyo');
      expect(a.isAuthoritative, isTrue);
      expect(b.isAuthoritative, isTrue);
      expect(resolver.isSamePlace(a, b), isFalse);
    });

    test('başlıktan türeyen kimliklerde önek eşleşmesi çalışır', () {
      final a = resolver.resolve(title: 'Kiyomizudera', cityId: 'kyoto');
      final b = resolver.resolve(title: 'Kiyomizudera Temple', cityId: 'kyoto');
      expect(a.isAuthoritative, isFalse);
      expect(resolver.isSamePlace(a, b), isTrue);
    });

    test('kısa adlarda bulanık eşleşme yapılmaz', () {
      final a = resolver.resolve(title: 'Ueno', cityId: 'tokyo');
      final b = resolver.resolve(title: 'Ueni', cityId: 'tokyo');
      expect(resolver.isSamePlace(a, b), isFalse);
    });

    test('farklı şehirdeki aynı ad birleşmez', () {
      final a = resolver.resolve(title: 'Kiyomizudera', cityId: 'kyoto');
      final b = resolver.resolve(title: 'Kiyomizudera', cityId: 'osaka');
      expect(resolver.isSamePlace(a, b), isFalse);
    });

    test('alias soft merge en kaliteli kaydı ana yapar', () {
      final merges = softMergeAliases([
        PlaceAliasRecord(
          identity:
              resolver.resolve(title: 'Universal Studios', cityId: 'osaka'),
          title: 'Universal Studios',
        ),
        PlaceAliasRecord(
          identity: resolver.resolve(
              title: 'Universal Studios Japan',
              placeId: 'os-usj',
              cityId: 'osaka'),
          title: 'Universal Studios Japan',
          placeId: 'os-usj',
          hasCoordinates: true,
          hasDescription: true,
        ),
      ]);
      expect(merges, hasLength(1));
      expect(merges.single.didMerge, isTrue);
      expect(merges.single.primary.placeId, 'os-usj');
      expect(merges.single.absorbed.single.title, 'Universal Studios');
    });

    test('kullanıcı seçimi kalite skorunda öne geçer', () {
      final merges = softMergeAliases([
        PlaceAliasRecord(
          identity: resolver.resolve(
              title: 'USJ', placeId: 'os-usj', cityId: 'osaka'),
          title: 'USJ',
          placeId: 'os-usj',
          hasCoordinates: true,
          hasDescription: true,
          hasImage: true,
        ),
        PlaceAliasRecord(
          identity:
              resolver.resolve(title: 'Universal Studios', cityId: 'osaka'),
          title: 'Universal Studios',
          userExplicitSelection: true,
        ),
      ]);
      expect(merges.single.primary.userExplicitSelection, isTrue);
    });
  });

  // =========================================================================
  // Intent-aware tekrar politikası
  // =========================================================================
  group('esnek tekrar kısıtı', () {
    const evaluator = RepeatPolicyEvaluator();

    RepeatObservation observation({
      int minutes = 60,
      int consecutive = 1,
    }) =>
        RepeatObservation(
          identityKey: 'tokyo:test',
          previousDayNumber: 1,
          minutesSpentSoFar: minutes,
          consecutiveDayCount: consecutive,
        );

    test('hardZero ardışık tekrarı reddeder', () {
      final verdict = evaluator.evaluate(
        rule: const RepeatRule(),
        observation: observation(),
      );
      expect(verdict.decision, RepeatDecision.rejectAdjacentDuplicate);
    });

    test('repeatableZone iki ardışık güne izin verir, üçüncüyü reddeder', () {
      expect(
        evaluator
            .evaluate(rule: const RepeatRule.zone(), observation: observation())
            .isAllowed,
        isTrue,
      );
      expect(
        evaluator
            .evaluate(
              rule: const RepeatRule.zone(),
              observation: observation(consecutive: 2),
            )
            .decision,
        RepeatDecision.rejectConsecutiveLimit,
      );
    });

    test('timeQuota kota dolmadıkça tekrar önerir', () {
      final incomplete = evaluator.evaluate(
        rule: const RepeatRule.quota(240),
        observation: observation(minutes: 60),
      );
      expect(incomplete.isAllowed, isTrue);
      expect(incomplete.remainingQuotaMinutes, 180);
      expect(incomplete.reason, 'quota-incomplete');

      final satisfied = evaluator.evaluate(
        rule: const RepeatRule.quota(240),
        observation: observation(minutes: 240),
      );
      expect(satisfied.decision, RepeatDecision.rejectAdjacentDuplicate);
      expect(satisfied.reason, 'quota-satisfied');
    });

    test('userOverride her şeyi ezer', () {
      final verdict = evaluator.evaluate(
        rule: const RepeatRule.userSelected(),
        observation: observation(consecutive: 9),
      );
      expect(verdict.isAllowed, isTrue);
      expect(verdict.reason, 'user-explicit-selection');
    });

    test('inferRepeatRule bölge ve parkları yakalar', () {
      expect(inferRepeatRule(title: 'Akihabara').isRepeatableZone, isTrue);
      expect(
        inferRepeatRule(title: 'Universal Studios Japan').isRepeatableZone,
        isTrue,
      );
      expect(inferRepeatRule(title: 'Senso-ji').policy, RepeatPolicy.hardZero);
      expect(
        inferRepeatRule(
                title: 'Tokyo National Museum', recommendedTotalMinutes: 240)
            .policy,
        RepeatPolicy.timeQuota,
      );
      expect(
        inferRepeatRule(title: 'Senso-ji', userExplicitSelection: true)
            .isUserOverride,
        isTrue,
      );
    });

    test('plan seviyesinde bölge ardışık iki güne kalır, tapınak silinir', () {
      DayPlan day(int number, List<TimelineItem> items) => DayPlan(
            dayNumber: number,
            date: '2026-10-1$number',
            theme: 'Test',
            items: items,
          );
      TimelineItem activity(
        String id,
        String title, {
        String? placeId,
        RepeatSignals? repeat,
      }) =>
          TimelineItem(
            id: id,
            title: title,
            placeId: placeId,
            cityId: 'tokyo',
            kind: TimelineItemKind.activity,
            durationMin: 90,
            repeat: repeat,
          );

      final days = [
        day(1, [
          activity('a1', 'Akihabara',
              placeId: 'tk-akihabara',
              repeat: const RepeatSignals(isRepeatableZone: true)),
          activity('s1', 'Senso-ji (Asakusa)', placeId: 'tk-sensoji'),
        ]),
        day(2, [
          activity('a2', 'Akihabara',
              placeId: 'tk-akihabara',
              repeat: const RepeatSignals(isRepeatableZone: true)),
          activity('s2', 'Sensoji', placeId: 'tk-sensoji'),
        ]),
      ];

      final duplicates = findConsecutiveActivityDuplicates(days);
      expect(duplicates, hasLength(1));
      expect(duplicates.single.identity, 'tokyo:sensoji');
      expect(duplicates.single.policy, 'hardZero');

      final cleaned = removeConsecutiveActivityDuplicates(days);
      final secondDayIds = cleaned[1].items.map((i) => i.id).toList();
      expect(secondDayIds, contains('a2'), reason: 'bölge korunmalı');
      expect(secondDayIds, isNot(contains('s2')), reason: 'tapınak silinmeli');
      expect(findConsecutiveActivityDuplicates(cleaned), isEmpty);
    });

    test('userExplicitSelection ardışık tekrarı korur', () {
      final days = [
        DayPlan(dayNumber: 1, date: '2026-10-11', theme: 'T', items: [
          TimelineItem(
            id: 'u1',
            title: 'Senso-ji',
            placeId: 'tk-sensoji',
            cityId: 'tokyo',
            kind: TimelineItemKind.activity,
            repeat: const RepeatSignals(userExplicitSelection: true),
          ),
        ]),
        DayPlan(dayNumber: 2, date: '2026-10-12', theme: 'T', items: [
          TimelineItem(
            id: 'u2',
            title: '浅草寺',
            placeId: 'tk-sensoji',
            cityId: 'tokyo',
            kind: TimelineItemKind.activity,
            repeat: const RepeatSignals(userExplicitSelection: true),
          ),
        ]),
      ];
      expect(findConsecutiveActivityDuplicates(days), isEmpty);
      expect(
        removeConsecutiveActivityDuplicates(days)[1].items,
        hasLength(1),
      );
    });
  });

  // =========================================================================
  // JSON v3 sözleşmesi
  // =========================================================================
  group('JSON v3 geriye uyumluluğu', () {
    test('Trip kök dokümanı zorunlu schemaVersion 3 alanını üretir', () {
      final trip = Trip(
        id: 'plan-v3',
        slug: 'plan-v3',
        title: 'Japan',
        timezone: 'Asia/Tokyo',
        tripStart: '2026-10-12',
        tripEnd: '2026-10-13',
        flights: TripFlights(),
        preferences: TripPreferences(
          travelDates: TravelDates(
            start: '2026-10-12',
            end: '2026-10-13',
          ),
          pace: Pace.moderate,
        ),
        days: [
          DayPlan(
            dayNumber: 1,
            date: '2026-10-12',
            theme: 'Tokyo',
          ),
        ],
      );

      final json = trip.toJson();
      expect(json['schemaVersion'], Trip.currentSchemaVersion);
      expect(json['schemaVersion'], 3);
      expect(json['days'], isA<List<dynamic>>());
      expect(Trip.fromJson(json).toJson()['schemaVersion'], 3);
    });

    test('v2 dokümanı kayıpsız açılır ve v3 alanı eklemez', () {
      final v2 = {
        'id': 'x1',
        'title': '🗼 Tokyo Skytree',
        'placeId': 'tk-skytree',
        'kind': 'activity',
        'time': '10:00',
        'durationMin': 90,
        'cityId': 'tokyo',
      };
      final item = TimelineItem.fromJson(v2);
      expect(item.transit, isNull);
      expect(item.closure, isNull);
      expect(item.canonicalPlaceHash, isNull);
      expect(item.toJson(), v2);
    });

    test('v2 repeatAllowed bayrağı userOverride\'a yükseltilir', () {
      final item = TimelineItem.fromJson({
        'id': 'x2',
        'title': 'Universal Studios Japan',
        'kind': 'activity',
        'repeatAllowed': true,
      });
      expect(item.repeat, isNotNull);
      expect(item.repeat!.policy, 'userOverride');
      expect(item.allowsRepeat, isTrue);
      expect(repeatRuleOf(item).isUserOverride, isTrue);
    });

    test('v3 sinyalleri round-trip korunur', () {
      final item = TimelineItem(
        id: 'x3',
        title: 'Shinjuku → Kyoto',
        canonicalPlaceHash: stableHash('kyoto:kiyomizudera'),
        isCityTransition: true,
        kind: TimelineItemKind.transport,
        transit: const TransitSignals(
          hasTrafficRiskDisclaimer: true,
          trafficRiskMultiplier: 1.3,
          stationNavigationBufferMin: 15,
          requestedService: 'nozomi',
          effectiveService: 'hikari',
          railPass: 'nationalJrPass',
          disclaimers: ['railPassDowngrade', 'trafficRisk'],
        ),
        repeat: const RepeatSignals(
          policy: 'timeQuota',
          recommendedTotalMinutes: 240,
          completedMinutes: 60,
        ),
        closure: const ClosureSignals(
          weeklyClosedWeekdays: [1],
          holidayShiftApplied: true,
          closureCause: 'shiftedClosure',
          shiftedFromDate: '2026-10-12',
        ),
      );
      final round = TimelineItem.fromJson(item.toJson());
      expect(round.canonicalPlaceHash, item.canonicalPlaceHash);
      expect(round.transit!.isServiceDowngraded, isTrue);
      expect(round.transit!.stationNavigationBufferMin, 15);
      expect(round.transit!.trafficRiskMultiplier, 1.3);
      expect(round.repeat!.remainingQuotaMinutes, 180);
      expect(round.closure!.holidayShiftApplied, isTrue);
      expect(round.closure!.shiftedFromDate, '2026-10-12');
    });

    test('varsayılan sinyaller JSON\'a yazılmaz', () {
      final item = TimelineItem(
        id: 'x4',
        title: 'Plain',
        transit: const TransitSignals(),
        repeat: const RepeatSignals(),
        closure: const ClosureSignals(),
      );
      final json = item.toJson();
      expect(json.containsKey('transit'), isFalse);
      expect(json.containsKey('repeat'), isFalse);
      expect(json.containsKey('closure'), isFalse);
    });

    test('DayPlan luggage/crowd round-trip', () {
      final day = DayPlan(
        dayNumber: 3,
        date: '2026-10-15',
        theme: 'Kyoto',
        luggage: const LuggageSignals(
          strategy: 'yamatoForward',
          size: 'large',
          bagCount: 2,
          originHandoverMin: 20,
          estimatedCostYen: 4400,
          baggageAvailableAfterDays: 1,
          advisories: ['yamatoOvernightBagRequired'],
          reasonCode: 'yamato-forward',
        ),
        crowd: const CrowdSignals(
          season: 'goldenWeek',
          durationMultiplier: 1.25,
          walkingMultiplier: 1.15,
          isPublicHoliday: true,
        ),
      );
      final round = DayPlan.fromJson(day.toJson());
      expect(round.luggage!.strategy, 'yamatoForward');
      expect(round.luggage!.bypassesStationLuggageBuffer, isTrue);
      expect(round.luggage!.totalScheduleImpactMin, 20);
      expect(round.crowd!.season, 'goldenWeek');
      expect(round.crowd!.durationMultiplier, 1.25);
    });

    test('CityTransitionPlan v3 seçenekleri ve seçili mod tutarlıdır', () {
      final plan = CityTransitionPlan(
        fromCity: 'Tokyo',
        toCity: 'Kyoto',
        mode: 'bus',
        railPass: 'nationalJrPass',
        durationMinutes: 371,
        options: cityTransitionOptionsFor(
          fromCity: 'Tokyo',
          toCity: 'Kyoto',
          railPass: RailPassType.nationalJrPass,
        ),
      );
      final round = CityTransitionPlan.fromJson(plan.toJson());
      expect(round.mode, 'bus');
      expect(round.railPass, 'nationalJrPass');
      expect(round.options, isNotEmpty);
      expect(round.selectedOption, isNotNull);
      expect(round.selectedOption!.mode, 'bus');
      expect(round.selectedOption!.hasTrafficRiskDisclaimer, isTrue);
      expect(
          railPassFromJsonValue(round.railPass), RailPassType.nationalJrPass);
      expect(railPassFromJsonValue(null), RailPassType.none);
    });
  });

  // =========================================================================
  // Geriye uyumluluk: field == null iken v2 davranışı
  // =========================================================================
  group('field == null iken v2 davranışı korunur', () {
    test('aynı istek, field olmadan ve field ile aynı rotayı üretir', () async {
      final day = DateTime(2026, 6, 15); // normal sezon, Pazartesi değil
      Future<OptimizationResult> run({required bool withField}) =>
          const BeamSearchItineraryOptimizer().optimize(OptimizationRequest(
            activities: [
              OptimizationActivity(
                id: 'a',
                name: 'A',
                day: day,
                location: _quietStop,
                durationMinutes: 60,
                minimumDurationMinutes: 60,
              ),
              OptimizationActivity(
                id: 'b',
                name: 'B',
                day: day,
                location: _hotel,
                durationMinutes: 45,
                minimumDurationMinutes: 45,
              ),
            ],
            routeMatrix: _matrix([_hotel, _quietStop]),
            constraints: DayRouteConstraints(
              startLocation: _hotel,
              endLocation: _hotel,
              availableStartTime: DateTime(2026, 6, 15, 9),
              availableEndTime: DateTime(2026, 6, 15, 20),
            ),
            field: withField
                ? FieldRealityContext(travelDate: day, cityId: 'tokyo')
                : null,
          ));

      final plain = await run(withField: false);
      final field = await run(withField: true);

      expect(plain.isSuccess, isTrue);
      expect(field.isSuccess, isTrue);
      expect(
        field.activities.map((a) => a.activityId).toList(),
        plain.activities.map((a) => a.activityId).toList(),
      );
      expect(field.metrics!.score, plain.metrics!.score);
      expect(
          field.metrics!.totalTravelMinutes, plain.metrics!.totalTravelMinutes);
    });
  });
}
