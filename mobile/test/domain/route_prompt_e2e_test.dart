import 'package:flutter_test/flutter_test.dart';

import '../support/route_fixture_loader.dart';
import '../support/route_hard_checker.dart';
import '../support/route_plan_agent.dart';
import '../support/route_plan_scenario.dart';
import '../support/route_scenario_generator.dart';
import '../support/route_score.dart';

/// Section B — rota promptu için entegrasyon iskeleti.
///
/// Şu anki durum: iskelet aktif ancak fixture'lar boş. `test/fixtures/pois/*`
/// ve `test/fixtures/scenarios/adversarial/A*.json` doldurulunca test seti
/// otomatik olarak koşumlu senaryolara döner. Boş kaldıkça test runner
/// `skip` mesajıyla neyin eksik olduğunu bildirir.

const _cities = <String>[
  'tokyo',
  'kyoto',
  'osaka',
  'hakone',
  'nara',
  'hiroshima',
  'kanazawa',
  'nikko',
  'takayama',
  'kamakura',
];

const _minimumAverageScore = 82;

void main() {
  group('route prompt e2e', () {
    const loader = RouteFixtureLoader();
    final pools = loader.loadPools(_cities);
    final adversarial = loader.loadAdversarial();
    const agent = BeamSearchPlannerAgent();
    const checker = RouteHardChecker();
    const scorer = RouteScorer();

    test('rand seed=1 batch — 10 senaryo hard-check + avg ≥ $_minimumAverageScore',
        () async {
      if (pools.isEmpty) {
        markTestSkipped(
          'POI havuzu boş — test/fixtures/pois/*.json dosyalarını doldurun.',
        );
        return;
      }
      final generator = ScenarioGenerator(
        pools: pools,
        baseDate: DateTime(2026, 9, 1),
      );
      final scenarios = generator.generate(1);
      expect(scenarios, isNotEmpty,
          reason: 'Generator senaryo üretemedi — havuzları kontrol edin.');
      final scores = <double>[];
      for (final scenario in scenarios) {
        final output = await agent.plan(scenario);
        if (output == null) {
          fail('Ajan ${scenario.id} için plan üretmedi.');
        }
        final hardReport = checker.evaluate(scenario, output);
        expect(hardReport.passed, isTrue,
            reason: '${scenario.id} → ${hardReport.failures}');
        final benchmarkResult = await planWithBeamSearch(scenario);
        final benchmark = ScoreBenchmark(
          transitMinutes:
              benchmarkResult.result.metrics?.totalTravelMinutes ?? 0,
          transfers:
              benchmarkResult.result.metrics?.totalTransferCount ?? 0,
        );
        final breakdown = scorer.score(
          scenario: scenario,
          output: output,
          benchmark: benchmark,
        );
        scores.add(breakdown.total);
      }
      final average = scores.reduce((a, b) => a + b) / scores.length;
      expect(average, greaterThanOrEqualTo(_minimumAverageScore.toDouble()),
          reason: 'Ortalama skor: ${average.toStringAsFixed(2)}');
    });

    test('adversarial A1–A7 — regresyon kilidi', () async {
      if (adversarial.isEmpty) {
        markTestSkipped(
          'Adversarial fixture yok — test/fixtures/scenarios/adversarial/A*.json',
        );
        return;
      }
      for (final scenario in adversarial) {
        final output = await agent.plan(scenario);
        expect(output, isNotNull,
            reason:
                '${scenario.id} ajanın plan üretmesini bekliyor — infeasible ise dropped[] beklenir.');
        final hardReport = checker.evaluate(scenario, output!);
        expect(hardReport.passed, isTrue,
            reason: '${scenario.id} → ${hardReport.failures}');
      }
    });
  });

  group('route prompt scaffold — sözleşme testleri', () {
    test('RoutePlanScenario JSON round-trip', () {
      final scenario = _sampleScenario();
      final decoded = RoutePlanScenario.fromJson(scenario.toJson());
      expect(decoded.id, scenario.id);
      expect(decoded.hotel.name, scenario.hotel.name);
      expect(decoded.activities.length, scenario.activities.length);
      expect(decoded.routeMatrix.length, scenario.routeMatrix.length);
    });

    test('BeamSearch mock ajanı örnek senaryoda plan üretir', () async {
      final scenario = _sampleScenario();
      final output = await const BeamSearchPlannerAgent().plan(scenario);
      expect(output, isNotNull);
      expect(output!.timeline, isNotEmpty);
    });

    test('Hard checker gap ihlalini yakalar', () {
      final scenario = _sampleScenario();
      final output = RoutePlanOutput(
        date: scenario.date,
        timeline: const [
          PromptTimelineEntry.activity(
            startTime: '09:00',
            endTime: '10:00',
            activityId: 'act1',
          ),
          PromptTimelineEntry.activity(
            startTime: '11:00', // 10:00 → 11:00 gap
            endTime: '12:00',
            activityId: 'act2',
          ),
        ],
        dropped: const [],
        metrics: const PromptMetrics(
          totalTransitMinutes: 0,
          totalWalkingMinutes: 0,
          totalTransfers: 0,
          totalYenCost: 0,
          clusterEntries: 1,
          backtracking: 0,
          hasLunch: false,
          hasDinner: false,
        ),
        warnings: const [],
      );
      final report = const RouteHardChecker().evaluate(scenario, output);
      expect(report.passed, isFalse);
      expect(report.failures.any((f) => f.code == 'timeline_gap'), isTrue);
    });
  });
}

RoutePlanScenario _sampleScenario() {
  final dayStart = DateTime(2026, 10, 14, 8, 30);
  final dayEnd = DateTime(2026, 10, 14, 21, 0);
  return RoutePlanScenario(
    id: 'sample',
    date: '2026-10-14',
    city: 'tokyo',
    hotel: const PromptHotel(
      id: 'hotel',
      name: 'Sample Hotel',
      latitude: 35.68,
      longitude: 139.76,
      cluster: 'chuo',
    ),
    dayStart: dayStart,
    dayEnd: dayEnd,
    activities: const [
      PromptActivity(
        id: 'act1',
        name: 'Meiji Shrine',
        latitude: 35.6764,
        longitude: 139.6993,
        cluster: 'shibuya',
        category: PromptActivityCategory.shrine,
        durationMinutes: 90,
      ),
      PromptActivity(
        id: 'lunch',
        name: 'Ichiran Ramen',
        latitude: 35.6595,
        longitude: 139.7005,
        cluster: 'shibuya',
        category: PromptActivityCategory.meal,
        durationMinutes: 60,
      ),
      PromptActivity(
        id: 'dinner',
        name: 'Sushi Dai',
        latitude: 35.6654,
        longitude: 139.7707,
        cluster: 'chuo',
        category: PromptActivityCategory.meal,
        durationMinutes: 60,
        fixedStartTime: '19:00',
        fixedEndTime: '20:00',
        isFixed: true,
        hasReservation: true,
      ),
    ],
    routeMatrix: _sampleMatrix(),
    notes: 'scaffold sanity check',
  );
}

List<PromptRouteEntry> _sampleMatrix() {
  const nodes = ['hotel', 'act1', 'lunch', 'dinner'];
  final entries = <PromptRouteEntry>[];
  for (final from in nodes) {
    for (final to in nodes) {
      if (from == to) continue;
      entries.add(PromptRouteEntry(
        fromId: from,
        toId: to,
        mode: PromptTransportMode.metro,
        doorToDoorMinutes: 15,
        walkingMinutes: 5,
        transferCount: 0,
        yenCost: 200,
        reliability: 0.95,
      ));
    }
  }
  return entries;
}
