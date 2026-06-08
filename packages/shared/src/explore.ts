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

/** Ülke profilinden önerilen yemekler (cuisines + dishRecommendations). */
export function recommendedFoods(countryCode: string): FoodRecommendation[] {
  const profile = getDestinationProfile(countryCode);
  if (!profile) return [];
  const out: FoodRecommendation[] = [];
  const seen = new Set<string>();
  for (const c of profile.cuisines) {
    if (!seen.has(c.label)) {
      seen.add(c.label);
      out.push({ label: c.label, emoji: c.emoji });
    }
  }
  for (const dish of profile.dishRecommendations) {
    if (!seen.has(dish)) {
      seen.add(dish);
      out.push({ label: dish });
    }
  }
  return out;
}

export function ratingStars(rating: number): string {
  const full = Math.floor(rating);
  const half = rating - full >= 0.5;
  return '★'.repeat(full) + (half ? '½' : '');
}
