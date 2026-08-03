import type { PlaceSuggestion } from './japanSuggestions.js';
import { getDestinationProfile } from './destinations/profiles.js';

/** id'den türeyen kararlı puan (4.2–4.9). */
export function placeRating(place: PlaceSuggestion): number {
  if (place.rating != null) return place.rating;
  let h = 0;
  for (let i = 0; i < place.id.length; i++) h = (h * 31 + place.id.charCodeAt(i)) | 0;
  const frac = (Math.abs(h) % 8) / 10; // 0.0–0.7
  return Math.round((4.2 + frac) * 10) / 10;
}

/** Çocuk dostu: açık alan tanımlı değilse kategoriden türet. */
export function isKidFriendly(place: PlaceSuggestion): boolean {
  if (place.kidFriendly != null) return place.kidFriendly;
  return place.category === 'fun' || place.category === 'nature';
}

/** Google Haritalar yorum/arama linki (API key gerekmez). */
export function googleReviewsUrl(query: string): string {
  return `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(query)}`;
}

export interface FoodRecommendation {
  label: string;
  emoji?: string;
}

/** Anahtar kelimeye göre yemek emojisi seç. Eşleşme yoksa default 🍽️. */
function emojiForDish(name: string): string {
  const n = name.toLowerCase();
  if (n.includes('ramen')) return '🍜';
  if (n.includes('udon') || n.includes('soba')) return '🍲';
  if (n.includes('onigiri')) return '🍙';
  if (n.includes('sushi') || n.includes('sashimi') || n.includes('nigiri') || n.includes('omakase'))
    return '🍣';
  if (n.includes('tempura')) return '🍤';
  if (n.includes('takoyaki')) return '🐙';
  if (n.includes('okonomiyaki')) return '🥞';
  if (n.includes('yakitori')) return '🍢';
  if (n.includes('yakiniku') || n.includes('wagyu') || n.includes('beef'))
    return '🥩';
  if (n.includes('izakaya') || n.includes('sake') || n.includes('shochu')) return '🍶';
  if (n.includes('matcha') || n.includes('mochi') || n.includes('wagashi')) return '🍵';
  if (n.includes('curry')) return '🍛';
  if (n.includes('katsu')) return '🍱';
  if (n.includes('tonkatsu')) return '🍖';
  if (n.includes('kaiseki') || n.includes('teishoku')) return '🍱';
  if (n.includes('konbini') || n.includes('sokak') || n.includes('street')) return '🏪';
  if (n.includes('tonkotsu') || n.includes('shoyu') || n.includes('miso')) return '🍜';
  if (n.includes('dim sum') || n.includes('dumpling') || n.includes('gyoza')) return '🥟';
  if (n.includes('tatlı') || n.includes('dessert') || n.includes('crepe')) return '🍰';
  if (n.includes('kahve') || n.includes('coffee') || n.includes('latte')) return '☕';
  return '🍽️';
}

/** Ülke profilinden önerilen yemekler (cuisines + dishRecommendations). */
export function recommendedFoods(countryCode: string): FoodRecommendation[] {
  const profile = getDestinationProfile(countryCode);
  if (!profile) return [];
  const out: FoodRecommendation[] = [];
  const seen = new Set<string>();
  for (const c of profile.cuisines) {
    if (!seen.has(c.label)) {
      seen.add(c.label);
      out.push({ label: c.label, emoji: c.emoji ?? emojiForDish(c.label) });
    }
  }
  for (const dish of profile.dishRecommendations) {
    if (!seen.has(dish)) {
      seen.add(dish);
      out.push({ label: dish, emoji: emojiForDish(dish) });
    }
  }
  return out;
}

export function ratingStars(rating: number): string {
  const full = Math.floor(rating);
  const half = rating - full >= 0.5;
  return '★'.repeat(full) + (half ? '½' : '');
}
