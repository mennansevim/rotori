import 'dart:math';

import 'route_plan_scenario.dart';
import 'route_time.dart';

/// Section B.1'e uygun deterministik rastgele senaryo üretici.
///
/// Aynı `seed` her koşumda aynı 10 senaryoyu üretir. POI havuzu boşsa üretim
/// yapılmaz — çağıran taraf fixture eksik uyarısını gösterir.
class PoiPool {
  const PoiPool({required this.city, required this.hotels, required this.pois});

  final String city;
  final List<PromptHotel> hotels;
  final List<PromptActivity> pois;

  bool get isEmpty => hotels.isEmpty || pois.isEmpty;

  bool get hasMealCoverage =>
      pois.any((a) => a.category == PromptActivityCategory.meal);
}

class ScenarioGeneratorConfig {
  const ScenarioGeneratorConfig({
    this.scenariosPerRun = 10,
    this.activityCountMin = 5,
    this.activityCountMax = 9,
    this.fixedCountMax = 2,
    this.dayStartHourMin = 7,
    this.dayStartHourMax = 9,
    this.dayEndHourMin = 21,
    this.dayEndHourMax = 23,
    this.matrixNoisePercent = 0.1,
  });

  final int scenariosPerRun;
  final int activityCountMin;
  final int activityCountMax;
  final int fixedCountMax;
  final int dayStartHourMin;
  final int dayStartHourMax;
  final int dayEndHourMin;
  final int dayEndHourMax;
  final double matrixNoisePercent;
}

class ScenarioGenerator {
  const ScenarioGenerator({
    required this.pools,
    required this.baseDate,
    this.config = const ScenarioGeneratorConfig(),
  });

  final Map<String, PoiPool> pools;

  /// Her senaryonun `date` üretiminin başlangıç tarihi.
  final DateTime baseDate;
  final ScenarioGeneratorConfig config;

  List<RoutePlanScenario> generate(int seed) {
    final rng = Random(seed);
    final cities = pools.entries
        .where((entry) => !entry.value.isEmpty)
        .map((entry) => entry.key)
        .toList()
      ..sort();
    if (cities.isEmpty) return const [];

    final scenarios = <RoutePlanScenario>[];
    for (var i = 0; i < config.scenariosPerRun; i++) {
      final city = cities[rng.nextInt(cities.length)];
      final pool = pools[city]!;
      scenarios.add(_buildScenario(
        pool: pool,
        seed: seed * 100003 + i * 31,
        index: i,
        rng: Random(seed * 100003 + i * 31),
      ));
    }
    return scenarios;
  }

  RoutePlanScenario _buildScenario({
    required PoiPool pool,
    required int seed,
    required int index,
    required Random rng,
  }) {
    final date = baseDate.add(Duration(days: rng.nextInt(180)));
    final isoDate = _iso(date);
    final dayStart = _time(
      date,
      hour: config.dayStartHourMin +
          rng.nextInt(config.dayStartHourMax - config.dayStartHourMin + 1),
      minute: rng.nextInt(60),
    );
    final dayEnd = _time(
      date,
      hour: config.dayEndHourMin +
          rng.nextInt(config.dayEndHourMax - config.dayEndHourMin + 1),
      minute: rng.nextInt(60),
    );

    final hotel = pool.hotels[rng.nextInt(pool.hotels.length)];

    final activityCount = config.activityCountMin +
        rng.nextInt(config.activityCountMax - config.activityCountMin + 1);
    final selected = _selectActivities(pool, rng, activityCount);
    final fixedCount = rng.nextInt(config.fixedCountMax + 1);
    // En fazla 1 meal fixed olabilir — aynı anda iki restoran rezervasyonu
    // fiziksel olarak imkânsızdır (Section A Kural 7: günde tam 1 akşam
    // yemeği). Diğer fixed slotlar meal-olmayan aktivitelerden gelir.
    final mealsInSelected = selected
        .where((a) => a.category == PromptActivityCategory.meal)
        .toList();
    final nonMealsInSelected = selected
        .where((a) => a.category != PromptActivityCategory.meal)
        .toList();
    final fixedCandidates = <PromptActivity>[
      if (mealsInSelected.isNotEmpty) mealsInSelected.first,
      ...nonMealsInSelected,
    ];
    final fixedIds = <String>{};
    for (var f = 0; f < fixedCount && f < fixedCandidates.length; f++) {
      fixedIds.add(fixedCandidates[f].id);
    }
    final activities = <PromptActivity>[];
    for (final activity in selected) {
      if (!fixedIds.contains(activity.id)) {
        activities.add(activity);
        continue;
      }
      final fixedStart = activity.category == PromptActivityCategory.meal
          ? _pickMealTime(rng)
          : _pickAfternoonTime(rng);
      final fixedEnd = _addMinutes(fixedStart, activity.durationMinutes);
      if (!_fitsOwnWindow(activity, fixedStart, fixedEnd)) {
        // POI'nin kendi açılış/kapanışıyla çakışan bir rezervasyon saati
        // önerilemez (ör. 18:00 kapanan bir pazara 19:00 rezervasyonu) —
        // sabitlemeden normal aktivite olarak bırak.
        activities.add(activity);
        continue;
      }
      activities.add(PromptActivity(
        id: activity.id,
        name: activity.name,
        latitude: activity.latitude,
        longitude: activity.longitude,
        cluster: activity.cluster,
        category: activity.category,
        durationMinutes: activity.durationMinutes,
        minimumDurationMinutes: activity.minimumDurationMinutes,
        openingTime: activity.openingTime,
        closingTime: activity.closingTime,
        fixedStartTime: fixedStart,
        fixedEndTime: fixedEnd,
        isFixed: true,
        isLocked: activity.isLocked,
        hasReservation: true,
        preferredTime: activity.preferredTime,
      ));
    }

    final windowed = _assignMealWindows(activities);
    final trimmed = _trimToFeasibleLoad(
      windowed,
      dayStart: dayStart,
      dayEnd: dayEnd,
    );

    final matrix = _buildMatrix(
      hotel: hotel,
      activities: trimmed,
      rng: rng,
    );

    return RoutePlanScenario(
      id: 'gen-$seed-$index',
      date: isoDate,
      city: pool.city,
      hotel: hotel,
      dayStart: dayStart,
      dayEnd: dayEnd,
      activities: trimmed,
      routeMatrix: matrix,
      seed: seed,
    );
  }

