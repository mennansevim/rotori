import type {
  DayPlan,
  FoodSensitivity,
  TimelineItem,
  Trip,
  TripPreferences,
  WalkingTarget,
} from './types.js';
import { WALKING_TARGET_STEPS } from './types.js';

const WEEKDAYS_TR = ['PAZ', 'PZT', 'SAL', 'ÇAR', 'PER', 'CUM', 'CMT'];

function weekdayTr(isoDate: string): string {
  const d = new Date(isoDate + 'T12:00:00');
  return WEEKDAYS_TR[d.getDay()];
}

function addDays(iso: string, n: number): string {
  const d = new Date(iso + 'T12:00:00');
  d.setDate(d.getDate() + n);
  return d.toISOString().slice(0, 10);
}

export function generateDaysBetween(start: string, end: string): DayPlan[] {
  const days: DayPlan[] = [];
  let current = start;
  let num = 0;
  while (current <= end && num < 60) {
    num += 1;
    days.push({
      dayNumber: num,
      date: current,
      weekday: weekdayTr(current),
      theme: `Gün ${num}`,
      tags: [],
      items: [],
      stepsEstimate: 10000,
    });
    current = addDays(current, 1);
  }
  return days;
}

function defaultTimezone(): string {
  try {
    return Intl.DateTimeFormat().resolvedOptions().timeZone;
  } catch {
    return 'UTC';
  }
}

export function createEmptyTrip(overrides?: Partial<Trip>): Trip {
  const id = crypto.randomUUID?.() ?? `trip-${Date.now()}`;
  const slug = `yeni-${Date.now().toString(36)}`;
  const start = addDays(new Date().toISOString().slice(0, 10), 14);
  const end = addDays(start, 6);
  const tz = defaultTimezone();

  const base: Trip = {
    id,
    slug,
    title: 'Japonya Turu',
    subtitle: '',
    timezone: tz,
    tripStart: `${start}T08:00:00`,
    tripEnd: `${end}T20:00:00`,
    flights: {
      outbound: [
        { city: '', airport: '', dateTime: `${start}T10:00:00` },
        { city: '', airport: '', dateTime: `${start}T18:00:00` },
      ],
      return: [
        { city: '', airport: '', dateTime: `${end}T10:00:00` },
        { city: '', airport: '', dateTime: `${end}T20:00:00` },
      ],
    },
    hotels: [],
    tickets: [],
    preferences: {
      travelDates: { start, end },
      originCity: '',
      destinationCity: '',
      destinationCountry: 'JP',
      destinations: [],
      destinationFood: [],
      mustSee: [],
      foodLikes: [],
      foodDislikes: [],
      dietary: [],
      dietaryTags: [],
      mealBudgetPerPerson: 2500,
      mealBudgetCurrency: 'JPY',
      planMeals: true,
      maxStepsPerDay: WALKING_TARGET_STEPS.moderate,
      pace: 'moderate',
      partySize: 2,
      tripType: 'multicity',
      nearbyAirportsOrigin: false,
      nearbyAirportsDest: false,
      directFlightsOnly: false,
      walkingTarget: 'moderate',
      transportPreference: 'mixed',
      paymentPreference: 'credit_and_cash',
      childProfiles: [],
      interests: [],
      foodSensitivities: [],
    },
    days: generateDaysBetween(start, end),
    deadlines: {},
  };

  return { ...base, ...overrides };
}

