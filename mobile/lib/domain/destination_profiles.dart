// TypeScript packages/shared/src/destinations/profiles.ts +
// destinations/tripDestinations.ts'in getDestinationForDate kısmının Dart
// karşılığı. Ülke profilleri (mutfak, popüler mekan, gün şablonları).

import 'japan_suggestions.dart';
import 'types.dart';

class CuisineChip {
  const CuisineChip({required this.id, required this.label, required this.emoji});
  final String id;
  final String label;
  final String emoji;
}

class DestinationProfile {
  const DestinationProfile({
    required this.code,
    required this.name,
    required this.flag,
    required this.defaultCurrency,
    required this.timezone,
    required this.cuisines,
    required this.dishRecommendations,
    this.dietaryOptionIds,
    required this.popularPlaces,
    required this.dayTemplates,
  });

  final String code;
  final String name;
  final String flag;
  final String defaultCurrency;
  final String timezone;
  final List<CuisineChip> cuisines;
  final List<String> dishRecommendations;
  final List<String>? dietaryOptionIds;
  final List<PlaceSuggestion> popularPlaces;
  final List<DayTemplate> dayTemplates;
}

const Map<String, DestinationProfile> kDestinationProfiles = {
  'JP': DestinationProfile(
    code: 'JP',
    name: 'Japonya',
    flag: '🇯🇵',
    defaultCurrency: 'JPY',
    timezone: 'Asia/Tokyo',
    cuisines: [
      CuisineChip(id: 'ramen', label: 'Ramen', emoji: '🍜'),
      CuisineChip(id: 'sushi', label: 'Sushi / sashimi', emoji: '🍣'),
      CuisineChip(id: 'izakaya', label: 'Izakaya', emoji: '🍶'),
      CuisineChip(id: 'matcha', label: 'Matcha & tatlı', emoji: '🍵'),
      CuisineChip(id: 'yakiniku', label: 'Yakiniku', emoji: '🥩'),
      CuisineChip(id: 'street', label: 'Konbini / sokak', emoji: '🏪'),
    ],
    dishRecommendations: [
      'Tonkotsu veya shoyu ramen',
      'Nigiri sushi & omakase',
      'Okonomiyaki (Osaka)',
      'Takoyaki',
      'Wagyu yakiniku',
      'Onigiri & konbini kahvaltısı',
      'Matcha latte & mochi',
      'Udon / soba',
      'Yakitori',
      'Kaiseki (özel gün)',
    ],
    dietaryOptionIds: ['no_pork', 'seafood_ok', 'meat_ok'],
    popularPlaces: kJapanPopular,
    dayTemplates: kJapanDayTemplates,
  ),
};

DestinationProfile? getDestinationProfile(String code) =>
    kDestinationProfiles[code];

List<DestinationProfile> listDestinationProfiles() =>
    kDestinationProfiles.values.toList();

/// Verilen ISO tarihe (YYYY-MM-DD) denk gelen destinasyonu bul.
/// (TS: destinations/tripDestinations.ts → getDestinationForDate)
TripDestination? getDestinationForDate(
  List<TripDestination> destinations,
  String isoDate,
) {
  final sorted = [...destinations]..sort((a, b) => a.order.compareTo(b.order));
  for (final d in sorted) {
    if (isoDate.compareTo(d.arrivalDate) >= 0 &&
        isoDate.compareTo(d.departureDate) <= 0) {
      return d;
    }
  }
  return null;
}
