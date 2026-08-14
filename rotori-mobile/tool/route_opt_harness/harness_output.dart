import 'dart:convert';

import 'scenario.dart';

const int harnessSchemaVersion = 2;

Map<String, dynamic> buildHarnessEnvelope({
  required DateTime generatedAt,
  required int seed,
  required SuiteMode suiteMode,
  required String matrixVersion,
  required String gitSha,
  required int beamWidth,
  required int localImprovementPasses,
  required bool allowActivityDropping,
  required int elapsedMs,
  required List<Map<String, dynamic>> scenarios,
}) {
  final days = scenarios
      .expand((scenario) => (scenario['days'] as List<dynamic>? ?? const []))
      .cast<Map<String, dynamic>>()
      .toList(growable: false);
  int sum(String key) => days.fold<int>(
        0,
        (total, day) => total + ((day[key] as num?)?.toInt() ?? 0),
      );
  int count(bool Function(Map<String, dynamic>) predicate) =>
      days.where(predicate).length;
  int duplicateActivities() {
    var duplicates = 0;
    for (final scenario in scenarios) {
      final seen = <String>{};
      final scenarioDays = scenario['days'] as List<dynamic>? ?? const [];
      for (final rawDay in scenarioDays) {
        final day = rawDay as Map<String, dynamic>;
        final inputs = day['inputActivities'] as List<dynamic>? ?? const [];
        for (final rawInput in inputs) {
          final input = rawInput as Map<String, dynamic>;
          final id = input['id'] as String?;
          if (id != null && !seen.add(id) && input['repeatFixture'] != true) {
            duplicates++;
          }
        }
      }
    }
    return duplicates;
  }

  int countDroppedPriority(String priority) => days.fold<int>(0, (total, day) {
        final dropped = day['dropped'] as List<dynamic>? ?? const [];
        return total +
            dropped.where((raw) {
              final item = raw as Map<String, dynamic>;
              return item['priority'] == priority;
            }).length;
      });

  final baseScenarioCount = scenarios
      .map((scenario) => scenario['baseScenarioId'] ?? scenario['id'])
      .toSet()
      .length;
  final profileComparison = <String, Map<String, num>>{};
  for (final profile in const [
    'balanced',
    'fastest',
    'leastWalking',
    'cheapest',
  ]) {
    final runs = scenarios.where((scenario) => scenario['profile'] == profile);
    if (runs.isEmpty) continue;
    int total(String key) => runs.fold<int>(0, (sum, scenario) {
          final totals = scenario['tripTotals'] as Map<String, dynamic>;
          return sum + ((totals[key] as num?)?.toInt() ?? 0);
        });
    profileComparison[profile] = {
      'runCount': runs.length,
      'averageTravelMinutes': total('inCityTravelMin') / runs.length,
      'averageWalkingMinutes': total('inCityWalkingMin') / runs.length,
      'averagePartyCostYen': total('inCityPartyTotalYen') / runs.length,
    };
  }
  num profileMetric(String profile, String metric) =>
      profileComparison[profile]?[metric] ?? double.infinity;
  bool isLowest(String profile, String metric) {
    final value = profileMetric(profile, metric);
    return profileComparison.keys.every(
      (candidate) => value <= profileMetric(candidate, metric),
    );
  }

  final requestedCount = sum('requestedActivityCount');
  final droppedCount = sum('droppedActivityCount');
  final evaluatedCount = count((day) => day['optimizerEvaluated'] == true);
  final reentryDayCount = count((day) {
    final metrics = day['metrics'];
    return metrics is Map &&
        ((metrics['clusterReentryCount'] as num?)?.toInt() ?? 0) > 0;
  });
  final kyotoDays = count(
      (day) => day['city'] == 'Kyoto' && day['optimizerEvaluated'] == true);
  final kyotoReentryDays = count((day) {
    final metrics = day['metrics'];
    return day['city'] == 'Kyoto' &&
        metrics is Map &&
        ((metrics['clusterReentryCount'] as num?)?.toInt() ?? 0) > 0;
  });
  final longIdleDays = count((day) {
    final metrics = day['metrics'];
    return metrics is Map &&
        ((metrics['scheduleIdleMinutes'] as num?)?.toInt() ?? 0) > 90;
  });

  return {
    'schemaVersion': harnessSchemaVersion,
    'generatedAt': generatedAt.toIso8601String(),
    'suite': {
      'seed': seed,
      'mode': suiteMode.name,
      'scenarioCount': baseScenarioCount,
      'profileRunCount': scenarios.length,
      'matrixVersion': matrixVersion,
      'matrixEstimated': true,
      'gitSha': gitSha,
    },
    'optimizerConfig': {
      'name': 'BeamSearchItineraryOptimizer',
      'beamWidth': beamWidth,
      'localImprovementPasses': localImprovementPasses,
      'allowActivityDropping': allowActivityDropping,
    },
    'summary': {
      'totalDayRecords': days.length,
      'optimizerEvaluatedDays':
          count((day) => day['optimizerEvaluated'] == true),
      'fieldRealityContextDays':
          count((day) => day['fieldRealityContextEnabled'] == true),
      'strictFeasibleDays': count((day) => day['strictFeasible'] == true),
      'recoveredByDroppingDays':
          count((day) => day['recoveredByDropping'] == true),
      'infeasibleDays': count((day) =>
          day['optimizerEvaluated'] == true && day['feasible'] != true),
      'departureOnlyDays': count((day) => day['type'] == 'departure'),
      'nonOptimizerFreeDays': count((day) =>
          day['optimizerEvaluated'] == false && day['type'] != 'departure'),
      'requestedActivityCount': sum('requestedActivityCount'),
      'scheduledActivityCount': sum('scheduledActivityCount'),
      'droppedActivityCount': sum('droppedActivityCount'),
      'requestedActivities': sum('requestedActivityCount'),
      'scheduledActivities': sum('scheduledActivityCount'),
      'droppedActivities': sum('droppedActivityCount'),
      'hardViolationCount': sum('hardViolationCount'),
      'duplicateActivityCount': duplicateActivities(),
      'mustDoDroppedCount': countDroppedPriority('mustDo'),
      'missingReturnLegCount': count((day) {
        if (day['optimizerEvaluated'] != true ||
            day['feasible'] != true ||
            ((day['requestedActivityCount'] as num?)?.toInt() ?? 0) == 0) {
          return false;
        }
        final timeline = day['timeline'] as List<dynamic>? ?? const [];
        return !timeline
            .any((raw) => (raw as Map<String, dynamic>)['kind'] == 'return');
      }),
      'longIdleDayCount': longIdleDays,
      'clusterReentryDayCount': reentryDayCount,
      'kyotoClusterReentryDayCount': kyotoReentryDays,
      'estimatedWarningMissingCount': count((day) {
        final timeline = day['timeline'] as List<dynamic>? ?? const [];
        final hasEstimated = timeline.any((raw) {
          final item = raw as Map<String, dynamic>;
          return item['isEstimated'] == true;
        });
        final warnings = day['warnings'] as List<dynamic>? ?? const [];
        return hasEstimated &&
            !warnings.any((warning) =>
                warning.toString().contains('yaklaşık') ||
                warning.toString().contains('estimated'));
      }),
      'elapsedMs': elapsedMs,
    },
    'profileComparison': profileComparison,
    'qualityGate': {
      'fieldRealityCoveragePass': count((day) =>
              day['optimizerEvaluated'] == true &&
              day['fieldRealityContextEnabled'] != true) ==
          0,
      'hardConstraintsPass': sum('hardViolationCount') == 0,
      'duplicatesPass': duplicateActivities() == 0,
      'mustDoProtectionPass': countDroppedPriority('mustDo') == 0,
      'returnLegsPass': count((day) {
            if (day['optimizerEvaluated'] != true ||
                day['feasible'] != true ||
                ((day['requestedActivityCount'] as num?)?.toInt() ?? 0) == 0) {
              return false;
            }
            final timeline = day['timeline'] as List<dynamic>? ?? const [];
            return !timeline.any(
                (raw) => (raw as Map<String, dynamic>)['kind'] == 'return');
          }) ==
          0,
      'droppingRate': requestedCount == 0 ? 0 : droppedCount / requestedCount,
      'droppingRatePass':
          requestedCount == 0 || droppedCount / requestedCount < .03,
      'clusterReentryRate':
          evaluatedCount == 0 ? 0 : reentryDayCount / evaluatedCount,
      'clusterReentryPass':
          evaluatedCount == 0 || reentryDayCount / evaluatedCount < .25,
      'kyotoClusterReentryRate':
          kyotoDays == 0 ? 0 : kyotoReentryDays / kyotoDays,
      'kyotoClusterReentryPass':
          kyotoDays == 0 || kyotoReentryDays / kyotoDays < .30,
      'longIdleRate': evaluatedCount == 0 ? 0 : longIdleDays / evaluatedCount,
      'longIdlePass':
          evaluatedCount == 0 || longIdleDays / evaluatedCount < .05,
      'estimatedWarningsPass': count((day) {
            final timeline = day['timeline'] as List<dynamic>? ?? const [];
            final hasEstimated = timeline.any(
                (raw) => (raw as Map<String, dynamic>)['isEstimated'] == true);
            final warnings = day['warnings'] as List<dynamic>? ?? const [];
            return hasEstimated &&
                !warnings.any((warning) =>
                    warning.toString().contains('yaklaşık') ||
                    warning.toString().contains('estimated'));
          }) ==
          0,
      'fastestProfilePass': isLowest('fastest', 'averageTravelMinutes'),
      'leastWalkingProfilePass':
          isLowest('leastWalking', 'averageWalkingMinutes'),
      'cheapestProfilePass': isLowest('cheapest', 'averagePartyCostYen'),
    },
    'scenarios': scenarios,
  };
}

/// Zaman ve çalışma ortamı kaynaklı alanları çıkarıp anahtarları sıralı,
/// semantik olarak karşılaştırılabilir JSON üretir.
String semanticHarnessJson(Map<String, dynamic> envelope) {
  final normalized = _normalize(envelope, isRoot: true);
  return jsonEncode(normalized);
}

Object? _normalize(Object? value, {bool isRoot = false}) {
  if (value is List) {
    return value.map((item) => _normalize(item)).toList(growable: false);
  }
  if (value is! Map) return value;

  final sortedKeys = value.keys.map((key) => key.toString()).toList()..sort();
  final result = <String, dynamic>{};
  for (final key in sortedKeys) {
    if (isRoot && key == 'generatedAt') continue;
    final raw = value[key];
    if (key == 'summary' && raw is Map) {
      final summary = Map<String, dynamic>.from(raw.cast<String, dynamic>())
        ..remove('elapsedMs');
      result[key] = _normalize(summary);
    } else {
      result[key] = _normalize(raw);
    }
  }
  return result;
}
