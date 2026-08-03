import 'dart:convert';
import 'dart:io';

import 'planner.dart';
import 'scenario.dart';

/// Rota optimizasyonu core'unu 100 çeşitlendirilmiş senaryoyla test eder ve
/// sonucu gün-gün JSON olarak yazar.
///
/// Çalıştırma (mobile/ dizininden):
///   dart run tool/route_opt_harness/main.dart
///   dart run tool/route_opt_harness/main.dart --count=100 --out=/tmp/rota.json
Future<void> main(List<String> args) async {
  final count = _intArg(args, '--count', 100);
  final out = _strArg(args, '--out',
      '${Directory.current.path}/route_opt_scenarios.json');

  stdout.writeln('▶ $count senaryo üretiliyor (seed sabit, deterministik)…');
  final specs = ScenarioGenerator(count: count).generate();

  final planner = TripPlanner();
  final results = <Map<String, dynamic>>[];

  var feasible = 0, infeasible = 0, dropped = 0;
  final sw = Stopwatch()..start();
  for (final spec in specs) {
    final json = await planner.plan(spec);
    results.add(json);
    final totals = json['tripTotals'] as Map<String, dynamic>;
    feasible += totals['feasibleDays'] as int;
    infeasible += totals['infeasibleDays'] as int;
    dropped += totals['droppedActivities'] as int;
    if (spec.id % 10 == 0) {
      stdout.writeln('  … ${spec.id}/${specs.length} planlandı');
    }
  }
  sw.stop();

  final envelope = {
    'generatedAt': DateTime.now().toIso8601String(),
    'optimizer': 'BeamSearchItineraryOptimizer',
    'note':
        'Şehir-içi günler beam-search ile saatlendi; şehirler-arası shinkansen '
            've havaalanı transferleri belgelenmiş bloklardır. Öğünler sabit '
            'zamanlı (kahvaltı/öğle/akşam). Ulaşım süreleri test için '
            'koordinattan türetilmiş sentetik değerlerdir.',
    'scenarioCount': results.length,
    'summary': {
      'feasibleDays': feasible,
      'infeasibleDays': infeasible,
      'droppedActivities': dropped,
      'elapsedMs': sw.elapsedMilliseconds,
    },
    'scenarios': results,
  };

  final encoder = const JsonEncoder.withIndent('  ');
  final file = File(out);
  await file.writeAsString(encoder.convert(envelope));

  stdout.writeln('');
  stdout.writeln('✅ Tamamlandı — ${sw.elapsedMilliseconds} ms');
  stdout.writeln('   feasible gün: $feasible · infeasible gün: $infeasible · '
      'düşürülen aktivite: $dropped');
  stdout.writeln('   JSON: $out');
}

int _intArg(List<String> args, String name, int fallback) {
  for (final a in args) {
    if (a.startsWith('$name=')) return int.tryParse(a.split('=')[1]) ?? fallback;
  }
  return fallback;
}

String _strArg(List<String> args, String name, String fallback) {
  for (final a in args) {
    if (a.startsWith('$name=')) return a.split('=')[1];
  }
  return fallback;
}
