import 'package:rotori/core/l10n.dart';
import 'package:rotori/domain/activity_identity.dart';
import 'package:rotori/domain/city_transfers.dart';
import 'package:rotori/domain/plan_generation.dart';
import 'package:rotori/domain/plan_schedule_engine.dart';
import 'package:rotori/domain/types.dart';

const int routeGenerationQaSchemaVersion = 1;

Map<String, dynamic> buildRouteGenerationQa({
  int scenarioCount = 160,
  int seed = 20260811,
  DateTime? generatedAt,
}) {
  const routePatterns = <List<String>>[
    ['tokyo'],
    ['osaka'],
    ['kyoto'],
    ['tokyo', 'kyoto'],
    ['kyoto', 'osaka'],
    ['osaka', 'kyoto', 'nara'],
    ['tokyo', 'kyoto', 'osaka'],
    ['tokyo', 'osaka', 'hiroshima'],
    ['osaka', 'hiroshima'],
    ['tokyo', 'nagoya'],
  ];
  const modes = ['shinkansen', 'train', 'bus', 'taxi', 'flight'];
  const engine = PlanScheduleEngine();
  final failures = <Map<String, dynamic>>[];
  final scenarios = <Map<String, dynamic>>[];
  var totalDays = 0;
  var totalActivities = 0;
  var emptyDays = 0;
  var adjacentDuplicates = 0;
  var transitionModeChecks = 0;
  var transitionMismatches = 0;

  for (var index = 0; index < scenarioCount; index++) {
    final cities = routePatterns[(index * 7 + seed) % routePatterns.length];
    final lang = index.isEven ? AppLang.tr : AppLang.en;
    final pace = Pace.values[(index + seed) % Pace.values.length];
    final dayCount = (cities.length * 3 + 2 + (index % 5)).clamp(5, 14);
    final start = DateTime(2026, 9, 1).add(Duration(days: index * 3));
    final end = start.add(Duration(days: dayCount - 1));
    final trip = buildTripFromCities(
      cityKeys: cities,
      startYmd: _ymd(start),
      endYmd: _ymd(end),
      lang: lang,
    );
    trip.preferences.pace = pace;
    trip.preferences.interests = [
      if (index % 3 == 0) InterestTag.themeParks,
      if (index % 4 == 0) InterestTag.food,
      if (index % 5 == 0) InterestTag.temples,
    ];
    fillTripDays(trip, lang: lang);

    final duplicates = findConsecutiveActivityDuplicates(trip.days);
    adjacentDuplicates += duplicates.length;
    totalDays += trip.days.length;
    totalActivities += trip.days.fold<int>(
      0,
      (sum, day) =>
          sum +
          day.items
              .where((item) => item.kind == TimelineItemKind.activity)
              .length,
    );
    emptyDays += trip.days.where((day) => day.items.isEmpty).length;
    for (final duplicate in duplicates) {
      failures.add({
        'scenarioId': 'generation-${index + 1}',
        'code': 'consecutiveActivityDuplicate',
        ...duplicate.toJson(),
      });
    }

    var scenarioTransitionChecks = 0;
    final transitions = trip.days
        .where((day) => day.cityTransition != null)
        .toList(growable: false);
    for (final day in transitions) {
      final transition = day.cityTransition!;
      for (final mode in modes) {
        transitionModeChecks++;
        scenarioTransitionChecks++;
        final result = engine.apply(
          Trip.fromJson(trip.toJson()),
          UpdateCityTransition(
            toDayNumber: day.dayNumber,
            fromCity: transition.fromCity,
            toCity: transition.toCity,
            mode: mode,
            lang: lang,
          ),
        );
        final mismatch = _transitionMismatch(
          result,
          dayNumber: day.dayNumber,
          fromCity: transition.fromCity,
          toCity: transition.toCity,
          mode: mode,
          lang: lang,
        );
        if (mismatch == null) continue;
        transitionMismatches++;
        failures.add({
          'scenarioId': 'generation-${index + 1}',
          'code': 'cityTransitionMismatch',
          'dayNumber': day.dayNumber,
          'mode': mode,
          'detail': mismatch,
        });
      }
    }

    scenarios.add({
      'id': 'generation-${index + 1}',
      'cities': cities,
      'start': _ymd(start),
      'end': _ymd(end),
      'dayCount': trip.days.length,
      'language': lang.code,
      'pace': pace.name,
      'activityCount': trip.days.fold<int>(
        0,
        (sum, day) =>
            sum +
            day.items
                .where((item) => item.kind == TimelineItemKind.activity)
                .length,
      ),
      'emptyDayCount': trip.days.where((day) => day.items.isEmpty).length,
      'adjacentDuplicateCount': duplicates.length,
      'transitionCount': transitions.length,
      'transitionModeChecks': scenarioTransitionChecks,
    });
  }

  return {
    'schemaVersion': routeGenerationQaSchemaVersion,
    'generatedAt': (generatedAt ?? DateTime.now().toUtc()).toIso8601String(),
    'suite': {
      'name': 'RotoriProductionRouteGenerationQA',
      'seed': seed,
      'scenarioCount': scenarioCount,
      'languages': ['tr', 'en'],
      'transportModes': modes,
      'routePatternCount': routePatterns.length,
    },
    'algorithmContract': {
      'generator': 'buildTripFromCities + fillTripDays',
      'activityIdentity': 'cityId + canonical placeId; title alias fallback',
      'transitionSourceOfTruth': 'DayPlan.cityTransition',
      'transitionProjection':
          'TimelineItem.isCityTransition + synchronized theme/details',
      'adjacentDuplicatePolicy': 'hard-zero for activity items',
      'optimizer': 'BeamSearchItineraryOptimizer',
      'beamWidth': 6,
      'routeMatrix': 'rotori-offline-jp',
    },
    'summary': {
      'plansGenerated': scenarioCount,
      'totalDayRecords': totalDays,
      'totalActivities': totalActivities,
      'emptyDayCount': emptyDays,
      'adjacentDuplicateCount': adjacentDuplicates,
      'transitionModeChecks': transitionModeChecks,
      'transitionMismatchCount': transitionMismatches,
      'failureCount': failures.length,
    },
    'qualityGate': {
      'noEmptyDays': emptyDays == 0,
      'noAdjacentActivityDuplicates': adjacentDuplicates == 0,
      'cityTransitionProjectionConsistent': transitionMismatches == 0,
      'passed': emptyDays == 0 &&
          adjacentDuplicates == 0 &&
          transitionMismatches == 0,
    },
    'failures': failures,
    'scenarios': scenarios,
  };
}

