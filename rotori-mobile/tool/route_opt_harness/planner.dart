import 'dart:math';

import 'package:rotori/domain/itinerary_optimizer.dart';
import 'package:rotori/domain/route_matrix.dart';
import 'package:rotori/domain/route_optimization_validator.dart';
import 'package:rotori/domain/trip_activity_assignment.dart' as assignment;

import 'matrix_builder.dart';
import 'poi_data.dart';
import 'scenario.dart';

/// Bir senaryoyu gün-gün planlar ve JSON'a hazır Map üretir.
class TripPlanner {
  TripPlanner({this.beamWidth = 6});

  final int beamWidth;

  final _matrixBuilder = const MatrixBuilder();

  RouteOptimizationProfile _profile(String name) => switch (name) {
        'fastest' => RouteOptimizationProfile.fastest,
        'leastWalking' => RouteOptimizationProfile.leastWalking,
        'cheapest' => RouteOptimizationProfile.cheapest,
        _ => RouteOptimizationProfile.balanced,
      };

  Future<Map<String, dynamic>> plan(
    ScenarioSpec spec, {
    SuiteMode suiteMode = SuiteMode.product,
  }) async {
    final tripDays = _buildTripDays(spec);
    final productAssignments = suiteMode == SuiteMode.product
        ? _assignProductPois(spec, tripDays)
        : const <int, List<PoiSpec>>{};
    // Şehir başına POI dağıtımı. Konaklama gün sayısı şehrin benzersiz POI
    // sayısını aşabildiğinden (ör. Tokyo 6 gece × 4 POI > havuz), havuz
    // tükenince yeniden karılıp doldurulur. Böylece her tam gün, optimizer'ı
    // gerçekten sınayan dolu bir aday kümesiyle beslenir (test amacı budur).
    final cityPools = <String, List<PoiSpec>>{};
    final cityMasters = <String, List<PoiSpec>>{};
    final rng = Random(9000 + (spec.baseScenarioId ?? spec.id));
    final usedPoiIds = <String>{};
    final repeatFixtureIds = <String>{};
    for (final stay in spec.stays) {
      final master = sightseeingPois(stay.city);
      cityMasters[stay.city] = master;
      cityPools[stay.city] = [...master]..shuffle(rng);
    }

    /// Havuz [need] adet POI'ye yetmiyorsa ana listeyi yeniden karıp ekler.
    /// Yeni turda, hemen önceki turun son POI'lerinin tekrarını olabildiğince
    /// öteler (art arda aynı yer görünmesin diye).
    void refillIfNeeded(String cityKey, int need) {
      final pool = cityPools[cityKey]!;
      if (pool.length >= need) return;
      if (suiteMode == SuiteMode.product) return;
      final master = cityMasters[cityKey]!;
      final recent = pool.map((p) => p.id).toSet();
      final refill = [...master]..shuffle(rng);
      refill.sort((a, b) {
        final ar = recent.contains(a.id) ? 1 : 0;
        final br = recent.contains(b.id) ? 1 : 0;
        return ar.compareTo(br);
      });
      for (final p in refill) {
        if (pool.length >= master.length) break;
        if (!pool.any((e) => e.id == p.id)) pool.add(p);
      }
    }

    final dayJsons = <Map<String, dynamic>>[];
    var tripTravel = 0, tripWalk = 0, tripTransfers = 0, tripCost = 0;
    var tripPartyCost = 0;
    var interCityPerPerson = 0, interCityParty = 0;
    var airportPerPerson = 0, airportParty = 0;
    var feasibleDays = 0, infeasibleDays = 0, droppedTotal = 0;
    var strictFeasibleDays = 0;
    var recoveredByDroppingDays = 0;
    var optimizerEvaluatedDays = 0;
    var departureOnlyDays = 0;

    for (final td in tripDays) {
      final date = spec.startDate.add(Duration(days: td.globalIndex));
      final city = cities[td.city]!;
      final pool = cityPools[td.city]!;

      // Bu güne kaç POI ayrılacak?
      final poiCount = switch (td.type) {
        _DayType.arrival => 2,
        _DayType.transfer => 2,
        _DayType.full => 3,
        _DayType.departure => 0,
      };

      // Tam gün özel POI (tema parkı / uzak gezi) varsa güne tek başına ata.
      // Önce havuzu yeterince doldur, SONRA özel POI ara — böylece refill ile
      // gelen bir tema parkı diğer noktalarla aynı güne karışmaz (baseline
      // hatası). durationMin>=300 magic number yerine açık dayRole kullanılır.
      final dayPois = <PoiSpec>[];
      if (suiteMode == SuiteMode.product) {
        dayPois.addAll(productAssignments[td.globalIndex] ?? const []);
      } else if (td.type != _DayType.departure) {
        refillIfNeeded(td.city, poiCount);
        // Tam gün özel park yalnız gerçek tam güne izole edilir; kısa
        // varış/transfer gününe konsa sığmaz ve düşerdi. Uzak gezi (excursion)
        // her gün tipinde tek başına atanabilir.
        final isolateFullDay = td.type == _DayType.full;
        final exclusiveIndex = pool.indexWhere((p) =>
            p.dayRole == PoiDayRole.excursion ||
            (isolateFullDay && p.dayRole == PoiDayRole.fullDayExclusive));
        if (exclusiveIndex >= 0) {
          dayPois.add(pool.removeAt(exclusiveIndex));
        }
      }
      if (suiteMode == SuiteMode.stress && dayPois.isEmpty) {
        refillIfNeeded(td.city, poiCount);
        // Kısa günlerde (varış/transfer) tam gün park seçme; tam güne bırak.
        final skipFullDay = td.type != _DayType.full;
        for (var i = 0; i < poiCount && pool.isNotEmpty;) {
          final idx = skipFullDay
              ? pool.indexWhere((p) => p.dayRole != PoiDayRole.fullDayExclusive)
              : 0;
          if (idx < 0) break;
          dayPois.add(pool.removeAt(idx));
          i++;
        }
      }
      for (final poi in dayPois) {
        if (!usedPoiIds.add(poi.id)) repeatFixtureIds.add(poi.id);
      }

      Map<String, dynamic> dayJson;
      switch (td.type) {
        case _DayType.departure:
          dayJson = _departureDay(spec, td, date, city);
          break;
        default:
          dayJson = await _sightseeingDay(
            spec,
            td,
            date,
            city,
            dayPois,
            repeatFixtureIds,
          );
          break;
      }

      // Ulaşım öncesi transfer/varış bloklarını ekle.
      if (td.type == _DayType.arrival) {
        final block = _arrivalBlock(spec, td.city, date);
        dayJson['arrivalTransfer'] = block;
        airportPerPerson += block['airportCostPerPersonYen'] as int;
        airportParty += block['airportPartyTotalYen'] as int;
        interCityPerPerson += block['interCityCostPerPersonYen'] as int;
        interCityParty += block['interCityPartyTotalYen'] as int;
      } else if (td.type == _DayType.transfer) {
        final block = _shinkansenBlock(td.prevCity!, td.city, spec, date);
        dayJson['cityTransfer'] = block;
        interCityPerPerson += block['costPerPersonYen'] as int;
        interCityParty += block['partyTotalCostYen'] as int;
      } else if (td.type == _DayType.departure) {
        final block = dayJson['departureTransfer'] as Map<String, dynamic>;
        airportPerPerson += block['airportCostPerPersonYen'] as int;
        airportParty += block['airportPartyTotalYen'] as int;
        interCityPerPerson += block['interCityCostPerPersonYen'] as int;
        interCityParty += block['interCityPartyTotalYen'] as int;
      }

      // Toplamlara ekle.
      final m = dayJson['metrics'];
      if (m is Map) {
        tripTravel += (m['travelMin'] as int? ?? 0);
        tripWalk += (m['walkingMin'] as int? ?? 0);
        tripTransfers += (m['transfers'] as int? ?? 0);
        tripCost += (m['costPerPersonYen'] as int? ?? 0);
        tripPartyCost += (m['partyTotalCostYen'] as int? ?? 0);
      }
      if (dayJson['feasible'] == true) {
        feasibleDays++;
      } else if (dayJson['type'] != 'departure') {
        infeasibleDays++;
      }
      if (dayJson['optimizerEvaluated'] == true) {
        optimizerEvaluatedDays++;
      } else {
        departureOnlyDays++;
      }
      if (dayJson['strictFeasible'] == true) strictFeasibleDays++;
      if (dayJson['recoveredByDropping'] == true) {
        recoveredByDroppingDays++;
      }
      droppedTotal += (dayJson['droppedActivityCount'] as int?) ?? 0;

      dayJsons.add(dayJson);
    }

    return {
      'id': spec.id,
      'baseScenarioId': spec.baseScenarioId ?? spec.id,
      'title': spec.title,
      'party': {
        'adults': spec.adults,
        'children': spec.children,
        'total': spec.party,
      },
      'profile': spec.profile,
      'suiteMode': suiteMode.name,
      'entryAirport': spec.entryAirport,
      'exitAirport': spec.exitAirport,
      'dailyWindow':
          '${_h(spec.dailyStartHour)}:00–${_h(spec.dailyEndHour)}:00',
      'cities':
          spec.stays.map((s) => {'city': s.city, 'nights': s.nights}).toList(),
      'totalDays': spec.totalDays,
      'days': dayJsons,
      'tripTotals': {
        'feasibleDays': feasibleDays,
        'infeasibleDays': infeasibleDays,
        'droppedActivities': droppedTotal,
        'optimizerEvaluatedDays': optimizerEvaluatedDays,
        'strictFeasibleDays': strictFeasibleDays,
        'recoveredByDroppingDays': recoveredByDroppingDays,
        'departureOnlyDays': departureOnlyDays,
        'inCityTravelMin': tripTravel,
        'inCityWalkingMin': tripWalk,
        'inCityTransfers': tripTransfers,
        'inCityTransportCostYen': tripCost,
        'inCityCostPerPersonYen': tripCost,
        'inCityPartyTotalYen': tripPartyCost,
        'interCityCostPerPersonYen': interCityPerPerson,
        'interCityPartyTotalYen': interCityParty,
        'airportCostPerPersonYen': airportPerPerson,
        'airportPartyTotalYen': airportParty,
        'grandTotalPerPersonYen':
            tripCost + interCityPerPerson + airportPerPerson,
        'grandTotalPartyYen': tripPartyCost + interCityParty + airportParty,
      },
    };
  }

