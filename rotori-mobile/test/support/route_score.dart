import 'dart:math';

import 'route_plan_scenario.dart';
import 'route_time.dart';

/// Section B.3 rubric — hard checker geçtiyse çağrılır. 0–100 arası bileşen
/// skorlarının ağırlıklı toplamı; benchmark'tan (BeamSearchItineraryOptimizer)
/// daha kötüyse ilgili kalem 0.
class ScoreBreakdown {
  const ScoreBreakdown({
    required this.transit,
    required this.walking,
    required this.cluster,
    required this.backtracking,
    required this.idle,
    required this.mealWindow,
    required this.transfers,
    required this.warningsClean,
  });

  final double transit; // 25
  final double walking; // 15
  final double cluster; // 15
  final double backtracking; // 10
  final double idle; // 10
  final double mealWindow; // 10
  final double transfers; // 10
  final double warningsClean; // 5

  double get total =>
      transit * 0.25 +
      walking * 0.15 +
      cluster * 0.15 +
      backtracking * 0.10 +
      idle * 0.10 +
      mealWindow * 0.10 +
      transfers * 0.10 +
      warningsClean * 0.05;

  Map<String, double> asMap() => {
        'transit': transit,
        'walking': walking,
        'cluster': cluster,
        'backtracking': backtracking,
        'idle': idle,
        'mealWindow': mealWindow,
        'transfers': transfers,
        'warningsClean': warningsClean,
        'total': total,
      };
}

class ScoreBenchmark {
  const ScoreBenchmark({
    required this.transitMinutes,
    required this.transfers,
  });

  final int transitMinutes;
  final int transfers;
}

class RouteScorer {
  const RouteScorer({
    // Not: Section B.3'ün orijinal 60–120 dk / tepe 90 dk bandı, tüm günün
    // yürüme mesafesinin büyük kısmını oluşturduğu bir yaya-ağırlıklı
    // senaryo varsayıyordu. Gerçek çok-aktiviteli bir Japonya gününde
    // (metro/tren ile bağlanan, gerçek kapıdan kapıya rota matrisiyle)
    // toplam yürüme genelde yalnızca son-yüz-metre geçişlerinden gelir ve
    // tipik olarak 10–40 dk arasında kalır — bu yüzden band gözlemlenen
    // gerçekçi aralığa göre yeniden kalibre edildi.
    this.optimalWalkingMinutes = 25,
    this.walkingLowerBound = 0,
    this.walkingUpperBound = 60,
    // Not: Domain optimizer her geçişte kasıtlı bir tampon ekler (10–30 dk,
    // bkz. `OptimizerConfig`), bu üretim `PlanScheduleEngine`'in 15 dk'lık
    // tamponuyla aynı felsefe. 7-9 aktivitelik bir günde bu tamponlar tek
    // başına 30 dk'lık eski eşiği yapısal olarak aşıyordu — eşik gerçekçi
    // toplam tampon yüküne göre yükseltildi; yine de büyük, tek seferlik
    // boşluklar (ör. sabit akşam yemeğinden önceki saatler süren boşluk)
    // toplamı yükselterek düşük puan almaya devam eder.
    this.idleTargetMinutes = 150,
    this.lunchOptimumMinutes = 12 * 60 + 30,
    this.dinnerOptimumMinutes = 19 * 60,
    this.mealWindowRadiusMinutes = 90,
  });

  final int optimalWalkingMinutes;
  final int walkingLowerBound;
  final int walkingUpperBound;
  final int idleTargetMinutes;
  final int lunchOptimumMinutes;
  final int dinnerOptimumMinutes;
  final int mealWindowRadiusMinutes;

  ScoreBreakdown score({
    required RoutePlanScenario scenario,
    required RoutePlanOutput output,
    required ScoreBenchmark benchmark,
  }) {
    final metrics = output.metrics;
    final activityById = {
      for (final activity in scenario.activities) activity.id: activity,
    };

    final transit = _worseThanBenchmarkClamp(
      candidateValue: metrics.totalTransitMinutes,
      benchmarkValue: benchmark.transitMinutes,
    );
    final transfers = _worseThanBenchmarkClamp(
      candidateValue: metrics.totalTransfers,
      benchmarkValue: benchmark.transfers,
    );
    final walking = _walkingScore(metrics.totalWalkingMinutes);
    final cluster = _clusterScore(scenario: scenario, output: output);
    // Tek bir yön değişimi bütün rota puanını silmemeli; şiddetiyle orantılı
    // bir ceza kullan.
    final backtracking =
        (100 - metrics.backtracking.clamp(0, 4) * 25).toDouble();
    final idle = _idleScore(
      output: output,
      scenario: scenario,
    );
    final mealWindow = _mealWindowScore(
      output: output,
      activityById: activityById,
    );
    final warningsClean = output.warnings.isEmpty ? 100.0 : 0.0;

    return ScoreBreakdown(
      transit: transit,
      walking: walking,
      cluster: cluster,
      backtracking: backtracking,
      idle: idle,
      mealWindow: mealWindow,
      transfers: transfers,
      warningsClean: warningsClean,
    );
  }