  /// Section B.1'in rastgele batch'i "normal, planlanabilir" günleri temsil
  /// eder — gerçek aşırı yüklenme testi ayrı, adversarial A4 senaryosuna
  /// aittir (Section B.5). Kaba bir süre bütçesi (aktivite süreleri toplamı +
  /// leg başına ortalama seyahat tahmini) gün penceresinin çoğunu
  /// dolduruyorsa, en uzun süreli sabit-olmayan meal-dışı aktiviteyi çıkarıp
  /// tekrar dener — böylece optimizer'ın `dropped[]` / aktivite-düşürme
  /// yeteneği yalnızca gerçekten aşırı yüklü A4 gibi senaryolarda devreye
  /// girer, sıradan günlerde değil.
  List<PromptActivity> _trimToFeasibleLoad(
    List<PromptActivity> activities, {
    required DateTime dayStart,
    required DateTime dayEnd,
    int assumedMinutesPerLeg = 25,
    double budgetFraction = 0.82,
  }) {
    var current = activities;
    final windowMinutes = dayEnd.difference(dayStart).inMinutes;
    while (current.length > 3) {
      final totalDuration =
          current.fold<int>(0, (sum, a) => sum + a.durationMinutes);
      final legCount = current.length + 1; // hotel→...→hotel
      final estimatedTravel = legCount * assumedMinutesPerLeg;
      if (totalDuration + estimatedTravel <= windowMinutes * budgetFraction) {
        break;
      }
      final droppable = current
          .where((a) => !a.hasFixedSchedule && a.category != PromptActivityCategory.meal)
          .toList();
      if (droppable.isEmpty) break;
      droppable.sort((a, b) => b.durationMinutes.compareTo(a.durationMinutes));
      final worst = droppable.first;
      current = current.where((a) => a.id != worst.id).toList();
    }
    return current;
  }

  /// Section A Kural 7: her günde tam 1 öğle (11:30–14:00) ve 1 akşam yemeği
  /// (18:00–22:00) olmalıdır. Sabit rezervasyonu olmayan meal aktiviteleri
  /// domain'de tamamen serbest saatlere yerleşebilir (optimizer öğün
  /// kavramını bilmez) — bu yüzden generator, karşılaşma sırasına göre ilk
  /// sabit-olmayan meal'i öğle, ikinciyi akşam penceresine sabitler. POI'nin
  /// kendi açılış/kapanışı varsa öğün penceresiyle kesişimi alınır; kesişim
  /// boşsa öğün penceresi öncelenir (test verisi — gerçek mekan saatinden
  /// çok Section A sözleşmesini doğrulamak önemlidir).
  List<PromptActivity> _assignMealWindows(List<PromptActivity> activities) {
    const lunchOpen = '11:30', lunchClose = '14:00';
    const dinnerOpen = '18:00', dinnerClose = '22:00';
    var mealRole = 0;
    return [
      for (final activity in activities)
        if (activity.category == PromptActivityCategory.meal &&
            !activity.hasFixedSchedule &&
            mealRole < 2)
          _withMealWindow(
            activity,
            mealRole++ == 0
                ? (open: lunchOpen, close: lunchClose)
                : (open: dinnerOpen, close: dinnerClose),
          )
        else
          activity,
    ];
  }