  Map<int, List<PoiSpec>> _assignProductPois(
    ScenarioSpec spec,
    List<_TripDay> tripDays,
  ) {
    final result = <int, List<PoiSpec>>{};
    for (final stay in spec.stays) {
      final city = cities[stay.city]!;
      final cityDays = tripDays.where((day) => day.city == stay.city).toList();
      final assignmentDays = cityDays.map((day) {
        final date = spec.startDate.add(Duration(days: day.globalIndex));
        final dayStart = spec.dailyStartHour * 60;
        final transferReady = switch (day.type) {
          _DayType.arrival => 10 * 60 + _arrivalDuration(spec, day.city) + 60,
          _DayType.transfer => 8 * 60 +
              shinkansenBetween(day.prevCity!, day.city).minutes +
              40 +
              45,
          _ => dayStart,
        };
        final availableStart = max(dayStart, transferReady);
        final startHour = availableStart ~/ 60;
        final startMinute = availableStart % 60;
        return assignment.TripAssignmentDay(
          index: day.globalIndex,
          city: stay.city,
          type: switch (day.type) {
            _DayType.arrival => assignment.AssignmentDayType.arrival,
            _DayType.full => assignment.AssignmentDayType.full,
            _DayType.transfer => assignment.AssignmentDayType.transfer,
            _DayType.departure => assignment.AssignmentDayType.departure,
          },
          startTime: DateTime(
            date.year,
            date.month,
            date.day,
            startHour,
            startMinute,
          ),
          endTime: DateTime(
            date.year,
            date.month,
            date.day,
            spec.dailyEndHour,
          ),
          hotel: TripLocation(
            id: city.hotelId,
            name: city.hotelName,
            latitude: city.hotelLat,
            longitude: city.hotelLng,
            city: city.name,
            clusterId: city.hotelCluster,
          ),
          requiredMealMinutes: day.type == _DayType.full ? 230 : 95,
          minimumTransitionMinutes: 20,
          returnMinutes: 25,
          maxActivities: switch (day.type) {
            _DayType.arrival || _DayType.transfer => 2,
            _DayType.full => 3,
            _DayType.departure => 0,
          },
        );
      }).toList(growable: false);
      final poiById = {
        for (final poi in sightseeingPois(stay.city))
          if ((poi.dayRole != PoiDayRole.fullDayExclusive &&
                  poi.dayRole != PoiDayRole.excursion) ||
              cityDays.any((day) => day.type == _DayType.full))
            poi.id: poi,
      };
      final assignables = poiById.values.map((poi) {
        final day = spec.startDate;
        return assignment.AssignableTripActivity(
          city: stay.city,
          dayRole: switch (poi.dayRole) {
            PoiDayRole.normal => assignment.ActivityDayRole.normal,
            PoiDayRole.halfDayAnchor =>
              assignment.ActivityDayRole.halfDayAnchor,
            PoiDayRole.fullDayExclusive =>
              assignment.ActivityDayRole.fullDayExclusive,
            PoiDayRole.excursion => assignment.ActivityDayRole.excursion,
          },
          activity: OptimizationActivity(
            id: poi.id,
            name: poi.name,
            day: day,
            location: TripLocation(
              id: poi.id,
              name: poi.name,
              latitude: poi.lat,
              longitude: poi.lng,
              city: poi.city,
              clusterId: poi.cluster,
            ),
            durationMinutes: poi.durationMin,
            minimumDurationMinutes: max(20, (poi.durationMin * .7).round()),
            openingTime: poi.openHour == 0
                ? null
                : DateTime(day.year, day.month, day.day, poi.openHour),
            closingTime: poi.closeHour == 24
                ? null
                : DateTime(day.year, day.month, day.day, poi.closeHour),
            priority: poi.dayRole == PoiDayRole.fullDayExclusive ||
                    poi.dayRole == PoiDayRole.excursion
                ? ActivityPriority.mustDo
                : ActivityPriority.normal,
            category: poi.category,
          ),
        );
      }).toList(growable: false);
      final assigned = const assignment.TripActivityAssignmentEngine().assign(
        days: assignmentDays,
        activities: assignables,
      );
      if (!assigned.isSuccess) {
        throw StateError(assigned.failure!.message);
      }
      for (final entry in assigned.assignments.entries) {
        result[entry.key] = entry.value
            .map((item) => poiById[item.activity.id]!)
            .toList(growable: false);
      }
    }
    return result;
  }

