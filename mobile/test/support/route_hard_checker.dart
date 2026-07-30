import 'route_plan_scenario.dart';
import 'route_time.dart';

/// Section A "TEMEL KURALLAR (HARD)" listesinin mekanik doğrulaması.
/// Herhangi bir madde ihlal edilirse senaryo test hard-fail sayılır (0 puan).
class HardCheckFailure {
  const HardCheckFailure({required this.code, required this.detail});

  final String code;
  final String detail;

  @override
  String toString() => '[$code] $detail';
}

class HardCheckReport {
  const HardCheckReport(this.failures);

  final List<HardCheckFailure> failures;

  bool get passed => failures.isEmpty;

  @override
  String toString() =>
      passed ? 'HardCheck OK' : 'HardCheck FAIL:\n${failures.join('\n')}';
}

class RouteHardChecker {
  const RouteHardChecker({
    this.doorToDoorToleranceMinutes = 1,
    this.walkingKilometerLimit = 8.0,
    this.walkingMinutesPerKilometer = 12.5,
    this.lunchWindowStartMinutes = 11 * 60 + 30,
    this.lunchWindowEndMinutes = 14 * 60,
    this.dinnerWindowStartMinutes = 18 * 60,
    this.dinnerWindowEndMinutes = 22 * 60,
  });

  final int doorToDoorToleranceMinutes;
  final double walkingKilometerLimit;
  final double walkingMinutesPerKilometer;
  final int lunchWindowStartMinutes;
  final int lunchWindowEndMinutes;
  final int dinnerWindowStartMinutes;
  final int dinnerWindowEndMinutes;