  PromptActivity _withMealWindow(
    PromptActivity activity,
    ({String open, String close}) slot,
  ) {
    final open = activity.openingTime != null &&
            minutesOfDay(activity.openingTime!) > minutesOfDay(slot.open)
        ? activity.openingTime!
        : slot.open;
    final close = activity.closingTime != null &&
            minutesOfDay(activity.closingTime!) < minutesOfDay(slot.close)
        ? activity.closingTime!
        : slot.close;
    final fitsDuration =
        minutesOfDay(close) - minutesOfDay(open) >= activity.durationMinutes;
    final effectiveOpen = fitsDuration ? open : slot.open;
    final effectiveClose = fitsDuration ? close : slot.close;
    return PromptActivity(
      id: activity.id,
      name: activity.name,
      latitude: activity.latitude,
      longitude: activity.longitude,
      cluster: activity.cluster,
      category: activity.category,
      durationMinutes: activity.durationMinutes,
      minimumDurationMinutes: activity.minimumDurationMinutes,
      openingTime: effectiveOpen,
      closingTime: effectiveClose,
      isFixed: activity.isFixed,
      isLocked: activity.isLocked,
      hasReservation: activity.hasReservation,
      preferredTime: activity.preferredTime,
    );
  }

  List<PromptActivity> _selectActivities(
    PoiPool pool,
    Random rng,
    int count,
  ) {
    final meals = pool.pois
        .where((p) => p.category == PromptActivityCategory.meal)
        .toList();
    final rest = pool.pois
        .where((p) => p.category != PromptActivityCategory.meal)
        .toList();
    meals.shuffle(rng);
    rest.shuffle(rng);
    final selected = <PromptActivity>[];
    final mealCount = meals.length >= 2 ? 2 : meals.length;
    selected.addAll(meals.take(mealCount));
    final remaining = count - selected.length;
    if (remaining > 0) {
      selected.addAll(rest.take(remaining));
    }
    return selected;
  }

  List<PromptRouteEntry> _buildMatrix({
    required PromptHotel hotel,
    required List<PromptActivity> activities,
    required Random rng,
  }) {
    final entries = <PromptRouteEntry>[];
    final locations = [
      _MatrixNode(
        id: hotel.id,
        latitude: hotel.latitude,
        longitude: hotel.longitude,
      ),
      for (final activity in activities)
        _MatrixNode(
          id: activity.id,
          latitude: activity.latitude,
          longitude: activity.longitude,
        ),
    ];
    for (final from in locations) {
      for (final to in locations) {
        if (from.id == to.id) continue;
        final distanceKm = _haversineKm(from, to);
        final base = (distanceKm * 6).ceil() + 2; // dakika (kaba tahmin)
        final noisy = (base *
                (1 + (rng.nextDouble() * 2 - 1) * config.matrixNoisePercent))
            .round()
            .clamp(2, 240);
        final walkingMinutes = distanceKm < 1.5 ? (distanceKm * 12).ceil() : 0;
        final mode = distanceKm < 0.8
            ? PromptTransportMode.walking
            : distanceKm < 12
                ? PromptTransportMode.metro
                : PromptTransportMode.train;
        entries.add(PromptRouteEntry(
          fromId: from.id,
          toId: to.id,
          mode: mode,
          doorToDoorMinutes: noisy,
          walkingMinutes: walkingMinutes,
          transferCount: mode == PromptTransportMode.walking
              ? 0
              : distanceKm < 5
                  ? 0
                  : 1,
          yenCost: mode == PromptTransportMode.walking ? 0 : 250,
          reliability: 0.9 + rng.nextDouble() * 0.09,
        ));
      }
    }
    return entries;
  }

  double _haversineKm(_MatrixNode a, _MatrixNode b) {
    const earthRadius = 6371.0;
    final dLat = _deg2rad(b.latitude - a.latitude);
    final dLon = _deg2rad(b.longitude - a.longitude);
    final s1 = sin(dLat / 2);
    final s2 = sin(dLon / 2);
    final aa = s1 * s1 +
        cos(_deg2rad(a.latitude)) *
            cos(_deg2rad(b.latitude)) *
            s2 *
            s2;
    return 2 * earthRadius * atan2(sqrt(aa), sqrt(1 - aa));
  }

  double _deg2rad(double deg) => deg * pi / 180;

  bool _fitsOwnWindow(PromptActivity activity, String start, String end) {
    final opening = activity.openingTime;
    final closing = activity.closingTime;
    if (opening != null && minutesOfDay(start) < minutesOfDay(opening)) {
      return false;
    }
    if (closing != null && minutesOfDay(end) > minutesOfDay(closing)) {
      return false;
    }
    return true;
  }

  String _pickMealTime(Random rng) {
    final hour = 19 + rng.nextInt(2);
    final minute = rng.nextInt(4) * 15;
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  String _pickAfternoonTime(Random rng) {
    final hour = 13 + rng.nextInt(4);
    final minute = rng.nextInt(4) * 15;
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  DateTime _time(DateTime day,
          {required int hour, required int minute}) =>
      DateTime(day.year, day.month, day.day, hour, minute);

  String _iso(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  String _addMinutes(String hhmm, int minutes) {
    final parts = hhmm.split(':');
    final total = int.parse(parts[0]) * 60 + int.parse(parts[1]) + minutes;
    final hour = ((total ~/ 60) % 24).toString().padLeft(2, '0');
    final minute = (total % 60).toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class _MatrixNode {
  const _MatrixNode({
    required this.id,
    required this.latitude,
    required this.longitude,
  });

  final String id;
  final double latitude;
  final double longitude;
}