export function syncTripRoute(
  trip: Trip,
  input: {
    originCity: string;
    originAirport?: string;
    destinationCity: string;
    destinationAirport?: string;
    start: string;
    end: string;
    destinationCountry?: string;
  },
): Trip {
  const { originCity, destinationCity, start, end } = input;
  const title =
    originCity && destinationCity
      ? `${originCity} → ${destinationCity}`
      : trip.title;

  return {
    ...trip,
    title:
      trip.title === 'Yeni seyahat' || trip.title === 'Japonya Turu'
        ? title
        : trip.title,
    preferences: {
      ...trip.preferences,
      originCity,
      destinationCity,
      destinationCountry: input.destinationCountry ?? trip.preferences.destinationCountry,
      travelDates: { start, end },
    },
    tripStart: `${start}T08:00:00`,
    tripEnd: `${end}T20:00:00`,
    flights: {
      outbound: [
        {
          city: originCity,
          airport: input.originAirport ?? trip.flights.outbound[0]?.airport ?? '',
          dateTime: `${start}T10:00:00`,
        },
        {
          city: destinationCity,
          airport: input.destinationAirport ?? trip.flights.outbound[1]?.airport ?? '',
          dateTime: `${start}T18:00:00`,
        },
      ],
      return: [
        {
          city: destinationCity,
          airport: input.destinationAirport ?? trip.flights.return[0]?.airport ?? '',
          dateTime: `${end}T10:00:00`,
        },
        {
          city: originCity,
          airport: input.originAirport ?? trip.flights.return[1]?.airport ?? '',
          dateTime: `${end}T20:00:00`,
        },
      ],
    },
    days: generateDaysBetween(start, end),
  };
}

export function isTransportTicket(kind: string): boolean {
  return ['flight', 'train', 'bus', 'ferry'].includes(kind);
}

/** foodSensitivities tag listesinden dietaryTags türetir. */
export function dietaryTagsFromSensitivities(
  sensitivities: FoodSensitivity[] | undefined,
): string[] {
  if (!sensitivities || sensitivities.length === 0) return [];
  const out = new Set<string>();
  for (const s of sensitivities) {
    if (s === 'no_pork' || s === 'no_pork_derivatives') {
      out.add('no_pork');
    }
    if (s === 'no_seafood') out.add('no_seafood');
    if (s === 'halal_only') out.add('halal');
    if (s === 'vegetarian') out.add('vegetarian');
    if (s === 'kid_friendly') out.add('kid_friendly');
    if (s === 'chicken_focus') out.add('chicken_focus');
    if (s === 'turkish_palate') out.add('turkish_palate');
    if (s === 'no_fatty_meat') out.add('no_fatty_meat');
  }
  return Array.from(out);
}

/**
 * Eski localStorage verilerini yeni alanlarla doldurur. Mevcut alanları korur,
 * eksik olanları varsayılanlarla tamamlar. Strict reject yok — geri uyumlu.
 */
export function ensureTripPreferences(trip: Trip): Trip {
  const p = trip.preferences ?? ({} as TripPreferences);
  const walkingTarget: WalkingTarget = p.walkingTarget ?? 'moderate';
  const sensitivities = p.foodSensitivities ?? [];
  const sensitivityTags = dietaryTagsFromSensitivities(sensitivities);
  const existingDietaryTags = p.dietaryTags ?? [];
  const mergedDietaryTags = Array.from(
    new Set([...existingDietaryTags, ...sensitivityTags]),
  );
  const childrenCount =
    p.childProfiles?.length != null && p.childProfiles.length > 0
      ? p.childProfiles.length
      : p.childrenCount ?? 0;

  return {
    ...trip,
    preferences: {
      ...p,
      walkingTarget,
      transportPreference: p.transportPreference ?? 'mixed',
      paymentPreference: p.paymentPreference ?? 'credit_and_cash',
      childProfiles: p.childProfiles ?? [],
      interests: p.interests ?? [],
      foodSensitivities: sensitivities,
      dietaryTags: mergedDietaryTags,
      maxStepsPerDay: p.maxStepsPerDay ?? WALKING_TARGET_STEPS[walkingTarget],
      childrenCount,
    },
  };
}

export function newId(prefix: string) {
  return `${prefix}-${Date.now().toString(36)}`;
}

export function newHotelId() {
  return newId('hotel');
}

export function newTicketId() {
  return `ticket-${Date.now().toString(36)}`;
}