String? _transitionMismatch(
  PlanEditResult result, {
  required int dayNumber,
  required String fromCity,
  required String toCity,
  required String mode,
  required AppLang lang,
}) {
  if (!result.isSuccess) return result.failure?.message ?? 'command failed';
  final day = result.trip!.days.firstWhere(
    (candidate) => candidate.dayNumber == dayNumber,
  );
  if (day.cityTransition?.mode != mode) {
    return 'DayPlan.cityTransition.mode güncellenmedi';
  }
  final projected = day.items.where((item) => item.isCityTransition).toList();
  if (projected.length != 1) {
    return 'isCityTransition satır sayısı ${projected.length}';
  }
  final item = projected.single;
  final expected = suggestionForMode(
    mode,
    fromCity,
    toCity,
    0,
    dayNumber,
  ).transfer;
  if (!item.title.contains(L10n.resolve(expected.mode, lang))) {
    return 'timeline başlığı seçili modu taşımıyor: ${item.title}';
  }
  final lower = '${item.title} ${item.description ?? ''}'.toLowerCase();
  if (mode != 'shinkansen' && lower.contains('shinkansen')) {
    return 'eski Shinkansen metni sızdı';
  }
  if (mode != 'train' && lower.contains('jr special rapid')) {
    return 'eski JR Special Rapid metni sızdı';
  }
  final restored = Trip.fromJson(result.trip!.toJson());
  final restoredDay = restored.days.firstWhere(
    (candidate) => candidate.dayNumber == dayNumber,
  );
  if (restoredDay.cityTransition?.mode != mode ||
      restoredDay.items.where((item) => item.isCityTransition).length != 1) {
    return 'JSON round-trip geçiş metadata kaybetti';
  }
  return null;
}

String _ymd(DateTime date) => '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
