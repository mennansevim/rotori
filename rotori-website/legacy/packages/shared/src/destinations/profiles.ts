import { JAPAN_POPULAR, JAPAN_DAY_TEMPLATES } from '../japanSuggestions.js';
import type { DestinationProfile } from './types.js';

export const DESTINATION_PROFILES: Record<string, DestinationProfile> = {
  JP: {
    code: 'JP',
    name: 'Japonya',
    flag: '🇯🇵',
    defaultCurrency: 'JPY',
    timezone: 'Asia/Tokyo',
    cuisines: [
      { id: 'ramen', label: 'Ramen', emoji: '🍜' },
      { id: 'sushi', label: 'Sushi / sashimi', emoji: '🍣' },
      { id: 'izakaya', label: 'Izakaya', emoji: '🍶' },
      { id: 'matcha', label: 'Matcha & tatlı', emoji: '🍵' },
      { id: 'yakiniku', label: 'Yakiniku', emoji: '🥩' },
      { id: 'street', label: 'Konbini / sokak', emoji: '🏪' },
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
    popularPlaces: JAPAN_POPULAR,
    dayTemplates: JAPAN_DAY_TEMPLATES,
  },
};

export function getDestinationProfile(code: string): DestinationProfile | null {
  return DESTINATION_PROFILES[code] ?? null;
}

export function listDestinationProfiles(): DestinationProfile[] {
  return Object.values(DESTINATION_PROFILES);
}