  // -------------------- Gün tipi zinciri --------------------

  List<_TripDay> _buildTripDays(ScenarioSpec spec) {
    final days = <_TripDay>[];
    var globalIndex = 0;
    String? prevCity;
    for (var s = 0; s < spec.stays.length; s++) {
      final stay = spec.stays[s];
      for (var d = 0; d < stay.nights; d++) {
        final isFirstOverall = globalIndex == 0;
        final isFirstOfCity = d == 0;
        _DayType type;
        if (isFirstOverall) {
          type = _DayType.arrival;
        } else if (isFirstOfCity) {
          type = _DayType.transfer;
        } else {
          type = _DayType.full;
        }
        days.add(_TripDay(
          globalIndex: globalIndex,
          city: stay.city,
          type: type,
          prevCity: isFirstOfCity ? prevCity : null,
        ));
        globalIndex++;
      }
      prevCity = stay.city;
    }
    // Son günü daima dönüş yap (havaalanına gidiş).
    if (days.isNotEmpty) {
      final last = days.last;
      days[days.length - 1] = _TripDay(
        globalIndex: last.globalIndex,
        city: last.city,
        type: _DayType.departure,
        prevCity: last.prevCity,
      );
    }
    return days;
  }

  // -------------------- Gezi günü (optimizer) --------------------

