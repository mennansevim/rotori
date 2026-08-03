import type { Trip } from '../types.js';

/** Japonya 14 günlük tam plan şablonu — uygulama tek bu pakete odaklı. */
export interface TripTemplateMeta {
  id: 'japan-14d';
  name: string;
  description: string;
  emoji: string;
}

export const TRIP_TEMPLATES: TripTemplateMeta[] = [
  {
    id: 'japan-14d',
    name: 'Japonya 14 günlük',
    description:
      'Tokyo + Kyoto + Nara + Osaka rotası, 13 günlük dakika dakika plan; Skytree, teamLab, Disney, USJ, Fushimi Inari, Dotonbori. Tarihler, otel ve biletler boş — sen doldur.',
    emoji: '🇯🇵',
  },
];

export function getTemplateMeta(id: string): TripTemplateMeta | undefined {
  return TRIP_TEMPLATES.find((t) => t.id === id);
}

/** Şablon yüklenirken mevcut trip ile birleştir */
export function applyTemplatePatch(base: Trip, patch: Partial<Trip>): Trip {
  return {
    ...base,
    ...patch,
    id: patch.id ?? base.id,
    slug: patch.slug ?? base.slug,
    title: patch.title ?? base.title,
    subtitle: patch.subtitle ?? base.subtitle,
    timezone: patch.timezone ?? base.timezone,
    tripStart: patch.tripStart ?? base.tripStart,
    tripEnd: patch.tripEnd ?? base.tripEnd,
    flights: patch.flights ?? base.flights,
    hotels: patch.hotels ?? base.hotels,
    tickets: patch.tickets ?? base.tickets,
    preferences: { ...base.preferences, ...patch.preferences },
    days: patch.days ?? base.days,
    deadlines: patch.deadlines ?? base.deadlines,
    guide: patch.guide ?? base.guide,
  };
}
