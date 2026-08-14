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

  test('et, kanatlı ve deniz ürünü birlikte seçilebilir', () {
    // Kullanıcı hem et hem tavuk/hindi sevebilir; bunlar kısıt değil tercih.
    var update = toggleDietaryTag(const ['meat_ok'], 'poultry_ok');
    expect(update.selected, containsAll(<String>['meat_ok', 'poultry_ok']));
    expect(update.removed, isEmpty);

    // Ters yön de aynı: kanatlı seçiliyken et eklemek onu düşürmez.
    update = toggleDietaryTag(const ['poultry_ok'], 'meat_ok');
    expect(update.selected, containsAll(<String>['meat_ok', 'poultry_ok']));
    expect(update.removed, isEmpty);

    // Üçü bir arada.
    update = toggleDietaryTag(const ['meat_ok', 'poultry_ok'], 'seafood_ok');
    expect(
      update.selected,
      containsAll(<String>['meat_ok', 'poultry_ok', 'seafood_ok']),
    );
    expect(update.removed, isEmpty);
  });

  test('vegan seçimi kanatlı tercihini de kaldırır', () {
    final update = toggleDietaryTag(const ['poultry_ok'], 'vegan');

    expect(update.selected, contains('vegan'));
    expect(update.selected, isNot(contains('poultry_ok')));
    expect(update.removed, contains('poultry_ok'));
  });

  test('kayıtlı chicken_only etiketi poultry_ok olarak okunur', () {
    expect(
      normalizeDietaryTags(const ['chicken_only', 'no_pork']),
      containsAll(<String>['poultry_ok', 'no_pork']),
    );
    expect(
      normalizeDietaryTags(const ['chicken_only']),
      isNot(contains('chicken_only')),
    );
    // Hem eski hem yeni kimlik varsa tek etikete iner.
    expect(
      normalizeDietaryTags(const ['chicken_only', 'poultry_ok']).length,
      1,
    );
  });

  test('kayıtlı plan JSON turunda chicken_only göç eder', () {
    final trip = TripPreferences.fromJson(const {
      'dietaryTags': ['chicken_only', 'meat_ok'],
    });
    // Göç ettikten sonra ikisi bir arada durabilir.
    expect(trip.dietaryTags, containsAll(<String>['poultry_ok', 'meat_ok']));
    expect(trip.dietaryTags, isNot(contains('chicken_only')));

    // Destinasyon bazlı yemek tercihleri de aynı göçü görür.
    final perDest = DestinationFoodPrefs.fromJson(const {
      'destinationId': 'd1',
      'dietaryTags': ['chicken_only'],
    });
    expect(perDest.dietaryTags, const ['poultry_ok']);
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
