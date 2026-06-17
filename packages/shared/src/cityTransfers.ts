import type { DayPlan, TimelineItem, TripDestination } from './types.js';
import { newItemId } from './tripFactory.js';
import { getDestinationForDate } from './destinations/tripDestinations.js';

export interface CityTransfer {
  emoji: string;
  /** UI başlığı (ör. "Shinkansen Nozomi") */
  mode: string;
  /** Yaklaşık süre (ör. "2s 30dk") */
  duration: string;
  /** Tek yön yaklaşık ücret (ör. "~14,000 ¥") */
  fare: string;
  /** Plan içinde gösterilecek kısa ipucu */
  tip?: string;
}

const TRANSFERS: Record<string, CityTransfer> = {
  'tokyo|osaka': {
    emoji: '🚄',
    mode: 'Shinkansen Nozomi',
    duration: '2s 30dk',
    fare: '~14,720 ¥',
    tip: 'IC kart yerine gişe/Smart-EX. JR Pass kullanılmaz Nozomi için.',
  },
  'tokyo|kyoto': {
    emoji: '🚄',
    mode: 'Shinkansen Nozomi',
    duration: '2s 15dk',
    fare: '~14,170 ¥',
    tip: 'Sabah erken Nozomi sefer aralıkları sık, oturma kolaylığı için ayırtılabilir.',
  },
  'tokyo|hakone': {
    emoji: '🚆',
    mode: 'Odakyu Romance Car',
    duration: '1s 30dk',
    fare: '~2,470 ¥',
    tip: 'Hakone Free Pass al, gün boyu dağ ulaşımı dahil.',
  },
  'tokyo|nikko': {
    emoji: '🚆',
    mode: 'Tobu Limited Express Spacia',
    duration: '2s',
    fare: '~2,800 ¥',
  },
  'tokyo|nagoya': {
    emoji: '🚄',
    mode: 'Shinkansen Nozomi',
    duration: '1s 40dk',
    fare: '~11,300 ¥',
  },
  'osaka|kyoto': {
    emoji: '🚆',
    mode: 'JR Special Rapid',
    duration: '30dk',
    fare: '~580 ¥',
    tip: 'IC kart (Suica/Icoca) ile bin, ek bilet gerekmez.',
  },
  'osaka|nara': {
    emoji: '🚆',
    mode: 'Kintetsu Limited Express',
    duration: '45dk',
    fare: '~1,140 ¥',
  },
  'osaka|hiroshima': {
    emoji: '🚄',
    mode: 'Shinkansen Sakura/Nozomi',
    duration: '1s 25dk',
    fare: '~10,500 ¥',
  },
  'kyoto|nara': {
    emoji: '🚆',
    mode: 'JR Nara Line',
    duration: '45dk',
    fare: '~720 ¥',
  },
  'kyoto|osaka': {
    emoji: '🚆',
    mode: 'JR Special Rapid',
    duration: '30dk',
    fare: '~580 ¥',
  },
  'nara|kyoto': {
    emoji: '🚆',
    mode: 'JR Nara Line',
    duration: '45dk',
    fare: '~720 ¥',
  },
  'tokyo|fuji': {
    emoji: '🚌',
    mode: 'Highway Bus Shinjuku → Kawaguchiko',
    duration: '2s 15dk',
    fare: '~2,200 ¥',
  },
};

function normCity(city: string): string {
  return city
    .toLowerCase()
    .replace(/\s+\(.*?\)$/, '')
    .replace(/[-_\s]+/g, '')
    .trim();
}

/** İki şehir için bilinen transferi döndür (her iki yön de kabul edilir). */
export function lookupTransfer(from: string, to: string): CityTransfer | undefined {
  const a = normCity(from);
  const b = normCity(to);
  return TRANSFERS[`${a}|${b}`] ?? TRANSFERS[`${b}|${a}`];
}

/** Bir gün için "ana şehir" — önce öğelerdeki cityId, sonra destinasyon. */
function dayDominantCity(
  day: DayPlan,
  destinations: TripDestination[],
): string | undefined {
  for (const item of day.items) {
    if (item.cityId) return item.cityId;
  }
  return getDestinationForDate(destinations, day.date)?.city;
}

export interface CityTransitionSuggestion {
  fromDayNumber: number;
  toDayNumber: number;
  fromCity: string;
  toCity: string;
  transfer: CityTransfer;
}

/** Plan günleri içinde ardışık şehir geçişlerini ve önerilen transfer biçimini bul. */
export function detectCityTransitions(
  days: DayPlan[],
  destinations: TripDestination[],
): CityTransitionSuggestion[] {
  const out: CityTransitionSuggestion[] = [];
  const sorted = [...days].sort((a, b) => a.dayNumber - b.dayNumber);
  let prevCity: string | undefined;
  let prevDay: number | undefined;
  for (const day of sorted) {
    const city = dayDominantCity(day, destinations);
    if (city && prevCity && normCity(city) !== normCity(prevCity)) {
      const transfer = lookupTransfer(prevCity, city);
      if (transfer) {
        out.push({
          fromDayNumber: prevDay!,
          toDayNumber: day.dayNumber,
          fromCity: prevCity,
          toCity: city,
          transfer,
        });
      }
    }
    if (city) {
      prevCity = city;
      prevDay = day.dayNumber;
    }
  }
  return out;
}

/** Verilen güne, başına şehir-arası transfer öğesi ekle. */
export function insertCityTransfer(
  days: DayPlan[],
  dayNumber: number,
  suggestion: CityTransitionSuggestion,
): DayPlan[] {
  return days.map((d) => {
    if (d.dayNumber !== dayNumber) return d;
    const t = suggestion.transfer;
    const item: TimelineItem = {
      id: newItemId(dayNumber),
      title: `${t.emoji} ${suggestion.fromCity} → ${suggestion.toCity} • ${t.mode}`,
      description: `${t.duration} · ${t.fare}`,
      tips: t.tip,
      kind: 'transport',
      time: '08:30',
      scheduledTime: '08:30',
      cityId: suggestion.toCity,
    };
    return { ...d, items: [item, ...d.items] };
  });
}

/** Aynı transferin bu güne zaten eklendiğini kontrol et. */
export function hasExistingTransferTo(day: DayPlan, toCity: string): boolean {
  const norm = normCity(toCity);
  return day.items.some(
    (it) =>
      it.kind === 'transport' &&
      it.title.toLowerCase().includes('→') &&
      it.title.toLowerCase().includes(norm),
  );
}