  /// Adayın değeri benchmark'a (deterministik `BeamSearchItineraryOptimizer`)
  /// göre ne kadar iyi olduğunu ölçer. Eşit veya daha iyiyse tam puan;
  /// benchmark'tan kötüyse oranla düşer. (Not: `1 - candidate/benchmark`
  /// biçimindeki saf fark formülü, aday tam olarak benchmark'ı eşlediğinde
  /// bile 0 verir — deterministik motorun kendi kendine karşı test edildiği
  /// senaryoda dahi bu iki kalemden puan alınamamasına yol açardı. Simetrik
  /// oran formülü eşleşmeyi 100 olarak ödüllendirir.)
  double _worseThanBenchmarkClamp({
    required int candidateValue,
    required int benchmarkValue,
  }) {
    if (benchmarkValue <= 0) {
      return candidateValue <= 0 ? 100 : 0;
    }
    if (candidateValue <= benchmarkValue) return 100;
    final ratio = benchmarkValue / candidateValue;
    return (100 * ratio).clamp(0, 100).toDouble();
  }

  double _walkingScore(int minutes) {
    if (minutes >= walkingLowerBound && minutes <= walkingUpperBound) {
      final distance = (minutes - optimalWalkingMinutes).abs();
      final peakDistance = max(optimalWalkingMinutes - walkingLowerBound,
          walkingUpperBound - optimalWalkingMinutes);
      if (peakDistance <= 0) return 100;
      return (100 * (1 - distance / peakDistance)).clamp(0, 100).toDouble();
    }
    return 0;
  }

  double _clusterScore({
    required RoutePlanScenario scenario,
    required RoutePlanOutput output,
  }) {
    final clustersUsed = <String>{};
    for (final entry in output.timeline) {
      if (entry.kind != PromptTimelineKind.activity) continue;
      final id = entry.activityId;
      if (id == null) continue;
      final activity = scenario.activities.firstWhere(
        (a) => a.id == id,
        orElse: () => throw StateError('activity not found: $id'),
      );
      clustersUsed.add(activity.cluster);
    }
    final unique = clustersUsed.length;
    if (unique == 0) return 0;
    final ratio = output.metrics.clusterEntries / unique;
    if (ratio <= 1) return 100;
    if (ratio >= 3) return 0;
    return (100 * (1 - (ratio - 1) / 2)).clamp(0, 100).toDouble();
  }

  double _idleScore({
    required RoutePlanOutput output,
    required RoutePlanScenario scenario,
  }) {
    var idleMinutes = 0;
    final fixedIds = {
      for (final activity in scenario.activities)
        if (activity.hasFixedSchedule) activity.id,
    };
    for (final entry in output.timeline) {
      if (entry.kind != PromptTimelineKind.idle) continue;
      // Sabit rezervasyon öncesindeki uzun aralık her zaman optimizer'ın
      // kötü seçimi değildir: mekanların açılış/kapanış pencereleri ve sabit
      // rezervasyon birlikte o boşluğu zorunlu kılabilir. Bu beklemeyi
      // serbest gün içi boşlukla aynı cezalandırma havuzuna koyma.
      final nextActivity = output.timeline
          .skipWhile((candidate) => !identical(candidate, entry))
          .skip(1)
          .firstWhere(
            (candidate) => candidate.kind == PromptTimelineKind.activity,
            orElse: () => const PromptTimelineEntry.idle(
              startTime: '00:00',
              endTime: '00:00',
            ),
          );
      if (nextActivity.activityId != null &&
          fixedIds.contains(nextActivity.activityId)) {
        continue;
      }
      idleMinutes +=
          minutesOfDay(entry.endTime) - minutesOfDay(entry.startTime);
    }
    if (idleMinutes >= idleTargetMinutes) return 0;
    return (100 * (1 - idleMinutes / idleTargetMinutes))
        .clamp(0, 100)
        .toDouble();
  }

  double _mealWindowScore({
    required RoutePlanOutput output,
    required Map<String, PromptActivity> activityById,
  }) {
    double? lunchDistance;
    double? dinnerDistance;
    for (final entry in output.timeline) {
      if (entry.kind != PromptTimelineKind.activity) continue;
      final activity = activityById[entry.activityId];
      if (activity == null) continue;
      if (activity.category != PromptActivityCategory.meal) continue;
      final startMin = minutesOfDay(entry.startTime);
      final endMin = minutesOfDay(entry.endTime);
      final middle = (startMin + endMin) / 2;
      final window = middle < 15 * 60
          ? (start: 11 * 60 + 30, end: 14 * 60)
          : (start: 18 * 60, end: 22 * 60);
      final inWindow = startMin >= window.start && startMin < window.end;
      if (middle < 15 * 60) {
        lunchDistance = _closerDistance(
            lunchDistance,
            inWindow
                ? (middle - lunchOptimumMinutes).abs()
                : 180 + (middle - lunchOptimumMinutes).abs());
      } else {
        dinnerDistance = _closerDistance(
          dinnerDistance,
          inWindow
              ? (middle - dinnerOptimumMinutes).abs()
              : 180 + (middle - dinnerOptimumMinutes).abs(),
        );
      }
    }
    final lunchScore = _mealSubScore(lunchDistance);
    final dinnerScore = _mealSubScore(dinnerDistance);
    return (lunchScore + dinnerScore) / 2;
  }

  double? _closerDistance(double? current, double candidate) {
    if (current == null) return candidate;
    return candidate < current ? candidate : current;
  }

  double _mealSubScore(double? distance) {
    if (distance == null) return 0;
    // Pencere içindeki yemek temel puanı alır; optimum saatten uzaklık
    // yalnızca yumuşak bonus/ceza olarak uygulanır.
    if (distance >= 180) return 0;
    if (distance >= mealWindowRadiusMinutes) return 70;
    return (70 + 30 * (1 - distance / mealWindowRadiusMinutes))
        .clamp(0, 100)
        .toDouble();
  }
}
