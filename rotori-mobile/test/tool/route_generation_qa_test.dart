import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/route_generation_qa/qa.dart';

void main() {
  test('160 gerçek plan üretimi kalite kapılarının tamamını geçer', () {
    final count = int.tryParse(
          Platform.environment['ROTORI_ROUTE_QA_COUNT'] ?? '',
        ) ??
        160;
    final seed = int.tryParse(
          Platform.environment['ROTORI_ROUTE_QA_SEED'] ?? '',
        ) ??
        20260811;
    final report = buildRouteGenerationQa(
      scenarioCount: count,
      seed: seed,
    );
    final outputPath = Platform.environment['ROTORI_ROUTE_QA_OUT'];
    if (outputPath != null && outputPath.isNotEmpty) {
      File(outputPath).writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(report),
      );
    }

    final gate = report['qualityGate'] as Map<String, dynamic>;
    final summary = report['summary'] as Map<String, dynamic>;
    expect(gate['passed'], isTrue, reason: jsonEncode(report['failures']));
    expect(summary['plansGenerated'], count);
    expect(summary['adjacentDuplicateCount'], 0);
    expect(summary['transitionMismatchCount'], 0);
    expect(summary['transitionModeChecks'], greaterThan(0));
  });
}
