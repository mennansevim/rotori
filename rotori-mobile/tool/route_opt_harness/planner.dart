import 'dart:math';

import 'package:japan_trip/domain/itinerary_optimizer.dart';
import 'package:japan_trip/domain/route_matrix.dart';

import 'matrix_builder.dart';
import 'poi_data.dart';
import 'scenario.dart';

/// Bir senaryoyu gün-gün planlar ve JSON'a hazır Map üretir.
class TripPlanner {
  TripPlanner();

  final _matrixBuilder = const MatrixBuilder();

  RouteOptimizationProfile _profile(String name) => switch (name) {
        'fastest' => RouteOptimizationProfile.fastest,
        'leastWalking' => RouteOptimizationProfile.leastWalking,
        'cheapest' => RouteOptimizationProfile.cheapest,
        _ => RouteOptimizationProfile.balanced,
      };

  Future<Map<String, dynamic>> plan(ScenarioSpec spec) async {
    final optimizer = BeamSearchItineraryOptimizer(
      config: const OptimizerConfig(allowActivityDropping: true),
    );

    final tripDays = _buildTripDays(spec);
    // Şehir başına POI dağıtımı. Konaklama gün sayısı şehrin benzersiz POI
    // sayısını aşabildiğinden (ör. Tokyo 6 gece × 4 POI > havuz), havuz
    // tükenince yeniden karılıp doldurulur. Böylece her tam gün, optimizer'ı
    // gerçekten sınayan dolu bir aday kümesiyle beslenir (test amacı budur).
    final cityPools = <String, List<PoiSpec>>{};
    final cityMasters = <String, List<PoiSpec>>{};
    final rng = Random(9000 + spec.id);
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
    var feasibleDays = 0, infeasibleDays = 0, droppedTotal = 0;

    for (final td in tripDays) {
      final date = spec.startDate.add(Duration(days: td.globalIndex));
      final city = cities[td.city]!;
      final pool = cityPools[td.city]!;

      // Bu güne kaç POI ayrılacak?
      final poiCount = switch (td.type) {
        _DayType.arrival => 2,
        _DayType.transfer => 2,
        _DayType.full => 4,
        _DayType.departure => 0,
      };

      // Tam gün özel POI (tema parkı / uzak gezi) varsa güne tek başına ata.
      // Önce havuzu yeterince doldur, SONRA özel POI ara — böylece refill ile
      // gelen bir tema parkı diğer noktalarla aynı güne karışmaz (baseline
      // hatası). durationMin>=300 magic number yerine açık dayRole kullanılır.
      final dayPois = <PoiSpec>[];
      if (td.type != _DayType.departure) {
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
      if (dayPois.isEmpty) {
        refillIfNeeded(td.city, poiCount);
        // Kısa günlerde (varış/transfer) tam gün park seçme; tam güne bırak.
        final skipFullDay = td.type != _DayType.full;
        for (var i = 0; i < poiCount && pool.isNotEmpty;) {
          final idx = skipFullDay
              ? pool.indexWhere(
                  (p) => p.dayRole != PoiDayRole.fullDayExclusive)
              : 0;
          if (idx < 0) break;
          dayPois.add(pool.removeAt(idx));
          i++;
        }
      }

      Map<String, dynamic> dayJson;
      switch (td.type) {
        case _DayType.departure:
          dayJson = _departureDay(spec, td, date, city);
          break;
        default:
          dayJson = await _sightseeingDay(
            spec, td, date, city, dayPois, optimizer);
          break;
      }

      // Ulaşım öncesi transfer/varış bloklarını ekle.
      if (td.type == _DayType.arrival) {
        dayJson['arrivalTransfer'] = _arrivalBlock(spec, td.city);
      } else if (td.type == _DayType.transfer) {
        dayJson['cityTransfer'] = _shinkansenBlock(td.prevCity!, td.city, spec);
      }

      // Toplamlara ekle.
      final m = dayJson['metrics'];
      if (m is Map) {
        tripTravel += (m['travelMin'] as int? ?? 0);
        tripWalk += (m['walkingMin'] as int? ?? 0);
        tripTransfers += (m['transfers'] as int? ?? 0);
        tripCost += (m['transportCostYen'] as int? ?? 0);
      }
      if (dayJson['feasible'] == true) {
        feasibleDays++;
      } else if (dayJson['type'] != 'departure') {
        infeasibleDays++;
      }
      droppedTotal += (dayJson['droppedActivityIds'] as List?)?.length ?? 0;

      dayJsons.add(dayJson);
    }

    return {
      'id': spec.id,
      'title': spec.title,
      'party': {
        'adults': spec.adults,
        'children': spec.children,
        'total': spec.party,
      },
      'profile': spec.profile,
      'entryAirport': spec.entryAirport,
      'exitAirport': spec.exitAirport,
      'dailyWindow':
          '${_h(spec.dailyStartHour)}:00–${_h(spec.dailyEndHour)}:00',
      'cities': spec.stays.map((s) => {'city': s.city, 'nights': s.nights}).toList(),
      'totalDays': spec.totalDays,
      'days': dayJsons,
      'tripTotals': {
        'feasibleDays': feasibleDays,
        'infeasibleDays': infeasibleDays,
        'droppedActivities': droppedTotal,
        'inCityTravelMin': tripTravel,
        'inCityWalkingMin': tripWalk,
        'inCityTransfers': tripTransfers,
        'inCityTransportCostYen': tripCost,
      },
    };
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
    BeamSearchItineraryOptimizer optimizer,
  ) async {
    final startHour = switch (td.type) {
      _DayType.arrival => 14,
      _DayType.transfer => 13,
      _ => spec.dailyStartHour,
    };
    final startMinute = td.type == _DayType.transfer ? 30 : 0;
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
        id: 'brk_${city.name}_${td.globalIndex}',
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
        closingTime: DateTime(date.year, date.month, date.day, startHour + 2, 0),
        preferredTime: TimeOfDayPreference.morning,
        category: 'meal',
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
    if (lunchAnchor <= 13 && dayPois.isNotEmpty && !isThemeparkDay) {
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
        openingTime: DateTime(date.year, date.month, date.day,
            (startH - 1).clamp(11, 13), 30),
        closingTime:
            DateTime(date.year, date.month, date.day, closeH, 0),
        preferredTime: TimeOfDayPreference.afternoon,
        category: 'meal',
      ));
    }