let __itemSeq = 0;
export function newItemId(dayNumber: number) {
  __itemSeq = (__itemSeq + 1) % 1_000_000;
  const t = Date.now().toString(36).slice(-4);
  const s = __itemSeq.toString(36);
  const r = Math.random().toString(36).slice(2, 5);
  return `d${dayNumber}-i${t}${s}${r}`;
}

const ACTIVITY_TIME_SLOTS = [
  '09:30',
  '11:00',
  '13:00',
  '14:30',
  '16:00',
  '17:30',
  '19:00',
];

/**
 * Bu güne yeni bir aktivite için en uygun saat slot'unu seçer.
 * Mevcut item'ların saatlerini dikkate alır; dolu slot'ları atlar.
 */
function nextTimeSlot(day: DayPlan): string {
  const used = new Set<string>();
  for (const it of day.items) {
    const t = it.scheduledTime ?? it.time;
    if (t) used.add(t);
  }
  for (const slot of ACTIVITY_TIME_SLOTS) {
    if (!used.has(slot)) return slot;
  }
  // Tüm slot'lar dolduysa 30 dakika ekleyerek devam et
  const last = ACTIVITY_TIME_SLOTS[ACTIVITY_TIME_SLOTS.length - 1];
  const [h, m] = last.split(':').map(Number);
  const total = h * 60 + m + 30 * (day.items.length - ACTIVITY_TIME_SLOTS.length + 1);
  const hh = Math.min(23, Math.floor(total / 60));
  const mm = total % 60;
  return `${String(hh).padStart(2, '0')}:${String(mm).padStart(2, '0')}`;
}

export function addPlaceToDay(
  days: DayPlan[],
  dayNumber: number,
  place: { name: string; emoji?: string; steps?: number },
): DayPlan[] {
  return days.map((d) => {
    if (d.dayNumber !== dayNumber) return d;
    const time = nextTimeSlot(d);
    const item: TimelineItem = {
      id: newItemId(dayNumber),
      title: `${place.emoji ?? '📍'} ${place.name}`,
      kind: 'activity',
      time,
      scheduledTime: time,
    };
    const tags = d.tags.includes(place.name) ? d.tags : [...d.tags, place.name];
    return {
      ...d,
      tags,
      theme: d.theme === `Gün ${dayNumber}` ? place.name : d.theme,
      stepsEstimate: (d.stepsEstimate ?? 0) + (place.steps ?? 3000),
      items: [...d.items, item],
    };
  });
}

/**
 * Belirli bir destinasyona ait günler arasından,
 * yeni bir aktivite için en uygun olanı seçer.
 * Sıralama: en az aktivite sayısı → en düşük adım tahmini → en erken gün.
 */
export function pickBestDayForDestination(
  days: DayPlan[],
  destinationDayNumbers: number[],
): number | null {
  if (destinationDayNumbers.length === 0) return null;
  const candidates = days
    .filter((d) => destinationDayNumbers.includes(d.dayNumber))
    .slice()
    .sort((a, b) => {
      const aAct = a.items.filter((it) => it.kind === 'activity' || it.kind == null).length;
      const bAct = b.items.filter((it) => it.kind === 'activity' || it.kind == null).length;
      if (aAct !== bAct) return aAct - bAct;
      const aSteps = a.stepsEstimate ?? 0;
      const bSteps = b.stepsEstimate ?? 0;
      if (aSteps !== bSteps) return aSteps - bSteps;
      return a.dayNumber - b.dayNumber;
    });
  return candidates[0]?.dayNumber ?? null;
}

export function applyDayTemplate(
  days: DayPlan[],
  dayNumber: number,
  template: { theme: string; emoji: string; places: { name: string; emoji: string }[]; stepsEstimate: number },
): DayPlan[] {
  let next = days.map((d) =>
    d.dayNumber === dayNumber
      ? {
          ...d,
          theme: `${template.emoji} ${template.theme}`,
          stepsEstimate: template.stepsEstimate,
          taxiRecommended: template.stepsEstimate > 18000,
        }
      : d,
  );
  for (const p of template.places) {
    next = addPlaceToDay(next, dayNumber, p);
  }
  return next;
}
