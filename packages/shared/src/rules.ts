import type { DayPlan, Trip, TripPreferences } from './types.js';

export interface TripWarning {
  id: string;
  severity: 'info' | 'warn' | 'urgent';
  message: string;
  dayNumber?: number;
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

export function collectTripWarnings(trip: Trip): TripWarning[] {
  const warnings: TripWarning[] = [];

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
