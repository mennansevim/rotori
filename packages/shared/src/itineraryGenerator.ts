import { getDestinationProfile } from './destinations/profiles.js';
import { getDestinationForDate } from './destinations/tripDestinations.js';
import { isKidFriendly } from './explore.js';
import type { DayTemplate, PlaceSuggestion } from './japanSuggestions.js';
import { newItemId } from './tripFactory.js';
import type { DayHighlight, DayPlan, InterestTag, TimelineItem, Trip } from './types.js';

/** Mekanın ilgi alanı puanı — her eşleşme +2. */
function interestScore(p: PlaceSuggestion, interests: InterestTag[]): number {
  if (!interests || interests.length === 0) return 0;
  const name = p.name.toLowerCase();
  const cat = p.category;
  let score = 0;
  const has = (tag: InterestTag) => interests.includes(tag);

  if (has('temples') && (cat === 'culture' || /temple|jingu|inari|todai|sensoji/.test(name))) score += 2;
  if (has('traditional') && cat === 'culture') score += 2;
  if (has('theme_parks') && (cat === 'fun' || /disney|usj|universal/.test(name))) score += 2;
  if (has('shopping') && cat === 'shopping') score += 2;
  if (has('food') && cat === 'food') score += 2;
  if (has('photography') && (cat === 'fun' || cat === 'nature' || /sky|crossing|tower|skytree/.test(name))) score += 2;
  if (has('anime') && /akihabara|anime|manga|ghibli|otaku/.test(name)) score += 2;
  if (has('pokemon') && /pokemon|pokémon/.test(name)) score += 2;
  if (has('tech') && /yodobashi|bic camera|akihabara/.test(name)) score += 2;
  if (has('kids') && isKidFriendly(p)) score += 2;
  return score;
}

const TIMES_RELAXED = ['10:00', '14:00', '18:00'];
const TIMES_MODERATE = ['09:00', '11:30', '14:00', '17:30'];
const TIMES_INTENSE = ['08:00', '10:00', '12:00', '14:30', '17:00', '19:00'];

function timesForPace(pace: string | undefined): string[] {
  if (pace === 'relaxed') return TIMES_RELAXED;
  if (pace === 'intense') return TIMES_INTENSE;
  return TIMES_MODERATE;
}

function activitiesPerDay(pace: string | undefined): number {
  if (pace === 'relaxed') return 2;
  if (pace === 'intense') return 5;
  return 3;
}

function placeById(places: PlaceSuggestion[], id: string): PlaceSuggestion | undefined {
  return places.find((p) => p.id === id);
}

function pickPlaces(
  pool: PlaceSuggestion[],
  count: number,
  used: Set<string>,
  kidMode: boolean,
  mustSee: string[],
  interests: InterestTag[],
  maxSteps: number,
): PlaceSuggestion[] {
  const mustLower = mustSee.map((m) => m.toLowerCase());
  const scored = pool
    .filter((p) => !used.has(p.id))
    .map((p) => {
      let score = 0;
      if (mustLower.some((m) => p.name.toLowerCase().includes(m) || m.includes(p.name.toLowerCase()))) {
        score += 100;
      }
      if (kidMode && isKidFriendly(p)) score += 20;
      if (kidMode && !isKidFriendly(p)) score -= 15;
      score += interestScore(p, interests);
      // Walking target: kullanıcının üst sınırını aşan yerleri yavaşça aşağı it.
      const steps = p.typicalSteps ?? 10000;
      if (steps > maxSteps) score -= Math.min(15, Math.floor((steps - maxSteps) / 1000));
      else if (steps < maxSteps) score += 3;
      return { p, score };
    })
    .sort((a, b) => b.score - a.score);

  const out: PlaceSuggestion[] = [];
  for (const { p } of scored) {
    if (out.length >= count) break;
    used.add(p.id);
    out.push(p);
  }
  return out;
}

function makeItem(dayNumber: number, time: string, place: PlaceSuggestion): TimelineItem {
  return {
    id: newItemId(dayNumber),
    time,
    scheduledTime: time,
    title: `${place.emoji} ${place.name}`,
    description: `${place.city} · ${place.category}`,
    tips:
      place.category === 'culture'
        ? 'Sabah erken gitmek kalabalığı azaltır.'
        : place.category === 'food'
          ? 'Öğle veya akşam için ideal.'
          : undefined,
    kind: 'activity',
  };
}

function mealItem(dayNumber: number, time: string, label: string): TimelineItem {
  return {
    id: newItemId(dayNumber),
    time,
    scheduledTime: time,
    title: `🍽️ ${label}`,
    kind: 'meal',
  };
}