  Future<Map<String, dynamic>> _sightseeingDay(
    ScenarioSpec spec,
    _TripDay td,
    DateTime date,
    CitySpec city,
    List<PoiSpec> dayPois,
    Set<String> repeatFixtureIds,
  ) async {
    final startOfDayMinutes = spec.dailyStartHour * 60;
    final transferReadyMinutes = switch (td.type) {
      _DayType.arrival => 10 * 60 + _arrivalDuration(spec, td.city) + 60,
      _DayType.transfer =>
        8 * 60 + shinkansenBetween(td.prevCity!, td.city).minutes + 40 + 45,
      _ => startOfDayMinutes,
    };
    final availableStartMinutes = max(startOfDayMinutes, transferReadyMinutes);
    final startHour = availableStartMinutes ~/ 60;
    final startMinute = availableStartMinutes % 60;
    final endHour = spec.dailyEndHour;

    final hotel = TripLocation(
      id: city.hotelId,
      name: city.hotelName,
      latitude: city.hotelLat,
      longitude: city.hotelLng,
      city: city.name,
      district: city.hotelCluster,
      clusterId: city.hotelCluster,
    );

    final activities = <OptimizationActivity>[];
    String? syntheticMealNote;

    // Tema parkı günü: 8 saatlik tek blok gün penceresini neredeyse tümüyle
    // doldurur. Ziyaretçi kahvaltı/öğle/akşamı parkın içinde alır; ayrı
    // oturmalı öğün eklenmez (aksi halde park bloğu bölünür veya sığmaz).
    final isThemeparkDay =
        dayPois.any((p) => p.dayRole == PoiDayRole.fullDayExclusive);

    // Kahvaltı: yalnızca tam günlerde (tema parkı günleri hariç), otelde sabah.
    if (td.type == _DayType.full && !isThemeparkDay) {
      final brk = TripLocation(
        id: city.hotelId,
        name: '${city.hotelName} kahvaltı',
        latitude: city.hotelLat,
        longitude: city.hotelLng,
        city: city.name,
        district: city.hotelCluster,
        clusterId: city.hotelCluster,
      );
      activities.add(OptimizationActivity(
        id: 'breakfast_${td.globalIndex}',
        name: 'Kahvaltı',
        day: date,
        location: brk,
        durationMinutes: 35,
        minimumDurationMinutes: 25,
        openingTime: DateTime(date.year, date.month, date.day, startHour, 0),
        closingTime:
            DateTime(date.year, date.month, date.day, startHour + 2, 0),
        preferredTime: TimeOfDayPreference.morning,
        category: 'meal',
        priority: ActivityPriority.mustDo,
      ));
    }

    // Gezilecek noktalar.
    for (final p in dayPois) {
      final loc = TripLocation(
        id: p.id,
        name: p.name,
        latitude: p.lat,
        longitude: p.lng,
        city: p.city,
        district: p.cluster,
        clusterId: p.cluster,
      );
      final open = (p.openHour == 0 && p.closeHour == 24)
          ? null
          : DateTime(date.year, date.month, date.day, p.openHour, 0);
      final close = (p.openHour == 0 && p.closeHour == 24)
          ? null
          : DateTime(date.year, date.month, date.day, p.closeHour, 0);
      activities.add(OptimizationActivity(
        id: p.id,
        name: p.name,
        day: date,
        location: loc,
        durationMinutes: p.durationMin,
        minimumDurationMinutes: max(20, (p.durationMin * 0.7).round()),
        openingTime: open,
        closingTime: close,
        category: p.category,
      ));
    }

    // Öğle yemeği (fixed ~12:30) — gün öğlen açık pencereyi kapsıyorsa.
    // Tema parkı günlerinde ayrı oturmalı öğle yemeği eklenmez; ziyaretçi
    // öğünü parkın içinde alır ve 8 saatlik blok bölünmez.
    final lunchAnchor = startHour + (startMinute > 0 ? 1 : 0);
    if (lunchAnchor <= 13 &&
        td.type != _DayType.arrival &&
        dayPois.isNotEmpty &&
        !isThemeparkDay) {
      final venue = _mealVenue(city, dayPois, 'lunch', td.globalIndex);
      // Aktivite penceresi = öğün penceresi ∩ yerin çalışma saati.
      final openH = venue.openHour > 11 ? venue.openHour : 11;
      final closeH = venue.closeHour < 15 ? venue.closeHour : 15;
      final startH = openH < 12 ? 12 : openH;
      activities.add(OptimizationActivity(
        id: 'lunch_${td.globalIndex}',
        name: 'Öğle yemeği · ${venue.location.name}',
        day: date,
        location: venue.location,
        durationMinutes: 60,
        minimumDurationMinutes: 40,
        openingTime: DateTime(
            date.year, date.month, date.day, (startH - 1).clamp(11, 13), 30),
        closingTime: DateTime(date.year, date.month, date.day, closeH, 0),
        preferredTime: TimeOfDayPreference.afternoon,
        category: 'meal',
        priority: ActivityPriority.mustDo,
      ));
    }

    // Akşam yemeği (~19:00) — yalnız akşam servisi veren açık bir yer varsa.
    // Uygun yer yoksa gerçekçi saatli sentetik lokanta üretilir ve warning
    // olarak işaretlenir. Tema parkı günlerinde ayrı akşam yemeği eklenmez.
    if (endHour >= 20 && dayPois.isNotEmpty && !isThemeparkDay) {
      final venue = _mealVenue(city, dayPois, 'dinner', td.globalIndex);
      // Aktivite penceresi yerin çalışma saatiyle kısıtlanır.
      final openH = venue.openHour > 18 ? venue.openHour : 18;
      final closeH = venue.closeHour < endHour ? venue.closeHour : endHour;
      if (closeH - openH >= 1) {
        activities.add(OptimizationActivity(
          id: 'dinner_${td.globalIndex}',
          name: 'Akşam yemeği · ${venue.location.name}',
          day: date,
          location: venue.location,
          durationMinutes: 75,
          minimumDurationMinutes: 55,
          openingTime: DateTime(date.year, date.month, date.day, openH, 0),
          closingTime: DateTime(date.year, date.month, date.day, closeH, 0),
          preferredTime: TimeOfDayPreference.evening,
          category: 'meal',
          priority: ActivityPriority.mustDo,
        ));
        if (venue.isSynthetic) {
          syntheticMealNote =
              'Uygun akşam restoranı bulunamadı; sentetik lokanta kullanıldı.';
        }
      }
    }

    if (activities.isEmpty) {
      return _emptyDay(td, date, city, 'Bu güne aktivite atanmadı.');
    }

    // Matris için tüm lokasyonlar (otel + aktiviteler).
    final locSet = <String, TripLocation>{hotel.id: hotel};
    for (final a in activities) {
      locSet[a.location.id] = a.location;
    }
    final matrix = _matrixBuilder.build(
      locSet.values.toList(),
      departureTime:
          DateTime(date.year, date.month, date.day, startHour, startMinute),
    );

    final request = OptimizationRequest(
      activities: activities,
      routeMatrix: matrix,
      constraints: DayRouteConstraints(
        startLocation: hotel,
        endLocation: hotel,
        availableStartTime:
            DateTime(date.year, date.month, date.day, startHour, startMinute),
        availableEndTime: DateTime(date.year, date.month, date.day, endHour, 0),
      ),
      preferences: RoutePreferences(
        profile: _profile(spec.profile),
        maximumWalkingMinutes: spec.hasChild ? 150 : 240,
        partySize: spec.party,
        luggageState: td.type == _DayType.transfer
            ? LuggageState.carried
            : LuggageState.none,
      ),
    );

    final strictResult = await BeamSearchItineraryOptimizer(
      config: OptimizerConfig(
        beamWidth: beamWidth,
        allowActivityDropping: false,
      ),
    ).optimize(request);
    final strictFeasible = strictResult.isSuccess;
    final result = strictFeasible
        ? strictResult
        : await BeamSearchItineraryOptimizer(
            config: OptimizerConfig(
              beamWidth: beamWidth,
              allowActivityDropping: true,
            ),
          ).optimize(request);
    final validationIssues = result.isSuccess
        ? const RouteOptimizationValidator().validate(request, result)
        : const <RouteValidationIssue>[];
    return _dayFromResult(
      spec,
      td,
      date,
      city,
      startHour,
      startMinute,
      endHour,
      result,
      inputActivities: activities,
      repeatFixtureIds: repeatFixtureIds,
      requestedActivityCount: activities.length,
      strictFeasible: strictFeasible,
      validationIssues: validationIssues,
      syntheticMealNote: syntheticMealNote,
    );
  }

