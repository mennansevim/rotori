import type { DayPlan, Trip, TripPreferences } from './types.js';

export interface TripWarning {
  id: string;
  severity: 'info' | 'warn' | 'urgent';
  message: string;
  dayNumber?: number;
  /** Yayın adımındaki "adıma dön" butonu için hedef step id. */
  step?: 'journey' | 'explore' | 'title' | 'hotels' | 'food' | 'plan' | 'calendar';
}

export function checkStepsOverLimit(day: DayPlan, maxSteps?: number): TripWarning | null {
  if (!maxSteps) return null;
  const estimate = day.stepsEstimateMax ?? day.stepsEstimate;
  if (estimate != null && estimate > maxSteps) {
    return {
      id: `steps-${day.dayNumber}`,
      severity: 'warn',
      message: `Gün ${day.dayNumber}: tahmini ${estimate.toLocaleString('tr-TR')} adım, limit ${maxSteps.toLocaleString('tr-TR')}. Taksi veya aktivite azaltmayı düşünün.`,
      dayNumber: day.dayNumber,
      step: 'plan',
    };
  }
  return null;
}

export function checkUnassignedMustSee(trip: Trip): TripWarning[] {
  const assigned = new Set(
    trip.days.flatMap((d) =>
      d.items.flatMap((i) => [i.title, ...(i.description ? [i.description] : [])]),
    ),
  );
  const text = [...assigned].join(' ').toLowerCase();
  return trip.preferences.mustSee
    .filter((place) => !text.includes(place.toLowerCase()))
    .map((place) => ({
      id: `mustsee-${place}`,
      severity: 'info' as const,
      message: `"${place}" henüz günlük plana eklenmemiş.`,
      step: 'plan' as const,
    }));
}

export function checkShinkansenDeadline(
  deadline: string | undefined,
  now = new Date(),
): TripWarning | null {
  if (!deadline) return null;
  const d = new Date(deadline);
  const diff = d.getTime() - now.getTime();
  const days = Math.floor(diff / (86400000));
  if (days <= 0) {
    return {
      id: 'shinkansen-urgent',
      severity: 'urgent',
      message: 'Shinkansen rezervasyon penceresi geçti veya bugün son gün.',
    };
  }
  if (days <= 30) {
    return {
      id: 'shinkansen-soon',
      severity: 'warn',
      message: `Shinkansen rezervasyonuna ${days} gün kaldı.`,
    };
  }
  return null;
}

export function checkHotelsIncomplete(trip: Trip): TripWarning | null {
  const dests = trip.preferences.destinations ?? [];
  if (dests.length === 0) return null;
  const hotels = trip.hotels ?? [];
  if (hotels.length === 0) {
    return {
      id: 'hotels-missing',
      severity: 'warn',
      message: 'Henüz otel eklenmedi. Konaklama adımında en az bir otel ekle.',
      step: 'hotels',
    };
  }
  const incomplete = hotels.filter(
    (h) => !h.city?.trim() || !h.name?.trim() || !h.address?.trim(),
  );
  if (incomplete.length > 0) {
    return {
      id: 'hotels-incomplete',
      severity: 'warn',
      message: `${incomplete.length} otel için şehir, ad veya açık adres eksik.`,
      step: 'hotels',
    };
  }
  return null;
}

export function checkEmptyPlan(trip: Trip): TripWarning | null {
  if (trip.days.length === 0) return null;
  const allEmpty = trip.days.every((d) => d.items.length === 0);
  if (allEmpty) {
    return {
      id: 'plan-empty',
      severity: 'warn',
      message: 'Plan günleri tamamen boş. Plan adımından gezi planını oluştur.',
      step: 'plan',
    };
  }
  return null;
}

export function checkMissingTitle(trip: Trip): TripWarning | null {
  const t = trip.title?.trim();
  if (!t || t === 'Yeni seyahat' || t === 'Japonya Turu') {
    return {
      id: 'title-default',
      severity: 'info',
      message: 'Plan başlığı varsayılan. Kendi başlığını yazmak istersen Başlık adımına dön.',
      step: 'title',
    };
  }
  return null;
}

export function collectTripWarnings(trip: Trip): TripWarning[] {
  const warnings: TripWarning[] = [];

  const hotel = checkHotelsIncomplete(trip);
  if (hotel) warnings.push(hotel);
  const empty = checkEmptyPlan(trip);
  if (empty) warnings.push(empty);
  const title = checkMissingTitle(trip);
  if (title) warnings.push(title);

  warnings.push(...checkUnassignedMustSee(trip));
  const sh = checkShinkansenDeadline(trip.deadlines?.shinkansenBooking);
  if (sh) warnings.push(sh);

  return warnings;
}

export function suggestTaxiForDay(day: DayPlan, prefs: TripPreferences): boolean {
  const est = day.stepsEstimateMax ?? day.stepsEstimate ?? 0;
  const max = prefs.maxStepsPerDay ?? 14000;
  return est > max || day.taxiRecommended === true;
}

export function moveItemBetweenDays(
  days: DayPlan[],
  itemId: string,
  fromDayNumber: number,
  toDayNumber: number,
): DayPlan[] {
  if (fromDayNumber === toDayNumber) return days;

  const next = days.map((d) => ({
    ...d,
    items: [...d.items],
  }));

  const from = next.find((d) => d.dayNumber === fromDayNumber);
  const to = next.find((d) => d.dayNumber === toDayNumber);
  if (!from || !to) return days;

  const idx = from.items.findIndex((i) => i.id === itemId);
  if (idx < 0) return days;

  const [item] = from.items.splice(idx, 1);
  to.items.push({
    ...item,
    movedFromDay: fromDayNumber,
  });

  return next;
}
