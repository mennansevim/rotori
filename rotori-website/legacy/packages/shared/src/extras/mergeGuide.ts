import { getGuideDefaultsForCountry } from './countryDefaults.js';
import type { TripGuide, TipCard, ShoppingItem, FoodSpot, CompassBlock } from './types.js';
import type { Trip } from '../types.js';

function mergeList<T extends { id: string; source?: string }>(
  userItems: T[],
  suggestions: T[],
): T[] {
  const userIds = new Set(userItems.map((i) => i.id));
  const merged = [...userItems];
  for (const s of suggestions) {
    if (!userIds.has(s.id)) merged.push(s);
  }
  return merged;
}

export function buildSuggestedGuide(destinations: { countryCode: string }[]): TripGuide {
  const tips: TipCard[] = [];
  const shopping: ShoppingItem[] = [];
  const food: FoodSpot[] = [];
  const compass: CompassBlock[] = [];
  const seen = new Set<string>();

  for (const d of destinations) {
    if (!d.countryCode || seen.has(d.countryCode)) continue;
    seen.add(d.countryCode);
    const def = getGuideDefaultsForCountry(d.countryCode);
    if (!def) continue;
    tips.push(...def.practicalTips);
    shopping.push(...def.shopping);
    food.push(...def.foodSpots);
    compass.push(...def.compass);
  }

  return {
    useSuggestions: true,
    practicalTips: tips,
    shopping,
    foodSpots: food,
    compass,
  };
}

export function ensureTripGuide(trip: Trip): Trip {
  const userGuide = trip.guide ?? {
    useSuggestions: true,
    practicalTips: [],
    shopping: [],
    foodSpots: [],
    compass: [],
  };

  if (!userGuide.useSuggestions) return { ...trip, guide: userGuide };

  const suggested = buildSuggestedGuide(trip.preferences.destinations ?? []);

  return {
    ...trip,
    guide: {
      useSuggestions: true,
      practicalTips: mergeList(userGuide.practicalTips, suggested.practicalTips),
      shopping: mergeList(userGuide.shopping, suggested.shopping),
      foodSpots: mergeList(userGuide.foodSpots, suggested.foodSpots),
      compass: mergeList(userGuide.compass, suggested.compass),
    },
  };
}

/** Yayınlanan rehberde gösterilecek birleşik içerik */
export function getPublishedGuide(trip: Trip): TripGuide {
  return ensureTripGuide(trip).guide!;
}
