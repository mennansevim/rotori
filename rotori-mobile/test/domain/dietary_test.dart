import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/domain/dietary.dart';
import 'package:rotori/domain/types.dart';

void main() {
  test('vegan seçimi çelişen hayvansal ürün seçimlerini kaldırır', () {
    final update = toggleDietaryTag(
      const ['meat_ok', 'seafood_ok', 'no_alcohol'],
      'vegan',
    );

    expect(update.selected, containsAll(<String>['vegan', 'no_alcohol']));
    expect(update.selected, isNot(contains('meat_ok')));
    expect(update.selected, isNot(contains('seafood_ok')));
    expect(update.removed, containsAll(<String>['meat_ok', 'seafood_ok']));
  });

  test('et tercihi vegan/vejetaryen seçimlerini kaldırır', () {
    final update = toggleDietaryTag(
      const ['vegan', 'no_pork'],
      'meat_ok',
    );

    expect(update.selected, containsAll(<String>['meat_ok', 'no_pork']));
    expect(update.selected, isNot(contains('vegan')));
  });

  test('plan varsayımları versioned JSON turunda korunur', () {
    const assumptions = PlanAssumptions(
      dateSource: 'seasonalSuggestion',
      dateRationale: 'seasonalWeatherAndCrowdBalance',
      flightStatus: 'draft',
      hotelStatus: 'draft',
    );

    final restored = PlanAssumptions.tryFromJson(assumptions.toJson());

    expect(restored, isNotNull);
    expect(restored!.schemaVersion, PlanAssumptions.currentSchemaVersion);
    expect(restored.dateSource, 'seasonalSuggestion');
    expect(restored.flightStatus, 'draft');
    expect(
      PlanAssumptions.tryFromJson({
        ...assumptions.toJson(),
        'schemaVersion': 999,
      }),
      isNull,
    );
  });
}