  Map<String, dynamic> _dayFromResult(
    ScenarioSpec spec,
    _TripDay td,
    DateTime date,
    CitySpec city,
    int startHour,
    int startMinute,
    int endHour,
    OptimizationResult result, {
    required List<OptimizationActivity> inputActivities,
    required Set<String> repeatFixtureIds,
    required int requestedActivityCount,
    required bool strictFeasible,
    required List<RouteValidationIssue> validationIssues,
    String? syntheticMealNote,
  }) {
    final scheduledActivityCount = result.activities.length;
    final droppedActivityCount = result.droppedActivityIds.length;
    final base = {
      'dayIndex': td.globalIndex + 1,
      'date': _date(date),
      'city': city.name,
      'type': td.type.name,
      'window': '${_h(startHour)}:${_m(startMinute)}–${_h(endHour)}:00',
      'startsAtHotel': city.hotelName,
      'endsAtHotel': city.hotelName,
      'optimizerEvaluated': true,
      'strictFeasible': strictFeasible,
      'recoveredByDropping':
          !strictFeasible && result.isSuccess && droppedActivityCount > 0,
      'requestedActivityCount': requestedActivityCount,
      'scheduledActivityCount': scheduledActivityCount,
      'droppedActivityCount': droppedActivityCount,
      'hardViolationCount': validationIssues.length,
    };

    if (!result.isSuccess) {
      return {
        ...base,
        'feasible': false,
        'failureCode': result.failure?.code.name,
        'failureMessage': result.failure?.message,
        'schedule': const <Map<String, dynamic>>[],
        'droppedActivityIds': const <String>[],
        'metrics': _zeroMetrics(),
        'warnings': result.warnings,
      };
    }

    final schedule = result.activities.map((a) {
      final leg = a.inboundLeg;
      return {
        'start': _time(a.startTime),
        'end': _time(a.endTime),
        'name': a.activity.name,
        'category': a.activity.category,
        'durationMin': a.endTime.difference(a.startTime).inMinutes,
        'fixed': a.activity.hasFixedSchedule,
        'inbound': {
          'mode': leg.mode.name,
          'travelMin': leg.travelDurationMinutes,
          'walkMin': leg.walkingDurationMinutes,
          'waitMin': leg.waitingDurationMinutes,
          'transitWaitMin': leg.transitWaitMinutes,
          'scheduleIdleMin': leg.scheduleIdleMinutes,
          'bufferMin': leg.bufferMinutes,
          'transfers': leg.transferCount,
          'costYen': leg.estimatedCostYen,
          'costPerPersonYen': leg.costPerPersonYen,
          'partyTotalCostYen': leg.partyTotalCostYen,
          'vehicleCount': leg.vehicleCount,
          'fareBasis': leg.fareBasis.name,
          'isEstimated': leg.isEstimated,
          'depart': _time(leg.departureTime),
          'arrive': _time(leg.arrivalTime),
        },
        'reason': a.optimizationReason,
        'warnings': a.warnings,
      };
    }).toList();

    final timeline = <Map<String, dynamic>>[];
    for (final activity in result.activities) {
      final leg = activity.inboundLeg;
      if (leg.travelDurationMinutes > 0) {
        timeline.add(_legJson('transit', leg));
      }
      if (leg.scheduleIdleMinutes > 0) {
        final isFreeTime = leg.scheduleIdleMinutes > 30;
        timeline.add({
          'kind': isFreeTime ? 'freeTime' : 'idle',
          'start':
              _time(leg.arrivalTime.add(Duration(minutes: leg.bufferMinutes))),
          'end': _time(activity.startTime),
          'minutes': leg.scheduleIdleMinutes,
          'reason':
              isFreeTime ? 'serbest_zaman' : 'venue_opening_or_fixed_time',
        });
      }
      timeline.add({
        'kind': 'activity',
        'activityId': activity.activity.id,
        'locationId': activity.location.id,
        'start': _time(activity.startTime),
        'end': _time(activity.endTime),
      });
    }
    if (result.legs.isNotEmpty) {
      timeline.add(_legJson('return', result.legs.last));
    }

    final m = result.metrics!;
    final delta = result.delta;
    final clusterReentryCount = _clusterReentryCount(result.activities);
    return {
      ...base,
      'feasible': true,
      'inputActivities': inputActivities
          .map((activity) => {
                'id': activity.id,
                'name': activity.name,
                'priority': activity.priority.name,
                'clusterId': activity.clusterId,
                'repeatFixture': repeatFixtureIds.contains(activity.id),
              })
          .toList(growable: false),
      'droppedActivityIds': result.droppedActivityIds,
      'dropped': result.droppedActivities
          .map((activity) => {
                'activityId': activity.activityId,
                'name': activity.name,
                'priority': activity.priority.name,
                'reason': activity.reason.name,
                'attemptedDayIndexes': activity.attemptedDayIndexes,
                if (activity.conflictingActivityId != null)
                  'conflictingActivityId': activity.conflictingActivityId,
              })
          .toList(growable: false),
      'schedule': schedule,
      'timeline': timeline,
      'metrics': {
        'travelMin': m.totalTravelMinutes,
        'walkingMin': m.totalWalkingMinutes,
        'waitingMin': m.totalWaitingMinutes,
        'transitWaitMinutes': m.totalTransitWaitMinutes,
        'scheduleIdleMinutes': result.legs.fold<int>(
          0,
          (sum, leg) =>
              sum +
              (leg.scheduleIdleMinutes <= 30 ? leg.scheduleIdleMinutes : 0),
        ),
        'freeTimeMinutes': result.legs.fold<int>(
          0,
          (sum, leg) =>
              sum +
              (leg.scheduleIdleMinutes > 30 ? leg.scheduleIdleMinutes : 0),
        ),
        'rawScheduleGapMinutes': m.scheduleIdleMinutes,
        'bufferMinutes': result.legs.fold<int>(
          0,
          (sum, leg) => sum + leg.bufferMinutes,
        ),
        'transfers': m.totalTransferCount,
        'transportCostYen': m.estimatedTransportCostYen,
        'costPerPersonYen': result.legs.fold<int>(
          0,
          (sum, leg) => sum + leg.costPerPersonYen,
        ),
        'partyTotalCostYen': m.partyTotalTransportCostYen,
        'backtrackingMin':
            double.parse(m.backtrackingMinutes.toStringAsFixed(2)),
        'evaluatedStateCount': m.evaluatedStateCount,
        'prunedStateCount': m.prunedStateCount,
        'beamWidth': m.beamWidth,
        'routeEfficiency':
            double.parse(m.routeEfficiencyScore.toStringAsFixed(3)),
        'score': double.parse(m.score.toStringAsFixed(2)),
        'objectiveScore': double.parse(m.objectiveScore.toStringAsFixed(2)),
        'clusterReentryCount': clusterReentryCount,
      },
      'delta': {
        'travelMinutes': delta?.travelDeltaMinutes ?? 0,
        'walkingMinutes': delta?.walkingDeltaMinutes ?? 0,
        'scheduleIdleMinutes': delta?.idleDeltaMinutes ?? 0,
        'transferCount': delta?.transferDelta ?? 0,
        'partyCostYen': delta?.partyCostDeltaYen ?? 0,
        'backtrackingMinutes': delta == null
            ? 0
            : double.parse(delta.backtrackingDelta.toStringAsFixed(2)),
        'objectiveScore': delta == null
            ? 0
            : double.parse(delta.objectiveScoreDelta.toStringAsFixed(2)),
        'objectiveImprovementPct': delta == null
            ? 0
            : double.parse(delta.objectiveImprovementPct.toStringAsFixed(2)),
      },
      'stages': {
        'baseline': {
          'available': delta != null,
        },
        'beam': {
          'objectiveScore': double.parse(m.objectiveScore.toStringAsFixed(2)),
          'evaluatedStateCount': m.evaluatedStateCount,
          'prunedStateCount': m.prunedStateCount,
        },
        'localImprovement': {
          'passesApplied': 3,
          'acceptedMoves': result.optimizationChanges,
        },
      },
      'optimizationChanges': result.optimizationChanges,
      'warnings': [
        ...result.warnings,
        ...validationIssues.map((issue) => issue.message),
        if (spec.hasChild)
          'Çocuk tarifesi modellenmedi; maliyetler yetişkin tarifesi varsayar.',
        if (syntheticMealNote != null) syntheticMealNote,
      ],
    };
  }