function buildFromTemplate(
  day: DayPlan,
  template: DayTemplate,
  places: PlaceSuggestion[],
  pace: string | undefined,
): DayPlan {
  const times = timesForPace(pace);
  const items: TimelineItem[] = [];
  let stepSum = 0;

  template.places.forEach((pid, i) => {
    const place = placeById(places, pid);
    if (!place) return;
    const time = times[i] ?? times[times.length - 1];
    items.push(makeItem(day.dayNumber, time, place));
    stepSum += place.typicalSteps ?? 8000;
    if (i === 0 && times[1]) {
      items.push(mealItem(day.dayNumber, times[1], 'Öğle yemeği molası'));
    }
  });

  if (!items.length && template.id.includes('arrival')) {
    items.push({
      id: newItemId(day.dayNumber),
      time: '15:00',
      scheduledTime: '15:00',
      title: '🛬 Varış & check-in',
      description: 'Otele yerleş, jet lag için hafif tempo.',
      kind: 'activity',
    });
    items.push({
      id: newItemId(day.dayNumber),
      time: '18:00',
      scheduledTime: '18:00',
      title: '🏪 Çevre keşfi & konbini',
      description: 'Yakın çevrede kısa yürüyüş, akşam atıştırmalığı.',
      kind: 'meal',
    });
    stepSum = template.stepsEstimate;
  }

  const tags = template.places
    .map((id) => placeById(places, id)?.name)
    .filter(Boolean) as string[];

  const highlights: DayHighlight[] = [
    {
      title: template.label,
      body: `${template.emoji} ${template.theme} — tempo: ${pace === 'relaxed' ? 'Rahat' : pace === 'intense' ? 'Yoğun' : 'Dengeli'}`,
    },
  ];

  return {
    ...day,
    theme: `${template.emoji} ${template.theme}`,
    tags: tags.length ? tags : [template.label],
    stepsEstimate: template.stepsEstimate || stepSum || 10000,
    taxiRecommended: (template.stepsEstimate || stepSum) > 18000,
    items,
    highlights,
  };
}

function buildDepartureDay(day: DayPlan, destName: string, flag: string): DayPlan {
  return {
    ...day,
    theme: `${flag} Ayrılış & havaalanı`,
    tags: ['Ayrılış', destName],
    stepsEstimate: 6000,
    items: [
      {
        id: newItemId(day.dayNumber),
        time: '09:00',
        scheduledTime: '09:00',
        title: '🧳 Check-out & valiz',
        kind: 'activity',
      },
      {
        id: newItemId(day.dayNumber),
        time: '11:00',
        scheduledTime: '11:00',
        title: '🚕 Havaalanı transferi',
        description: 'Tren veya taksi — uçuş saatine göre erken çık.',
        kind: 'transport',
      },
      {
        id: newItemId(day.dayNumber),
        time: '14:00',
        scheduledTime: '14:00',
        title: '✈️ Dönüş uçuşu',
        kind: 'transport',
      },
    ],
    highlights: [{ title: 'Ayrılış günü', body: 'Havaalanına en az 2–3 saat önce varın.' }],
  };
}

function buildFromPlaces(
  day: DayPlan,
  pool: PlaceSuggestion[],
  pace: string | undefined,
  used: Set<string>,
  kidMode: boolean,
  mustSee: string[],
  interests: InterestTag[],
  maxSteps: number,
  destLabel: string,
  flag: string,
): DayPlan {
  const count = activitiesPerDay(pace);
  const picked = pickPlaces(pool, count, used, kidMode, mustSee, interests, maxSteps);
  const times = timesForPace(pace);
  const items: TimelineItem[] = [];
  let stepSum = 0;

  picked.forEach((place, i) => {
    const time = times[i] ?? times[times.length - 1];
    items.push(makeItem(day.dayNumber, time, place));
    stepSum += place.typicalSteps ?? 8000;
  });

  if (picked.length >= 2 && times[1]) {
    items.splice(1, 0, mealItem(day.dayNumber, times[1], 'Öğle molası'));
  }

  const themePlace = picked[0];
  const theme = themePlace
    ? `${themePlace.emoji} ${themePlace.city} — ${themePlace.name}`
    : `${flag} ${destLabel}`;

  return {
    ...day,
    theme,
    tags: picked.map((p) => p.name),
    stepsEstimate: stepSum || 10000,
    taxiRecommended: stepSum > 18000,
    items,
    highlights: picked.length
      ? [{ title: 'Öne çıkan', body: picked.map((p) => p.name).join(' · ') }]
      : undefined,
  };
}

