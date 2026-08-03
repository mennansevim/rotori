// TypeScript packages/shared/src/explore.ts'in Dart karşılığı.
// Keşif ekranı puanlama/etiket yardımcıları.

import 'destination_profiles.dart';
import 'japan_suggestions.dart';

/// id'den türeyen kararlı puan (4.2–4.9).
/// JS'teki `(h * 31 + code) | 0` 32-bit signed taşma davranışı birebir korunur.
double placeRating(PlaceSuggestion place) {
  if (place.rating != null) return place.rating!;
  var h = 0;
  for (final code in place.id.codeUnits) {
    h = (h * 31 + code) & 0xFFFFFFFF;
  }
  // 32-bit signed'a çevir (JS `| 0`).
  if (h >= 0x80000000) h -= 0x100000000;
  final frac = (h.abs() % 8) / 10; // 0.0–0.7
  return ((4.2 + frac) * 10).roundToDouble() / 10;
}

/// Çocuk dostu: açık alan tanımlı değilse kategoriden türet.
bool isKidFriendly(PlaceSuggestion place) {
  if (place.kidFriendly != null) return place.kidFriendly!;
  return place.category == 'fun' || place.category == 'nature';
}

/// Google Haritalar yorum/arama linki (API key gerekmez).
String googleReviewsUrl(String query) =>
    'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(query)}';

class FoodRecommendation {
  const FoodRecommendation({required this.label, this.emoji});
  final String label;
  final String? emoji;
}

/// Anahtar kelimeye göre yemek emojisi seç. Eşleşme yoksa default 🍽️.
String _emojiForDish(String name) {
  final n = name.toLowerCase();
  if (n.contains('ramen')) return '🍜';
  if (n.contains('udon') || n.contains('soba')) return '🍲';
  if (n.contains('onigiri')) return '🍙';
  if (n.contains('sushi') ||
      n.contains('sashimi') ||
      n.contains('nigiri') ||
      n.contains('omakase')) {
    return '🍣';
  }
  if (n.contains('tempura')) return '🍤';
  if (n.contains('takoyaki')) return '🐙';
  if (n.contains('okonomiyaki')) return '🥞';
  if (n.contains('yakitori')) return '🍢';
  if (n.contains('yakiniku') || n.contains('wagyu') || n.contains('beef')) {
    return '🥩';
  }
  if (n.contains('izakaya') || n.contains('sake') || n.contains('shochu')) {
    return '🍶';
  }
  if (n.contains('matcha') || n.contains('mochi') || n.contains('wagashi')) {
    return '🍵';
  }
  if (n.contains('curry')) return '🍛';
  if (n.contains('katsu')) return '🍱';
  if (n.contains('tonkatsu')) return '🍖';
  if (n.contains('kaiseki') || n.contains('teishoku')) return '🍱';
  if (n.contains('konbini') || n.contains('sokak') || n.contains('street')) {
    return '🏪';
  }
  if (n.contains('tonkotsu') || n.contains('shoyu') || n.contains('miso')) {
    return '🍜';
  }
  if (n.contains('dim sum') || n.contains('dumpling') || n.contains('gyoza')) {
    return '🥟';
  }
  if (n.contains('tatlı') || n.contains('dessert') || n.contains('crepe')) {
    return '🍰';
  }
  if (n.contains('kahve') || n.contains('coffee') || n.contains('latte')) {
    return '☕';
  }
  return '🍽️';
}

/// Ülke profilinden önerilen yemekler (cuisines + dishRecommendations).
List<FoodRecommendation> recommendedFoods(String countryCode) {
  final profile = getDestinationProfile(countryCode);
  if (profile == null) return [];
  final out = <FoodRecommendation>[];
  final seen = <String>{};
  for (final c in profile.cuisines) {
    if (seen.add(c.label)) {
      out.add(FoodRecommendation(label: c.label, emoji: c.emoji));
    }
  }
  for (final dish in profile.dishRecommendations) {
    if (seen.add(dish)) {
      out.add(FoodRecommendation(label: dish, emoji: _emojiForDish(dish)));
    }
  }
  return out;
}

String ratingStars(double rating) {
  final full = rating.floor();
  final half = rating - full >= 0.5;
  return '★' * full + (half ? '½' : '');
}