  Map<String, dynamic> _legJson(String kind, RouteLeg leg) => {
        'kind': kind,
        'fromLocationId': leg.fromLocationId,
        'toLocationId': leg.toLocationId,
        'mode': leg.mode.name,
        'start': _time(leg.departureTime),
        'end': _time(leg.arrivalTime),
        'doorToDoorMinutes': leg.travelDurationMinutes,
        'rideMinutes': leg.rideMinutes,
        'walkingMinutes': leg.walkingDurationMinutes,
        'accessMinutes': leg.accessMinutes,
        'transitWaitMinutes': leg.transitWaitMinutes,
        'bufferMinutes': leg.bufferMinutes,
        'transferCount': leg.transferCount,
        'costPerPersonYen': leg.costPerPersonYen,
        'partyTotalCostYen': leg.partyTotalCostYen,
        'vehicleCount': leg.vehicleCount,
        'fareBasis': leg.fareBasis.name,
        'isEstimated': leg.isEstimated,
        if (leg.providerId != null) 'providerId': leg.providerId,
      };

  int _clusterReentryCount(List<ScheduledActivity> activities) {
    final closed = <String>{};
    String? current;
    var count = 0;
    for (final activity in activities) {
      final next = activity.routeCluster;
      if (next == null) continue;
      if (current != null && current != next) closed.add(current);
      if (next != current &&
          closed.contains(next) &&
          activity.activity.category != 'meal') {
        count++;
      }
      current = next;
    }
    return count;
  }

  Map<String, dynamic> _emptyDay(
      _TripDay td, DateTime date, CitySpec city, String note) {
    return {
      'dayIndex': td.globalIndex + 1,
      'date': _date(date),
      'city': city.name,
      'type': td.type.name,
      'feasible': true,
      'optimizerEvaluated': false,
      'strictFeasible': false,
      'recoveredByDropping': false,
      'requestedActivityCount': 0,
      'scheduledActivityCount': 0,
      'droppedActivityCount': 0,
      'hardViolationCount': 0,
      'note': note,
      'schedule': const <Map<String, dynamic>>[],
      'droppedActivityIds': const <String>[],
      'metrics': _zeroMetrics(),
    };
  }

  // -------------------- Dönüş günü (havaalanına gidiş) --------------------

