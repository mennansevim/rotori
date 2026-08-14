import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/domain/route_matrix.dart';

import '../../tool/route_opt_harness/matrix_builder.dart';
import '../../tool/route_opt_harness/harness_output.dart';
import '../../tool/route_opt_harness/planner.dart';
import '../../tool/route_opt_harness/poi_data.dart';
import '../../tool/route_opt_harness/scenario.dart';

/// P0 doğruluk fixleri için harness regresyonları:
///  - yemek yeri çalışma saatleri korunur (kapalı yere akşam yemeği yazılmaz),
///  - tam gün / uzak gezi POI'leri açık gün rolüyle izole edilir,
///  - aynı koordinatlı legler sıfırlanır (yapay kahvaltı yürüyüşü yok).
void main() {
  group('Harness sözleşmesi ve determinizm (Faz 0)', () {
    test('şema v2 strict/dropping/departure sayaçlarını ayrıştırır', () async {
      final spec =
          ScenarioGenerator(count: 1, seed: 20260803).generate().single;
      final scenario = await TripPlanner().plan(spec);
      final envelope = buildHarnessEnvelope(
        generatedAt: DateTime.utc(2026, 8, 3),
        seed: 20260803,
        suiteMode: SuiteMode.product,
        matrixVersion: MatrixBuilder.version,
        gitSha: 'test',
        beamWidth: 7,
        localImprovementPasses: 3,
        allowActivityDropping: true,
        elapsedMs: 12,
        scenarios: [scenario],
      );

      expect(envelope['schemaVersion'], 2);
      final summary = envelope['summary'] as Map<String, dynamic>;
      expect(summary['totalDayRecords'], spec.totalDays);
      expect(summary['departureOnlyDays'], 1);
      expect(
        summary['optimizerEvaluatedDays'],
        (summary['strictFeasibleDays'] as int) +
            (summary['recoveredByDroppingDays'] as int) +
            (summary['infeasibleDays'] as int),
      );
      expect(
        summary['fieldRealityContextDays'],
        summary['optimizerEvaluatedDays'],
      );
      expect(
        summary['requestedActivityCount'],
        (summary['scheduledActivityCount'] as int) +
            (summary['droppedActivityCount'] as int),
      );
      expect(summary['hardViolationCount'], 0);
      expect(summary['duplicateActivityCount'], 0);
      expect(summary['mustDoDroppedCount'], 0);
      expect(summary['missingReturnLegCount'], 0);
      expect(summary['estimatedWarningMissingCount'], 0);
      final qualityGate = envelope['qualityGate'] as Map<String, dynamic>;
      expect(qualityGate['fieldRealityCoveragePass'], isTrue);
      expect(qualityGate['droppingRatePass'], isTrue);

      final disneyDay = (scenario['days'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .firstWhere(
            (day) => (day['inputActivities'] as List<dynamic>).any(
              (raw) => (raw as Map<String, dynamic>)['id'] == 'tk_disneysea',
            ),
          );
      final scheduledNames = (disneyDay['schedule'] as List<dynamic>)
          .map((raw) => (raw as Map<String, dynamic>)['name']);
      expect(disneyDay['droppedActivityIds'], isNot(contains('tk_disneysea')));
      expect(scheduledNames, contains('Tokyo DisneySea'));
    });

    test('aynı seed semantik olarak aynı JSON üretir', () async {
      Future<Map<String, dynamic>> run(
          DateTime generatedAt, int elapsedMs) async {
        final specs = ScenarioGenerator(count: 2, seed: 42).generate();
        final planner = TripPlanner();
        final scenarios = <Map<String, dynamic>>[];
        for (final spec in specs) {
          scenarios.add(await planner.plan(spec));
        }
        return buildHarnessEnvelope(
          generatedAt: generatedAt,
          seed: 42,
          suiteMode: SuiteMode.product,
          matrixVersion: MatrixBuilder.version,
          gitSha: 'test',
          beamWidth: 7,
          localImprovementPasses: 3,
          allowActivityDropping: true,
          elapsedMs: elapsedMs,
          scenarios: scenarios,
        );
      }

      final first = await run(DateTime.utc(2026, 8, 3), 1);
      final second = await run(DateTime.utc(2027, 1, 1), 999);
      expect(semanticHarnessJson(first), semanticHarnessJson(second));
    });

    test('base senaryolar aynı girdide dört profile paired genişler', () {
      final paired =
          ScenarioGenerator(count: 2, seed: 42).generatePairedProfiles();
      expect(paired, hasLength(8));
      for (final baseId in paired.map((spec) => spec.baseScenarioId).toSet()) {
        final group = paired.where((spec) => spec.baseScenarioId == baseId);
        expect(group.map((spec) => spec.profile).toSet(), {
          'balanced',
          'fastest',
          'leastWalking',
          'cheapest',
        });
        expect(group.map((spec) => spec.routeLabel).toSet(), hasLength(1));
      }
    });

    test('transfer timeline gezi penceresi başlamadan biter', () async {
      final spec =
          ScenarioGenerator(count: 1, seed: 20260803).generate().single;
      final scenario = await TripPlanner().plan(spec);
      for (final rawDay in scenario['days'] as List<dynamic>) {
        final day = rawDay as Map<String, dynamic>;
        final block = day['arrivalTransfer'] ?? day['cityTransfer'];
        if (block is! Map<String, dynamic>) continue;
        if (day['window'] is! String) continue;
        final timeline = block['timeline'] as List<dynamic>;
        final transferEnd =
            (timeline.last as Map<String, dynamic>)['end'] as String;
        final window = day['window'] as String;
        final sightseeingStart = window.split('–').first;
        expect(
          _minutes(transferEnd),
          lessThanOrEqualTo(_minutes(sightseeingStart)),
          reason: '${day['city']} transfer/gezi çakışıyor',
        );
      }
    });
  });

  group('Yemek yeri çalışma saatleri (Faz 1.1)', () {
    test('Tsukiji öğle olabilir ama akşam yemeği olamaz', () {
      final tsukiji = pois.firstWhere((p) => p.id == 'tk_tsukiji');
      expect(tsukiji.servesMeal(MealPeriod.lunch, 11, 15, 40), isTrue);
      expect(tsukiji.servesMeal(MealPeriod.dinner, 18, 22, 55), isFalse);
    });

    test('Nishiki 18:00 sonrası akşam yemeği veremez', () {
      final nishiki = pois.firstWhere((p) => p.id == 'ky_nishiki');
      expect(nishiki.servesMeal(MealPeriod.dinner, 18, 22, 55), isFalse);
    });

    test('Kuromon 18:00 kapanışında akşam yemeği veremez', () {
      final kuromon = pois.firstWhere((p) => p.id == 'os_namba');
      expect(kuromon.servesMeal(MealPeriod.dinner, 18, 22, 55), isFalse);
    });

    test('Her şehirde en az bir gerçek akşam yemeği yeri var', () {
      for (final city in const [
        'Tokyo',
        'Kyoto',
        'Osaka',
        'Nara',
        'Hiroshima'
      ]) {
        final dinners = mealVenues(city, MealPeriod.dinner, 18, 22, 55);
        expect(dinners, isNotEmpty, reason: '$city akşam yemeği yeri yok');
      }
    });

    test('Akşam yemeği adayları hiçbir zaman kapalı market değildir', () {
      const markets = {'tk_tsukiji', 'ky_nishiki', 'os_namba'};
      for (final city in const ['Tokyo', 'Kyoto', 'Osaka']) {
        final dinners = mealVenues(city, MealPeriod.dinner, 18, 22, 55);
        for (final d in dinners) {
          expect(markets.contains(d.id), isFalse,
              reason: '${d.id} akşam yemeğine uygun sayıldı');
        }
      }
    });
  });

  group('POI gün rolleri (Faz 1.2)', () {
    test('USJ ve DisneySea fullDayExclusive', () {
      expect(pois.firstWhere((p) => p.id == 'os_usj').dayRole,
          PoiDayRole.fullDayExclusive);
      expect(pois.firstWhere((p) => p.id == 'tk_disneysea').dayRole,
          PoiDayRole.fullDayExclusive);
    });

    test('Miyajima excursion rolündedir', () {
      expect(pois.firstWhere((p) => p.id == 'hr_miyajima').dayRole,
          PoiDayRole.excursion);
    });

    test('Horyu-ji uzak cluster half-day anchor', () {
      expect(pois.firstWhere((p) => p.id == 'nr_horyuji').dayRole,
          PoiDayRole.halfDayAnchor);
    });
  });

  group('Sıfır co-located leg (Faz 1.3)', () {
    test('Aynı koordinat 0 dakikalık leg üretir', () {
      const builder = MatrixBuilder();
      const hotel = TripLocation(
        id: 'hotel',
        name: 'Otel',
        latitude: 35.6938,
        longitude: 139.7034,
        city: 'Tokyo',
        clusterId: 'shinjuku',
      );
      const breakfast = TripLocation(
        id: 'breakfast',
        name: 'Kahvaltı',
        latitude: 35.6938,
        longitude: 139.7034,
        city: 'Tokyo',
        clusterId: 'shinjuku',
      );
      final matrix = builder.build([hotel, breakfast]);
      final leg = matrix.entries.firstWhere(
        (e) => e.fromLocationId == 'hotel' && e.toLocationId == 'breakfast',
      );
      expect(leg.options.single.doorToDoorMinutes, 0);
      expect(leg.options.single.walkingMinutes, 0);
    });

    test('sentetik matris A→B ve B→A için yönlü asimetri taşır', () {
      const builder = MatrixBuilder();
      const a = TripLocation(
        id: 'a',
        name: 'A',
        latitude: 35,
        longitude: 139,
        clusterId: 'west',
      );
      const b = TripLocation(
        id: 'b',
        name: 'B',
        latitude: 35.08,
        longitude: 139.08,
        clusterId: 'east',
      );
      final matrix = builder.build(
        const [a, b],
        departureTime: DateTime(2026, 8, 3, 8),
      );
      final outbound = matrix.options('a', 'b').firstWhere(
            (option) =>
                option.mode == TransportMode.train ||
                option.mode == TransportMode.metro,
          );
      final inbound = matrix.options('b', 'a').firstWhere(
            (option) =>
                option.mode == TransportMode.train ||
                option.mode == TransportMode.metro,
          );
      expect(outbound.doorToDoorMinutes, isNot(inbound.doorToDoorMinutes));
      expect(outbound.isEstimated, isTrue);
      expect(inbound.isEstimated, isTrue);
    });

    test('sabah pik time slice öğlen rotasından daha uzundur', () {
      const builder = MatrixBuilder();
      const a = TripLocation(
        id: 'slice-a',
        name: 'A',
        latitude: 35,
        longitude: 139,
        clusterId: 'west',
      );
      const b = TripLocation(
        id: 'slice-b',
        name: 'B',
        latitude: 35.08,
        longitude: 139.08,
        clusterId: 'east',
      );
      TransportOption transit(RouteMatrix matrix) =>
          matrix.options(a.id, b.id).firstWhere(
                (option) =>
                    option.mode == TransportMode.train ||
                    option.mode == TransportMode.metro,
              );
      final morning = transit(builder.build(
        const [a, b],
        departureTime: DateTime(2026, 8, 3, 8),
      ));
      final noon = transit(builder.build(
        const [a, b],
        departureTime: DateTime(2026, 8, 3, 12),
      ));
      expect(morning.doorToDoorMinutes, greaterThan(noon.doorToDoorMinutes));
    });
  });
}

int _minutes(String value) {
  final parts = value.split(':');
  return int.parse(parts[0]) * 60 + int.parse(parts[1]);
}