    // Akşam yemeği (~19:00) — yalnız akşam servisi veren açık bir yer varsa.
    // Uygun yer yoksa gerçekçi saatli sentetik lokanta üretilir ve warning
    // olarak işaretlenir. Tema parkı günlerinde ayrı akşam yemeği eklenmez.
    if (endHour >= 20 && !isThemeparkDay) {
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
    final matrix = _matrixBuilder.build(locSet.values.toList());

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
        hasLuggage: td.type == _DayType.transfer,
      ),
    );

    final result = await optimizer.optimize(request);
    return _dayFromResult(spec, td, date, city, startHour, startMinute, endHour,
        result, syntheticMealNote);
  }

  Map<String, dynamic> _dayFromResult(
    ScenarioSpec spec,
    _TripDay td,
    DateTime date,
    CitySpec city,
    int startHour,
    int startMinute,
    int endHour,
    OptimizationResult result, [
    String? syntheticMealNote,
  ]) {
    final base = {
      'dayIndex': td.globalIndex + 1,
      'date': _date(date),
      'city': city.name,
      'type': td.type.name,
      'window':
          '${_h(startHour)}:${_m(startMinute)}–${_h(endHour)}:00',
      'startsAtHotel': city.hotelName,
      'endsAtHotel': city.hotelName,
    };

    if (!result.isSuccess) {
      return {
        ...base,
        'feasible': false,
        'failureCode': result.failure?.code.name,
        'failureMessage': result.failure?.message,
        'schedule': [],
        'droppedActivityIds': const [],
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
          'transfers': leg.transferCount,
          'costYen': leg.estimatedCostYen,
          'depart': _time(leg.departureTime),
          'arrive': _time(leg.arrivalTime),
        },
        'reason': a.optimizationReason,
        'warnings': a.warnings,
      };
    }).toList();

    final m = result.metrics!;
    return {
      ...base,
      'feasible': true,
      'droppedActivityIds': result.droppedActivityIds,
      'schedule': schedule,
      'metrics': {
        'travelMin': m.totalTravelMinutes,
        'walkingMin': m.totalWalkingMinutes,
        'waitingMin': m.totalWaitingMinutes,
        'transfers': m.totalTransferCount,
        'transportCostYen': m.estimatedTransportCostYen,
        'routeEfficiency':
            double.parse(m.routeEfficiencyScore.toStringAsFixed(3)),
        'score': double.parse(m.score.toStringAsFixed(2)),
      },
      'optimizationChanges': result.optimizationChanges,
      'warnings': [
        ...result.warnings,
        if (syntheticMealNote != null) syntheticMealNote,
      ],
    };
  }

  Map<String, dynamic> _emptyDay(
      _TripDay td, DateTime date, CitySpec city, String note) {
    return {
      'dayIndex': td.globalIndex + 1,
      'date': _date(date),
      'city': city.name,
      'type': td.type.name,
      'feasible': true,
      'note': note,
      'schedule': const [],
      'droppedActivityIds': const [],
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
      'note':
          'Son gün: otelden çıkış, ${airport.name} havaalanına transfer.',
      'departureTransfer': {
        'exitAirport': airport.code,
        'segments': segments,
        'totalDurationMin': totalMin,
        'totalCostYen': totalCost,
        'totalTransfers': transfers,
      },
      'schedule': const [],
      'droppedActivityIds': const [],
      'metrics': _zeroMetrics(),
    };
  }

  // -------------------- Transfer / varış blokları --------------------

  Map<String, dynamic> _arrivalBlock(ScenarioSpec spec, String firstCity) {
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
      'note': 'İniş → otele yerleşme; öğleden sonra hafif gezi başlar.',
    };
  }

  Map<String, dynamic> _shinkansenBlock(
      String fromCity, String toCity, ScenarioSpec spec) {
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
      'costYen': (sk.costYen + 800) * spec.party,
      'costYenPerPerson': sk.costYen + 800,
      'transfers': sk.transfers,
      'note': 'Sabah check-out + bavul; öğleden sonra yeni şehirde gezi.',
    };
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

    final candidates =
        mealVenues(city.name, period, winStart, winEnd, needed);
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
        candidates.sort((a, b) => _d2(a.lat, a.lng, last.lat, last.lng)
            .compareTo(_d2(b.lat, b.lng, last.lat, last.lng)));
      } else {
        candidates.sort((a, b) => _d2(a.lat, a.lng, city.hotelLat, city.hotelLng)
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

  String _date(DateTime d) =>
      '${d.year}-${_m(d.month)}-${_m(d.day)}';
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