  Map<String, dynamic> _departureDay(
      ScenarioSpec spec, _TripDay td, DateTime date, CitySpec city) {
    final airport = airports[spec.exitAirport]!;
    final segments = <Map<String, dynamic>>[];
    var totalMin = 0, totalCost = 0, transfers = 0;

    // Farklı bölgeye gidiliyorsa önce shinkansen.
    if (airport.city != city.name) {
      final sk = shinkansenBetween(city.name, airport.city);
      segments.add({
        'segment': 'shinkansen',
        'from': '${city.hotelName} → ${city.shinkansenStation}',
        'to': '${airport.city} istasyonu',
        'mode': 'shinkansen',
        'durationMin': sk.minutes + 20, // otel→istasyon dahil
        'costYen': sk.costYen + 400,
        'transfers': sk.transfers,
      });
      totalMin += sk.minutes + 20;
      totalCost += sk.costYen + 400;
      transfers += sk.transfers;
    }

    segments.add({
      'segment': 'airportAccess',
      'from': '${airport.city} merkez',
      'to': '${airport.name} (${airport.code})',
      'mode': airport.accessMode,
      'durationMin': airport.accessMinutes,
      'costYen': airport.accessCostYen,
      'transfers': 0,
    });
    totalMin += airport.accessMinutes;
    totalCost += airport.accessCostYen;

    return {
      'dayIndex': td.globalIndex + 1,
      'date': _date(date),
      'city': city.name,
      'type': 'departure',
      'feasible': true,
      'optimizerEvaluated': false,
      'strictFeasible': false,
      'recoveredByDropping': false,
      'requestedActivityCount': 0,
      'scheduledActivityCount': 0,
      'droppedActivityCount': 0,
      'hardViolationCount': 0,
      'note': 'Son gün: otelden çıkış, ${airport.name} havaalanına transfer.',
      'departureTransfer': {
        'exitAirport': airport.code,
        'segments': segments,
        'totalDurationMin': totalMin,
        'totalCostYen': totalCost,
        'totalTransfers': transfers,
        'interCityCostPerPersonYen': segments
            .where((segment) => segment['segment'] == 'shinkansen')
            .fold<int>(0, (sum, segment) => sum + (segment['costYen'] as int)),
        'interCityPartyTotalYen': segments
                .where((segment) => segment['segment'] == 'shinkansen')
                .fold<int>(
                    0, (sum, segment) => sum + (segment['costYen'] as int)) *
            spec.party,
        'airportCostPerPersonYen': airport.accessCostYen,
        'airportPartyTotalYen': airport.accessCostYen * spec.party,
        'timeline': _timedSegments(date, 9, segments, spec.party),
      },
      'schedule': const <Map<String, dynamic>>[],
      'droppedActivityIds': const <String>[],
      'metrics': _zeroMetrics(),
    };
  }

  // -------------------- Transfer / varış blokları --------------------

  Map<String, dynamic> _arrivalBlock(
    ScenarioSpec spec,
    String firstCity,
    DateTime date,
  ) {
    final airport = airports[spec.entryAirport]!;
    final city = cities[firstCity]!;
    final segments = <Map<String, dynamic>>[];
    var totalMin = airport.accessMinutes, totalCost = airport.accessCostYen;

    segments.add({
      'segment': 'airportAccess',
      'from': '${airport.name} (${airport.code})',
      'to': '${airport.city} merkez',
      'mode': airport.accessMode,
      'durationMin': airport.accessMinutes,
      'costYen': airport.accessCostYen,
    });

    if (airport.city != firstCity) {
      final sk = shinkansenBetween(airport.city, firstCity);
      segments.add({
        'segment': 'shinkansen',
        'from': '${airport.city} istasyonu',
        'to': '${city.shinkansenStation} → ${city.hotelName}',
        'mode': 'shinkansen',
        'durationMin': sk.minutes + 20,
        'costYen': sk.costYen + 400,
        'transfers': sk.transfers,
      });
      totalMin += sk.minutes + 20;
      totalCost += sk.costYen + 400;
    }

    return {
      'entryAirport': airport.code,
      'segments': segments,
      'totalDurationMin': totalMin,
      'totalCostYen': totalCost,
      'airportCostPerPersonYen': airport.accessCostYen,
      'airportPartyTotalYen': airport.accessCostYen * spec.party,
      'interCityCostPerPersonYen': totalCost - airport.accessCostYen,
      'interCityPartyTotalYen':
          (totalCost - airport.accessCostYen) * spec.party,
      'timeline': _timedSegments(date, 10, segments, spec.party),
      'assumption': 'Uçuş varışı 10:00 ve check-in tamponu varsayıldı.',
      'note': 'İniş → otele yerleşme; öğleden sonra hafif gezi başlar.',
    };
  }

  int _arrivalDuration(ScenarioSpec spec, String firstCity) {
    final airport = airports[spec.entryAirport]!;
    if (airport.city == firstCity) return airport.accessMinutes;
    final interCity = shinkansenBetween(airport.city, firstCity);
    return airport.accessMinutes + interCity.minutes + 20;
  }

  Map<String, dynamic> _shinkansenBlock(
    String fromCity,
    String toCity,
    ScenarioSpec spec,
    DateTime date,
  ) {
    final sk = shinkansenBetween(fromCity, toCity);
    final from = cities[fromCity]!;
    final to = cities[toCity]!;
    return {
      'from': fromCity,
      'to': toCity,
      'route': '${from.hotelName} → ${from.shinkansenStation} → '
          '${to.shinkansenStation} → ${to.hotelName}',
      'mode': 'shinkansen',
      'rideDurationMin': sk.minutes,
      'totalDurationMin': sk.minutes + 40, // otel↔istasyon dahil
      'costYen': sk.costYen + 800,
      'costPerPersonYen': sk.costYen + 800,
      'partyTotalCostYen': (sk.costYen + 800) * spec.party,
      'transfers': sk.transfers,
      'timeline': _timedSegments(
          date,
          8,
          [
            {
              'segment': 'shinkansen',
              'from': fromCity,
              'to': toCity,
              'mode': 'shinkansen',
              'durationMin': sk.minutes + 40,
              'costYen': sk.costYen + 800,
            }
          ],
          spec.party),
      'assumption': 'İstasyon çıkışı ve otele bagaj bırakma tamponu dahildir.',
      'note': 'Sabah check-out + bavul; öğleden sonra yeni şehirde gezi.',
    };
  }

