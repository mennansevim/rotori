import 'dart:convert';
import 'dart:io';

import 'route_plan_scenario.dart';
import 'route_scenario_generator.dart';

/// Test fixture'ları yükleyen yardımcı. Boş dosyalar `null`/`isEmpty`
/// döner; test runner "TODO: fixture doldur" atlar.
class RouteFixtureLoader {
  const RouteFixtureLoader({
    this.poisDir = 'test/fixtures/pois',
    this.adversarialDir = 'test/fixtures/scenarios/adversarial',
  });

  final String poisDir;
  final String adversarialDir;

  Map<String, PoiPool> loadPools(List<String> cities) {
    final pools = <String, PoiPool>{};
    for (final city in cities) {
      final file = File('$poisDir/$city.json');
      if (!file.existsSync()) continue;
      final raw = file.readAsStringSync().trim();
      if (raw.isEmpty) continue;
      final map = json.decode(raw) as Map<String, Object?>;
      final hotels = ((map['hotels'] as List?) ?? const [])
          .cast<Map<String, Object?>>()
          .map(PromptHotel.fromJson)
          .toList();
      final pois = ((map['pois'] as List?) ?? const [])
          .cast<Map<String, Object?>>()
          .map(PromptActivity.fromJson)
          .toList();
      if (hotels.isEmpty || pois.isEmpty) continue;
      pools[city] = PoiPool(city: city, hotels: hotels, pois: pois);
    }
    return pools;
  }

  List<RoutePlanScenario> loadAdversarial() {
    final dir = Directory(adversarialDir);
    if (!dir.existsSync()) return const [];
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    final scenarios = <RoutePlanScenario>[];
    for (final file in files) {
      final raw = file.readAsStringSync().trim();
      if (raw.isEmpty) continue;
      try {
        scenarios.add(RoutePlanScenario.decode(raw));
      } on FormatException catch (e) {
        throw StateError(
            'Adversarial fixture bozuk: ${file.path} — ${e.message}');
      }
    }
    return scenarios;
  }
}
