// TypeScript packages/shared/src/dietary.ts'in Dart karşılığı +
// tripFactory.ts'ten dietaryTagsFromSensitivities (beslenme etiketi türetimi).

import 'types.dart';

/// Ülkeye göre genişletilebilir beslenme etiketleri.
///
/// i18n: `label` ve `description` alanları L10n anahtarıdır (ör. 'diet.halal.label').
/// Bir DietaryOption gösterilirken çağrı yeri LanguageScope.of(context).s(opt.label)
/// ve .s(opt.description) ile çözmelidir. `id`/`emoji`/`countries` çeviri dışıdır.
class DietaryOption {
  const DietaryOption({
    required this.id,
    required this.label,
    required this.emoji,
    required this.description,
    this.countries,
  });

  final String id;

  /// L10n anahtarı.
  final String label;
  final String emoji;

  /// L10n anahtarı.
  final String description;

  /// boş/null = evrensel
  final List<String>? countries;
}

const List<DietaryOption> kDietaryOptions = [
  DietaryOption(
    id: 'halal',
    label: 'diet.halal.label',
    emoji: '🕌',
    description: 'diet.halal.desc',
    countries: ['JP', 'TR', 'MY'],
  ),
  DietaryOption(
    id: 'no_pork',
    label: 'diet.noPork.label',
    emoji: '🐷',
    description: 'diet.noPork.desc',
    countries: ['JP', 'TR'],
  ),
  DietaryOption(
    id: 'vegetarian',
    label: 'diet.vegetarian.label',
    emoji: '🥬',
    description: 'diet.vegetarian.desc',
  ),
  DietaryOption(
    id: 'vegan',
    label: 'diet.vegan.label',
    emoji: '🌱',
    description: 'diet.vegan.desc',
  ),
  DietaryOption(
    id: 'low_fat',
    label: 'diet.lowFat.label',
    emoji: '💧',
    description: 'diet.lowFat.desc',
  ),
  DietaryOption(
    id: 'no_alcohol',
    label: 'diet.noAlcohol.label',
    emoji: '🚫',
    description: 'diet.noAlcohol.desc',
  ),
  DietaryOption(
    id: 'bakery_ok',
    label: 'diet.bakeryOk.label',
    emoji: '🥐',
    description: 'diet.bakeryOk.desc',
  ),
  DietaryOption(
    id: 'meat_ok',
    label: 'diet.meatOk.label',
    emoji: '🥩',
    description: 'diet.meatOk.desc',
    countries: ['JP'],
  ),
  DietaryOption(
    id: 'poultry_ok',
    label: 'diet.poultryOk.label',
    emoji: '🍗',
    description: 'diet.poultryOk.desc',
  ),
  DietaryOption(
    id: 'seafood_ok',
    label: 'diet.seafoodOk.label',
    emoji: '🐟',
    description: 'diet.seafoodOk.desc',
    countries: ['JP'],
  ),
  DietaryOption(
    id: 'gluten_free',
    label: 'diet.glutenFree.label',
    emoji: '🌾',
    description: 'diet.glutenFree.desc',
  ),
  DietaryOption(
    id: 'spicy_ok',
    label: 'diet.spicyOk.label',
    emoji: '🌶️',
    description: 'diet.spicyOk.desc',
    countries: ['KR', 'TH', 'MX'],
  ),
  DietaryOption(
    id: 'spicy_avoid',
    label: 'diet.spicyAvoid.label',
    emoji: '🚫🌶️',
    description: 'diet.spicyAvoid.desc',
    countries: ['KR'],
  ),
];

List<DietaryOption> dietaryForCountry(String countryCode) {
  if (countryCode.isEmpty) {
    return kDietaryOptions
        .where((o) => o.countries == null || o.countries!.isEmpty)
        .toList();
  }
  return kDietaryOptions
      .where((o) =>
          o.countries == null ||
          o.countries!.isEmpty ||
          o.countries!.contains(countryCode))
      .toList();
}

/// Çoklu ülke rotası: her destinasyonun kurallarını birleştirir.
List<DietaryOption> dietaryForCountries(List<String> countryCodes) {
  final codes = countryCodes.where((c) => c.isNotEmpty).toList();
  if (codes.isEmpty) return dietaryForCountry('');
  final seen = <String>{};
  final out = <DietaryOption>[];
  for (final code in codes) {
    for (final opt in dietaryForCountry(code)) {
      if (seen.add(opt.id)) out.add(opt);
    }
  }
  return out;
}