/** Rota, tempo ve ülke profillerine göre gün-gün plan üretir (AI gerekmez). */
export function generateItineraryFromTrip(trip: Trip): DayPlan[] {
  const pace = trip.preferences.pace ?? 'moderate';
  const childCount =
    trip.preferences.childProfiles?.length ?? trip.preferences.childrenCount ?? 0;
  const kidMode = childCount > 0;
  const mustSee = trip.preferences.mustSee ?? [];
  const interests = trip.preferences.interests ?? [];
  const maxSteps = trip.preferences.maxStepsPerDay ?? 11000;
  const destinations = [...(trip.preferences.destinations ?? [])].sort((a, b) => a.order - b.order);
  const usedPlaces = new Set<string>();

  return trip.days.map((day) => {
    const dest = getDestinationForDate(destinations, day.date);
    if (!dest) return { ...day, items: day.items.length ? day.items : [] };

    const profile = getDestinationProfile(dest.countryCode);
    if (!profile) return day;

    const segDays = trip.days.filter((d) => {
      const dd = getDestinationForDate(destinations, d.date);
      return dd?.id === dest.id;
    });
    const dayIndexInSeg = segDays.findIndex((d) => d.dayNumber === day.dayNumber);
    const isFirst = dayIndexInSeg === 0;
    const isLast = dayIndexInSeg === segDays.length - 1;
    const flag = profile.flag;

    if (isLast && segDays.length > 1) {
      return buildDepartureDay(day, dest.city || profile.name, flag);
    }

    const templates = profile.dayTemplates ?? [];
    if (isFirst) {
      const arrival = templates.find((t) => t.id.includes('arrival')) ?? templates[0];
      if (arrival) return buildFromTemplate(day, arrival, profile.popularPlaces, pace);
    }

    const middleTemplates = templates.filter((t) => !t.id.includes('arrival'));
    if (middleTemplates.length) {
      const idx = Math.max(0, dayIndexInSeg - 1) % middleTemplates.length;
      const template = middleTemplates[idx];
      const built = buildFromTemplate(day, template, profile.popularPlaces, pace);
      template.places.forEach((id) => usedPlaces.add(id));
      return built;
    }

    return buildFromPlaces(
      day,
      profile.popularPlaces,
      pace,
      usedPlaces,
      kidMode,
      mustSee,
      interests,
      maxSteps,
      dest.city || profile.name,
      flag,
    );
  });
}

export interface AiItineraryDay {
  dayNumber: number;
  theme?: string;
  tags?: string[];
  stepsEstimate?: number;
  highlights?: DayHighlight[];
  items?: Array<{
    time?: string;
    title: string;
    description?: string;
    tips?: string;
    kind?: TimelineItem['kind'];
    durationMin?: number;
    cost?: number;
    costCurrency?: string;
    mapUrl?: string;
    lat?: number;
    lng?: number;
  }>;
}

const VALID_KINDS = new Set<TimelineItem['kind']>(['activity', 'transport', 'meal', 'hotel']);
function normalizeKind(raw: unknown): TimelineItem['kind'] {
  if (typeof raw !== 'string') return 'activity';
  const k = raw.toLowerCase();
  if (VALID_KINDS.has(k as TimelineItem['kind'])) return k as TimelineItem['kind'];
  if (k === 'arrival' || k === 'departure' || k === 'flight' || k === 'train' || k === 'taxi' || k === 'bus' || k === 'walk') return 'transport';
  if (k === 'food' || k === 'restaurant' || k === 'breakfast' || k === 'lunch' || k === 'dinner' || k === 'cafe') return 'meal';
  if (k === 'checkin' || k === 'check-in' || k === 'checkout' || k === 'check-out' || k === 'lodging') return 'hotel';
  return 'activity';
}

/** AI yanıtını mevcut gün iskeletine (tarih, weekday) uygular. */
export function mergeAiItinerary(baseDays: DayPlan[], aiDays: AiItineraryDay[]): DayPlan[] {
  const byNum = new Map(aiDays.map((d) => [d.dayNumber, d]));
  return baseDays.map((day) => {
    const ai = byNum.get(day.dayNumber);
    if (!ai) return day;
    const items: TimelineItem[] = (ai.items ?? []).map((it, idx) => ({
      id: newItemId(day.dayNumber) + `-${idx}`,
      time: it.time,
      scheduledTime: it.time,
      title: it.title,
      description: it.description,
      tips: it.tips,
      kind: normalizeKind(it.kind),
      durationMin: it.durationMin,
      cost: it.cost,
      costCurrency: it.costCurrency,
      mapUrl: it.mapUrl,
      lat: it.lat,
      lng: it.lng,
    }));
    return {
      ...day,
      theme: ai.theme ?? day.theme,
      tags: ai.tags ?? day.tags,
      stepsEstimate: ai.stepsEstimate ?? day.stepsEstimate,
      highlights: ai.highlights ?? day.highlights,
      items,
      taxiRecommended: (ai.stepsEstimate ?? day.stepsEstimate ?? 0) > 18000,
    };
  });
}