  HardCheckReport evaluate(
    RoutePlanScenario scenario,
    RoutePlanOutput output,
  ) {
    final failures = <HardCheckFailure>[];
    final activityById = {
      for (final activity in scenario.activities) activity.id: activity,
    };
    final matrix = _matrixIndex(scenario.routeMatrix);
    final dayStartMin = minutesOfDay(formatHhmm(scenario.dayStart));
    final dayEndMin = minutesOfDay(formatHhmm(scenario.dayEnd));

    if (output.timeline.isEmpty) {
      failures.add(const HardCheckFailure(
        code: 'timeline_empty',
        detail: 'Timeline boş — sabit-olmayan aktivite yerleştirilemedi.',
      ));
      return HardCheckReport(failures);
    }

    var previousEndMin = -1;
    final seenActivities = <String, int>{};
    for (var i = 0; i < output.timeline.length; i++) {
      final entry = output.timeline[i];
      final startMin = minutesOfDay(entry.startTime);
      final endMin = minutesOfDay(entry.endTime);
      if (endMin < startMin) {
        failures.add(HardCheckFailure(
          code: 'timeline_reverse',
          detail:
              '#$i ${entry.kind.name} girdisinin end saati start\'tan önce (${entry.startTime}→${entry.endTime}).',
        ));
      }
      if (previousEndMin >= 0 && startMin != previousEndMin) {
        failures.add(HardCheckFailure(
          code: 'timeline_gap',
          detail:
              '#$i ${entry.kind.name} önceki bloktan ayrık (önceki bitiş ${_hhmm(previousEndMin)}, bu blok ${entry.startTime}).',
        ));
      }
      previousEndMin = endMin;

      if (entry.kind == PromptTimelineKind.activity) {
        final id = entry.activityId!;
        seenActivities.update(id, (v) => v + 1, ifAbsent: () => 1);
        final activity = activityById[id];
        if (activity == null) {
          failures.add(HardCheckFailure(
            code: 'activity_unknown',
            detail: 'Timeline\'da bilinmeyen aktivite id: $id.',
          ));
          continue;
        }
        _validateActivity(
          failures: failures,
          entry: entry,
          activity: activity,
          startMin: startMin,
          endMin: endMin,
        );
      } else if (entry.kind == PromptTimelineKind.transit) {
        _validateTransit(
          failures: failures,
          entry: entry,
          startMin: startMin,
          endMin: endMin,
          matrix: matrix,
        );
      }
    }

    for (final MapEntry(:key, :value) in seenActivities.entries) {
      if (value > 1) {
        failures.add(HardCheckFailure(
          code: 'activity_repeat',
          detail: 'Aktivite timeline\'da $value kez geçiyor: $key.',
        ));
      }
    }

    for (final drop in output.dropped) {
      if (seenActivities.containsKey(drop.activityId)) {
        failures.add(HardCheckFailure(
          code: 'dropped_but_scheduled',
          detail:
              'Aktivite hem dropped hem timeline\'da: ${drop.activityId}.',
        ));
      }
    }

    // Otel çerçevesi (Kural 6).
    if (output.timeline.isNotEmpty) {
      final firstStartMin = minutesOfDay(output.timeline.first.startTime);
      final lastEndMin = minutesOfDay(output.timeline.last.endTime);
      if (firstStartMin < dayStartMin) {
        failures.add(HardCheckFailure(
          code: 'day_start_violation',
          detail:
              'İlk aktivite ${_hhmm(firstStartMin)}, dayStart ${_hhmm(dayStartMin)} önce başlıyor.',
        ));
      }
      if (lastEndMin > dayEndMin) {
        failures.add(HardCheckFailure(
          code: 'day_end_violation',
          detail:
              'Son blok ${_hhmm(lastEndMin)} bitiyor; dayEnd ${_hhmm(dayEndMin)}.',
        ));
      }
    }

    // Öğün pencereleri (Kural 7).
    final lunch = _findMealActivity(
      output: output,
      activityById: activityById,
      windowStartMin: lunchWindowStartMinutes,
      windowEndMin: lunchWindowEndMinutes,
    );
    final dinner = _findMealActivity(
      output: output,
      activityById: activityById,
      windowStartMin: dinnerWindowStartMinutes,
      windowEndMin: dinnerWindowEndMinutes,
    );
    // Gün penceresiyle hiç örtüşmeyen bir öğün yapısal olarak imkânsızdır
    // (ör. gün 14:00'te başlıyorsa 11:30–14:00 öğle penceresi zaten geçmiştir)
    // — böyle durumda o öğünü zorunlu tutmak anlamsızdır.
    final lunchWindowOverlapsDay = _overlaps(
      lunchWindowStartMinutes,
      lunchWindowEndMinutes,
      dayStartMin,
      dayEndMin,
    );
    final dinnerWindowOverlapsDay = _overlaps(
      dinnerWindowStartMinutes,
      dinnerWindowEndMinutes,
      dayStartMin,
      dayEndMin,
    );
    // Section A Kural 7: yalnızca akşam yemeği "SIKI"dir. Öğle yemeği
    // bulunamıyorsa modelin bunu açık bir warning ile bildirmesi (ya da
    // dropped[] üzerinden bir meal aktivitesini açıklaması) kabul edilir —
    // synthetic:meal ekleme alternatifinin yerine geçer.
    final lunchAccountedByWarning =
        output.warnings.any((w) => w.toLowerCase().contains('öğle yemeği'));
    final lunchAccountedByDrop = output.dropped.any(
      (d) => activityById[d.activityId]?.category == PromptActivityCategory.meal,
    );
    if (lunch == null &&
        lunchWindowOverlapsDay &&
        !lunchAccountedByWarning &&
        !lunchAccountedByDrop) {
      failures.add(const HardCheckFailure(
        code: 'lunch_missing',
        detail:
            'Öğle yemeği penceresi (11:30–14:00) içinde meal aktivitesi yok ve bu durum warning/dropped ile de açıklanmamış.',
      ));
    }
    if (dinner == null && dinnerWindowOverlapsDay) {
      failures.add(const HardCheckFailure(
        code: 'dinner_missing',
        detail: 'Akşam yemeği penceresi (18:00–22:00) içinde meal aktivitesi yok.',
      ));
    }
    if (output.metrics.hasLunch != (lunch != null)) {
      failures.add(HardCheckFailure(
        code: 'metrics_lunch_mismatch',
        detail:
            'metrics.hasLunch=${output.metrics.hasLunch} timeline gerçeğiyle uyuşmuyor.',
      ));
    }
    if (output.metrics.hasDinner != (dinner != null)) {
      failures.add(HardCheckFailure(
        code: 'metrics_dinner_mismatch',
        detail:
            'metrics.hasDinner=${output.metrics.hasDinner} timeline gerçeğiyle uyuşmuyor.',
      ));
    }

    // Yürüme eşiği (Kural 9).
    final walkingLimitMinutes =
        walkingKilometerLimit * walkingMinutesPerKilometer;
    if (output.metrics.totalWalkingMinutes > walkingLimitMinutes) {
      failures.add(HardCheckFailure(
        code: 'walking_over_limit',
        detail:
            'Toplam yürüme ${output.metrics.totalWalkingMinutes} dk; sınır ${walkingLimitMinutes.round()} dk (~${walkingKilometerLimit.toStringAsFixed(1)} km).',
      ));
    }

    return HardCheckReport(failures);
  }