/// foodSensitivities tag listesinden dietaryTags türetir.
/// (TS: tripFactory.ts → dietaryTagsFromSensitivities)
List<String> dietaryTagsFromSensitivities(
  List<FoodSensitivity>? sensitivities,
) {
  if (sensitivities == null || sensitivities.isEmpty) return [];
  final out = <String>{};
  for (final s in sensitivities) {
    if (s == FoodSensitivity.noPork || s == FoodSensitivity.noPorkDerivatives) {
      out.add('no_pork');
    }
    if (s == FoodSensitivity.noSeafood) out.add('no_seafood');
    if (s == FoodSensitivity.halalOnly) out.add('halal');
    if (s == FoodSensitivity.vegetarian) out.add('vegetarian');
    if (s == FoodSensitivity.kidFriendly) out.add('kid_friendly');
    if (s == FoodSensitivity.chickenFocus) out.add('chicken_focus');
    if (s == FoodSensitivity.turkishPalate) out.add('turkish_palate');
    if (s == FoodSensitivity.noFattyMeat) out.add('no_fatty_meat');
  }
  return out.toList();
}

/// Hayvansal ürün TERCİHLERİ (kısıt değil). Üçü birlikte seçilebilir; yalnızca
/// vegan/vejetaryen ile çelişirler.
const Set<String> kAnimalProductChoices = {
  'meat_ok',
  'seafood_ok',
  'poultry_ok',
};

/// Kaydedilmiş beslenme etiketlerini güncel kimliklere taşır.
///
/// `chicken_only` → `poultry_ok`: eski kimlik "sadece tavuk" (kırmızı eti
/// dışla) anlamı taşıyordu ama bu anlam hiçbir yerde uygulanmıyordu ve
/// arayüzde "Tavuk / hindi" olarak görünüyordu. Kullanıcının kastettiği
/// "kanatlı da severim"di; kimlik de artık bunu söylüyor.
List<String> normalizeDietaryTags(Iterable<String> tags) {
  final out = <String>{};
  for (final tag in tags) {
    out.add(tag == 'chicken_only' ? 'poultry_ok' : tag);
  }
  return out.toList(growable: false);
}

class DietarySelectionUpdate {
  const DietarySelectionUpdate({
    required this.selected,
    this.removed = const [],
  });

  final List<String> selected;
  final List<String> removed;
}

/// Beslenme seçimlerinde birbirini anlamsızlaştıran etiketleri tek domain
/// kuralında çözer. UI yalnız bu sonucu uygular; farklı ekranlar ayrı davranmaz.
DietarySelectionUpdate toggleDietaryTag(
  Iterable<String> current,
  String toggled,
) {
  final selected = current.toSet();
  if (selected.remove(toggled)) {
    return DietarySelectionUpdate(selected: selected.toList(growable: false));
  }

  final conflicts = <String>{};
  if (toggled == 'vegan') {
    conflicts.addAll({...kAnimalProductChoices, 'vegetarian'});
  } else if (toggled == 'vegetarian') {
    conflicts.addAll({...kAnimalProductChoices, 'vegan'});
  } else if (kAnimalProductChoices.contains(toggled)) {
    // Et / kanatlı / deniz ürünü BİRBİRİNİ DIŞLAMAZ.
    //
    // **Why:** Eskiden `meat_ok` ile `chicken_only` çelişik sayılıyordu, çünkü
    // etiketin adı "sadece tavuk" idi. Ama arayüzde "Tavuk / hindi" yazıyor ve
    // kullanıcı ikisini de sevebiliyor. Dahası bu dışlamanın hiçbir karşılığı
    // yoktu: yemek değerlendirmesi (`_conflicts`, japanese_dishes.dart) bu üç
    // etiketi hiç okumuyor — üçü de yalnızca POZİTİF tercih. Tek gerçek
    // çelişki vegan/vejetaryen ile olan.
    conflicts.addAll({'vegan', 'vegetarian'});
  }
  final removed = selected.where(conflicts.contains).toList(growable: false);
  selected.removeAll(conflicts);
  selected.add(toggled);
  return DietarySelectionUpdate(
    selected: selected.toList(growable: false),
    removed: removed,
  );
}
