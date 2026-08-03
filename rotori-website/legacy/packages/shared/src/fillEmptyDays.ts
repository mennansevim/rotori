import type { DayPlan, TimelineItem, TripDestination } from './types.js';
import { newItemId } from './tripFactory.js';
import { getDestinationForDate } from './destinations/tripDestinations.js';
import { getDestinationProfile } from './destinations/profiles.js';

/** Tek bir saat dilimine göre yer önerisi şablonu. */
interface SlotTemplate {
  time: string;
  kind: TimelineItem['kind'];
  /** kind=meal ise yemek tipi (Türkçe etiket). */
  mealTag?: string;
}

const FILL_SLOTS: SlotTemplate[] = [
  { time: '09:00', kind: 'activity' },
  { time: '11:00', kind: 'activity' },
  { time: '13:00', kind: 'meal', mealTag: 'Öğle yemeği' },
  { time: '14:30', kind: 'activity' },
  { time: '16:30', kind: 'activity' },
  { time: '19:00', kind: 'meal', mealTag: 'Akşam yemeği' },
];

const MEAL_PRESETS = [
  { emoji: '🍜', name: 'Ramen molası', tip: 'Tonkotsu veya shoyu — Ichiran, Ippudo, Afuri gibi zincirlerden biri.' },
  { emoji: '🍣', name: 'Conveyor sushi', tip: 'Sushiro / Kura Sushi — uygun fiyatlı, çocuk dostu.' },
  { emoji: '🥩', name: 'Yakitori izakaya', tip: 'Tori-kizoku zinciri ya da Omoide Yokocho ara sokakları.' },
  { emoji: '🍱', name: 'Konbini bento', tip: 'Family Mart / Lawson — taze onigiri & bento, hızlı seçenek.' },
  { emoji: '🍛', name: 'Japon curry', tip: 'CoCo Ichibanya — acılığı + topping seçilebilir.' },
];

/** Şehir adından (örn "Tokyo (Haneda)") sade şehir döndür. */
function cleanCity(city: string): string {
  return city.replace(/\s*\(.*\)\s*$/, '').trim();
}

/** Bir gün için TimelineItem üret — şablon + popularPlace eşle. */
function buildItem(
  dayNumber: number,
  slot: SlotTemplate,
  city: string,
  place: { name: string; emoji?: string; typicalSteps?: number } | undefined,
  preset: { emoji: string; name: string; tip: string },
): TimelineItem {
  const id = `${newItemId(dayNumber)}-fill-${slot.time.replace(':', '')}`;
  if (slot.kind === 'meal') {
    return {
      id,
      title: `${preset.emoji} ${slot.mealTag} — ${preset.name}`,
      description: 'Hızlı, yerel bir mola.',
      tips: preset.tip,
      kind: 'meal',
      time: slot.time,
      scheduledTime: slot.time,
      durationMin: 45,
      cityId: city,
    };
  }
  const name = place?.name ?? 'Mahalle yürüyüşü';
  const emoji = place?.emoji ?? '🚶';
  return {
    id,
    title: `${emoji} ${name}`,
    description: place ? `${cleanCity(city)} bölgesinde popüler durak.` : 'Bölgede serbest keşif.',
    kind: 'activity',
    time: slot.time,
    scheduledTime: slot.time,
    durationMin: 90,
    mapUrl: place
      ? `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(
          `${place.name} ${cleanCity(city)}`,
        )}`
      : undefined,
    cityId: city,
  };
}

/**
 * AI cevabından sonra hâlâ items.length === 0 olan günleri doldur.
 * Destinasyon profilinin popularPlaces listesinden rotasyonla seçer.
 */
export function fillEmptyDays(
  days: DayPlan[],
  destinations: TripDestination[],
): DayPlan[] {
  // Şehir bazında popularPlace havuzu + rotasyon indeksleri
  const cityPlaces = new Map<string, { name: string; emoji?: string; typicalSteps?: number }[]>();
  const cityCursors = new Map<string, number>();

  for (const dest of destinations) {
    const profile = getDestinationProfile(dest.countryCode);
    if (!profile) continue;
    const key = cleanCity(dest.city || dest.countryName);
    if (cityPlaces.has(key)) continue;
    cityPlaces.set(
      key,
      profile.popularPlaces.map((p) => ({
        name: p.name,
        emoji: p.emoji,
        typicalSteps: p.typicalSteps,
      })),
    );
    cityCursors.set(key, 0);
  }

  let mealCursor = 0;

  const MIN_ITEMS_PER_DAY = 4;

  return days.map((day) => {
    if (day.items.length >= MIN_ITEMS_PER_DAY) return day;
    const dest = getDestinationForDate(destinations, day.date);
    const cityKey = cleanCity(dest?.city || dest?.countryName || '');
    const pool = cityPlaces.get(cityKey) ?? [];
    let cursor = cityCursors.get(cityKey) ?? 0;

    // Hangi saat dilimlerinde zaten item var?
    const usedTimes = new Set(day.items.map((it) => it.time).filter(Boolean) as string[]);
    const usedKindCounts = day.items.reduce(
      (acc, it) => ({ ...acc, [it.kind ?? 'activity']: (acc[it.kind ?? 'activity'] ?? 0) + 1 }),
      {} as Record<string, number>,
    );

    const supplements: TimelineItem[] = [];
    let stepsSum = day.stepsEstimate ?? 0;
    const tags = new Set<string>(day.tags ?? []);

    for (const slot of FILL_SLOTS) {
      if (usedTimes.has(slot.time)) continue;
      // Yemek slot'u: gün içinde aynı kind 2'den az ise ekle
      if (slot.kind === 'meal' && (usedKindCounts.meal ?? 0) >= 2) continue;
      // Activity slot'u: havuz yoksa atla
      let place: { name: string; emoji?: string; typicalSteps?: number } | undefined;
      if (slot.kind === 'activity') {
        if (pool.length === 0) continue;
        // Aynı yer zaten varsa cursor'ı ilerlet
        let attempts = 0;
        while (attempts < pool.length) {
          const candidate = pool[cursor % pool.length];
          const inDay = day.items.some((it) => it.title.includes(candidate.name));
          const inSupp = supplements.some((it) => it.title.includes(candidate.name));
          if (!inDay && !inSupp) {
            place = candidate;
            break;
          }
          cursor++;
          attempts++;
        }
        if (!place) continue;
        cursor++;
        stepsSum += place.typicalSteps ?? 3000;
        tags.add(place.name);
      }
      const preset = MEAL_PRESETS[mealCursor % MEAL_PRESETS.length];
      if (slot.kind === 'meal') mealCursor++;
      supplements.push(buildItem(day.dayNumber, slot, cityKey, place, preset));

      // Yeterince eklediysek dur
      if (day.items.length + supplements.length >= MIN_ITEMS_PER_DAY + 1) break;
    }

    cityCursors.set(cityKey, cursor);

    if (supplements.length === 0) return day;

    const merged = [...day.items, ...supplements].sort((a, b) =>
      (a.time ?? '99:99').localeCompare(b.time ?? '99:99'),
    );

    const theme =
      day.theme && !day.theme.startsWith(`Gün `) && !day.theme.includes(' — Gün ')
        ? day.theme
        : `${cityKey} keşif günü`;

    return {
      ...day,
      theme,
      tags: [...tags].slice(0, 5),
      stepsEstimate: Math.min(22000, Math.max(day.stepsEstimate ?? 0, stepsSum)),
      items: merged,
    };
  });
}