  void _validateActivity({
    required List<HardCheckFailure> failures,
    required PromptTimelineEntry entry,
    required PromptActivity activity,
    required int startMin,
    required int endMin,
  }) {
    final duration = endMin - startMin;
    if (duration < (activity.minimumDurationMinutes ?? activity.durationMinutes)) {
      failures.add(HardCheckFailure(
        code: 'duration_short',
        detail:
            '${activity.id} süresi $duration dk; minimum ${activity.minimumDurationMinutes ?? activity.durationMinutes}.',
      ));
    }
    if (activity.openingTime != null &&
        startMin < minutesOfDay(activity.openingTime!)) {
      failures.add(HardCheckFailure(
        code: 'opening_violation',
        detail:
            '${activity.id} ${entry.startTime}\'te başlıyor ama açılış ${activity.openingTime}.',
      ));
    }
    if (activity.closingTime != null &&
        endMin > minutesOfDay(activity.closingTime!)) {
      failures.add(HardCheckFailure(
        code: 'closing_violation',
        detail:
            '${activity.id} ${entry.endTime}\'te bitiyor ama kapanış ${activity.closingTime}.',
      ));
    }
    if (activity.fixedStartTime != null &&
        startMin != minutesOfDay(activity.fixedStartTime!)) {
      failures.add(HardCheckFailure(
        code: 'fixed_start_violation',
        detail:
            '${activity.id} sabit ${activity.fixedStartTime}\'te başlamalıydı; ${entry.startTime}.',
      ));
    }
    if (activity.fixedEndTime != null &&
        endMin != minutesOfDay(activity.fixedEndTime!)) {
      failures.add(HardCheckFailure(
        code: 'fixed_end_violation',
        detail:
            '${activity.id} sabit ${activity.fixedEndTime}\'te bitmeliydi; ${entry.endTime}.',
      ));
    }
  }

  void _validateTransit({
    required List<HardCheckFailure> failures,
    required PromptTimelineEntry entry,
    required int startMin,
    required int endMin,
    required Map<String, List<PromptRouteEntry>> matrix,
  }) {
    final duration = endMin - startMin;
    final key = _matrixKey(entry.fromId!, entry.toId!);
    final options = matrix[key];
    if (options == null || options.isEmpty) {
      failures.add(HardCheckFailure(
        code: 'transit_no_matrix_entry',
        detail:
            '${entry.fromId} → ${entry.toId} matriste yok; uydurulmuş leg.',
      ));
      return;
    }
    final matchingMode =
        options.where((o) => o.mode == entry.mode).toList(growable: false);
    if (matchingMode.isEmpty) {
      failures.add(HardCheckFailure(
        code: 'transit_mode_mismatch',
        detail:
            '${entry.fromId} → ${entry.toId} için ${entry.mode!.name} moduna matriste kayıt yok.',
      ));
      return;
    }
    final closest = matchingMode
        .map((o) => (o, (o.doorToDoorMinutes - duration).abs()))
        .reduce((a, b) => a.$2 <= b.$2 ? a : b);
    if (closest.$2 > doorToDoorToleranceMinutes) {
      failures.add(HardCheckFailure(
        code: 'transit_duration_drift',
        detail:
            '${entry.fromId} → ${entry.toId} matriste ${closest.$1.doorToDoorMinutes} dk; timeline $duration dk.',
      ));
    }
  }

  Map<String, List<PromptRouteEntry>> _matrixIndex(
    List<PromptRouteEntry> entries,
  ) {
    final map = <String, List<PromptRouteEntry>>{};
    for (final entry in entries) {
      map
          .putIfAbsent(_matrixKey(entry.fromId, entry.toId), () => [])
          .add(entry);
    }
    return map;
  }

  String _matrixKey(String from, String to) => '$from $to';

  bool _overlaps(int aStart, int aEnd, int bStart, int bEnd) =>
      aStart < bEnd && bStart < aEnd;

  String _hhmm(int minutes) {
    final hour = (minutes ~/ 60).toString().padLeft(2, '0');
    final minute = (minutes % 60).toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  PromptTimelineEntry? _findMealActivity({
    required RoutePlanOutput output,
    required Map<String, PromptActivity> activityById,
    required int windowStartMin,
    required int windowEndMin,
  }) {
    for (final entry in output.timeline) {
      if (entry.kind != PromptTimelineKind.activity) continue;
      final activity = activityById[entry.activityId];
      if (activity == null) continue;
      if (activity.category != PromptActivityCategory.meal) continue;
      final startMin = minutesOfDay(entry.startTime);
      final endMin = minutesOfDay(entry.endTime);
      if (startMin >= windowStartMin && endMin <= windowEndMin) {
        return entry;
      }
    }
    return null;
  }
}
