import type { PlaceSuggestion, DayTemplate } from '../japanSuggestions.js';

export interface CuisineChip {
  id: string;
  label: string;
  emoji: string;
}

export interface DestinationProfile {
  code: string;
  name: string;
  flag: string;
  defaultCurrency: string;
  timezone: string;
  cuisines: CuisineChip[];
  dishRecommendations: string[];
  dietaryOptionIds?: string[];
  popularPlaces: PlaceSuggestion[];
  dayTemplates: DayTemplate[];
}