  List<Map<String, dynamic>> _timedSegments(
    DateTime date,
    int startHour,
    List<Map<String, dynamic>> segments,
    int partySize,
  ) {
    var cursor = DateTime(date.year, date.month, date.day, startHour);
    return segments.map((segment) {
      final duration = segment['durationMin'] as int;
      final end = cursor.add(Duration(minutes: duration));
      final cost = segment['costYen'] as int;
      final result = <String, dynamic>{
        'kind': 'fixedTransit',
        'segment': segment['segment'],
        'from': segment['from'],
        'to': segment['to'],
        'mode': segment['mode'],
        'start': _time(cursor),
        'end': _time(end),
        'doorToDoorMinutes': duration,
        'costPerPersonYen': cost,
        'partyTotalCostYen': cost * partySize,
        'fareBasis': FareBasis.perPerson.name,
        'isEstimated': true,
      };
      cursor = end;
      return result;
    }).toList(growable: false);
  }

  // -------------------- Yardımcılar --------------------

  /// Öğün için gerçekten açık bir yer seçer. Uygun yer yoksa gerçekçi saatli
  /// sentetik bir lokanta üretir ve `isSynthetic:true` işaretler. Böylece
  /// kapalı bir markete akşam yemeği yazılmaz (baseline hatası).
  _MealVenue _mealVenue(
      CitySpec city, List<PoiSpec> dayPois, String kind, int idx) {
    final period = kind == 'lunch' ? MealPeriod.lunch : MealPeriod.dinner;
    final winStart = kind == 'lunch' ? 11 : 18;
    final winEnd = kind == 'lunch' ? 15 : 22;
    final needed = kind == 'lunch' ? 40 : 55;

    final candidates = mealVenues(city.name, period, winStart, winEnd, needed);
    if (candidates.isNotEmpty) {
      // Öğle: gezinin ağırlık merkezine yakın; akşam: son POI/otele yakın.
      if (kind == 'lunch' && dayPois.isNotEmpty) {
        final cx =
            dayPois.map((p) => p.lat).reduce((a, b) => a + b) / dayPois.length;
        final cy =
            dayPois.map((p) => p.lng).reduce((a, b) => a + b) / dayPois.length;
        candidates.sort((a, b) =>
            _d2(a.lat, a.lng, cx, cy).compareTo(_d2(b.lat, b.lng, cx, cy)));
      } else if (kind == 'dinner' && dayPois.isNotEmpty) {
        final last = dayPois.last;
        double dinnerRouteCost(PoiSpec venue) =>
            _d2(venue.lat, venue.lng, last.lat, last.lng) +
            _d2(venue.lat, venue.lng, city.hotelLat, city.hotelLng) * 1.4 +
            (venue.cluster == last.cluster ? 0 : .05);
        candidates.sort(
          (a, b) => dinnerRouteCost(a).compareTo(dinnerRouteCost(b)),
        );
      } else {
        candidates.sort((a, b) =>
            _d2(a.lat, a.lng, city.hotelLat, city.hotelLng)
                .compareTo(_d2(b.lat, b.lng, city.hotelLat, city.hotelLng)));
      }
      final f = candidates.first;
      return _MealVenue(
        location: TripLocation(
          id: '${f.id}_$kind$idx',
          name: f.name,
          latitude: f.lat,
          longitude: f.lng,
          city: f.city,
          district: f.cluster,
          clusterId: f.cluster,
        ),
        openHour: f.openHour,
        closeHour: f.closeHour,
        isSynthetic: false,
      );
    }

    // Sentetik yerel lokanta (otele yakın), gerçekçi çalışma saatleriyle.
    return _MealVenue(
      location: TripLocation(
        id: '${kind}_local_${city.name}_$idx',
        name: kind == 'lunch' ? 'Yerel lokanta' : 'Akşam lokantası',
        latitude: city.hotelLat + 0.002,
        longitude: city.hotelLng + 0.002,
        city: city.name,
        district: city.hotelCluster,
        clusterId: city.hotelCluster,
      ),
      openHour: kind == 'lunch' ? 11 : 17,
      closeHour: kind == 'lunch' ? 15 : 22,
      isSynthetic: true,
    );
  }

  double _d2(double a, double b, double c, double d) =>
      (a - c) * (a - c) + (b - d) * (b - d);

  Map<String, dynamic> _zeroMetrics() => {
        'travelMin': 0,
        'walkingMin': 0,
        'waitingMin': 0,
        'transfers': 0,
        'transportCostYen': 0,
      };

  String _date(DateTime d) => '${d.year}-${_m(d.month)}-${_m(d.day)}';
  String _time(DateTime d) => '${_h(d.hour)}:${_m(d.minute)}';
  String _h(int v) => v.toString().padLeft(2, '0');
  String _m(int v) => v.toString().padLeft(2, '0');
}

enum _DayType { arrival, transfer, full, departure }

/// Seçilmiş bir yemek yeri adayı: lokasyon + gerçek çalışma saatleri + sentetik
/// olup olmadığı. Sentetik ise güne warning düşülür.
class _MealVenue {
  const _MealVenue({
    required this.location,
    required this.openHour,
    required this.closeHour,
    required this.isSynthetic,
  });
  final TripLocation location;
  final int openHour;
  final int closeHour;
  final bool isSynthetic;
}

class _TripDay {
  const _TripDay({
    required this.globalIndex,
    required this.city,
    required this.type,
    this.prevCity,
  });
  final int globalIndex;
  final String city;
  final _DayType type;
  final String? prevCity;
}
