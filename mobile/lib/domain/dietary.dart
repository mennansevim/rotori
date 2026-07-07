// TypeScript packages/shared/src/dietary.ts'in Dart karşılığı +
// tripFactory.ts'ten dietaryTagsFromSensitivities (beslenme etiketi türetimi).

import 'types.dart';

/// Ülkeye göre genişletilebilir beslenme etiketleri.
class DietaryOption {
  const DietaryOption({
    required this.id,
    required this.label,
    required this.emoji,
    required this.description,
    this.countries,
  });

  final String id;
  final String label;
  final String emoji;
  final String description;

  /// boş/null = evrensel
  final List<String>? countries;
}

const List<DietaryOption> kDietaryOptions = [
  DietaryOption(
    id: 'halal',
    label: 'Helal',
    emoji: '🕌',
    description: 'Helal sertifikalı veya domuzsuz seçenekler',
    countries: ['JP', 'TR', 'MY'],
  ),
  DietaryOption(
    id: 'no_pork',
    label: 'Domuz yok',
    emoji: '🐷',
    description: 'Domuz eti ve domuz yağı içermesin',
    countries: ['JP', 'TR'],
  ),
  DietaryOption(
    id: 'vegetarian',
    label: 'Vejetaryen',
    emoji: '🥬',
    description: 'Et ve balık yok, yumurta/süt olabilir',
  ),
  DietaryOption(
    id: 'vegan',
    label: 'Vegan',
    emoji: '🌱',
    description: 'Hayvansal ürün yok',
  ),
  DietaryOption(
    id: 'low_fat',
    label: 'Yağsız / hafif',
    emoji: '💧',
    description: 'Kızartma ve ağır soslardan kaçın',
  ),
  DietaryOption(
    id: 'no_alcohol',
    label: 'Alkolsüz',
    emoji: '🚫',
    description: 'Yemeklerde alkol kullanılmasın',
  ),
  DietaryOption(
    id: 'bakery_ok',
    label: 'Hamur işi OK',
    emoji: '🥐',
    description: 'Ekmek, noodle, unlu atıştırmalıklar uygun',
  ),
  DietaryOption(
    id: 'meat_ok',
    label: 'Et sever',
    emoji: '🥩',
    description: 'Wagyu, yakiniku, et ağırlıklı menüler',
    countries: ['JP'],
  ),
  DietaryOption(
    id: 'chicken_only',
    label: 'Tavuk / hindi',
    emoji: '🍗',
    description: 'Kırmızı et yerine tavuk tercih',
  ),
  DietaryOption(
    id: 'seafood_ok',
    label: 'Deniz ürünü',
    emoji: '🐟',
    description: 'Sushi, sashimi, deniz ürünleri uygun',
    countries: ['JP'],
  ),
  DietaryOption(
    id: 'gluten_free',
    label: 'Glutensiz',
    emoji: '🌾',
    description: 'Buğday / gluten hassasiyeti',
  ),
  DietaryOption(
    id: 'spicy_ok',
    label: 'Acı sever',
    emoji: '🌶️',
    description: 'Acı ve baharatlı yemekler uygun',
    countries: ['KR', 'TH', 'MX'],
  ),
  DietaryOption(
    id: 'spicy_avoid',
    label: 'Acı istemiyorum',
    emoji: '🚫🌶️',
    description: 'Acı sos ve gochujang azaltılsın',
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
