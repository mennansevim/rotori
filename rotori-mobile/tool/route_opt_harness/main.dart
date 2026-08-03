import 'dart:convert';
import 'dart:io';

import 'harness_output.dart';
import 'matrix_builder.dart';
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
  final seed = _intArg(args, '--seed', 20260803);
  final beamWidth = _intArg(args, '--beam-width', 6);
  final suiteMode = parseSuiteMode(_strArg(args, '--suite', 'product'));
  final out = _strArg(
      args, '--out', '${Directory.current.path}/route_opt_scenarios.json');
  final gitSha = _strArg(
    args,
    '--git-sha',
    Platform.environment['GIT_COMMIT_SHA'] ?? 'unknown',
  );

  stdout.writeln(
      '▶ $count senaryo üretiliyor (seed=$seed, suite=${suiteMode.name})…');
  final specs = ScenarioGenerator(
    count: count,
    seed: seed,
    suiteMode: suiteMode,
  ).generatePairedProfiles();

  final planner = TripPlanner(beamWidth: beamWidth);
  final results = <Map<String, dynamic>>[];

  final sw = Stopwatch()..start();
  for (var i = 0; i < specs.length; i++) {
    final spec = specs[i];
    final json = await planner.plan(spec, suiteMode: suiteMode);
    results.add(json);
    if ((i + 1) % 20 == 0) {
      stdout.writeln('  … ${i + 1}/${specs.length} planlandı');
    }
  }
  sw.stop();

  final envelope = buildHarnessEnvelope(
    generatedAt: DateTime.now(),
    seed: seed,
    suiteMode: suiteMode,
    matrixVersion: MatrixBuilder.version,
    gitSha: gitSha,
    beamWidth: beamWidth,
    localImprovementPasses: 3,
    allowActivityDropping: true,
    elapsedMs: sw.elapsedMilliseconds,
    scenarios: results,
  );

  const encoder = JsonEncoder.withIndent('  ');
  final file = File(out);
  await file.writeAsString(encoder.convert(envelope));

  stdout.writeln('');
  stdout.writeln('✅ Tamamlandı — ${sw.elapsedMilliseconds} ms');
  final summary = envelope['summary'] as Map<String, dynamic>;
  stdout.writeln('   strict: ${summary['strictFeasibleDays']} · '
      'dropping ile kurtarılan: ${summary['recoveredByDroppingDays']} · '
      'infeasible: ${summary['infeasibleDays']}');
  stdout.writeln('   JSON: $out');
}

int _intArg(List<String> args, String name, int fallback) {
  for (final a in args) {
    if (a.startsWith('$name=')) {
      return int.tryParse(a.split('=')[1]) ?? fallback;
    }
  }
  return fallback;
}

String _strArg(List<String> args, String name, String fallback) {
  for (final a in args) {
    if (a.startsWith('$name=')) return a.split('=')[1];
  }
  return fallback;
}
