import { describe, it, expect } from 'vitest';
import { fillEmptyDays } from '../fillEmptyDays';
import type { DayPlan, TripDestination } from '../types';

const dayBase = (overrides: Partial<DayPlan>): DayPlan => ({
  dayNumber: 1,
  date: '2026-10-01',
  theme: '',
  tags: [],
  items: [],
  ...overrides,
});

const tokyoDest: TripDestination = {
  id: 'd1',
  countryCode: 'JP',
  countryName: 'Japonya',
  city: 'Tokyo',
  arrivalDate: '2026-10-01',
  departureDate: '2026-10-10',
  order: 0,
};

describe('fillEmptyDays', () => {
  it('tamamen boş günü en az 4 itemla doldurur', () => {
    const days: DayPlan[] = [dayBase({})];
    const filled = fillEmptyDays(days, [tokyoDest]);
    expect(filled[0].items.length).toBeGreaterThanOrEqual(4);
  });

  it('yeterince dolu günleri (>=4) değiştirmez', () => {
    const days: DayPlan[] = [
      dayBase({
        items: Array.from({ length: 5 }, (_, i) => ({
          id: `i${i}`,
          title: `Item ${i}`,
          kind: 'activity' as const,
          time: `0${i + 8}:00`,
        })),
      }),
    ];
    const filled = fillEmptyDays(days, [tokyoDest]);
    expect(filled[0].items).toHaveLength(5);
  });

  it('az itemli günleri tamamlar, mevcut item korunur', () => {
    const existing = {
      id: 'orig',
      title: 'Senso-ji Asakusa',
      kind: 'activity' as const,
      time: '10:00',
    };
    const days: DayPlan[] = [dayBase({ items: [existing] })];
    const filled = fillEmptyDays(days, [tokyoDest]);
    expect(filled[0].items.length).toBeGreaterThanOrEqual(4);
    expect(filled[0].items.find((i) => i.id === 'orig')).toBeDefined();
  });

  it('item zaman sırasına dizilir', () => {
    const existing = {
      id: 'late',
      title: 'Geç aktivite',
      kind: 'activity' as const,
      time: '18:00',
    };
    const days: DayPlan[] = [dayBase({ items: [existing] })];
    const filled = fillEmptyDays(days, [tokyoDest]);
    const times = filled[0].items
      .map((i) => i.time ?? '99:99')
      .filter(Boolean);
    const sorted = [...times].sort((a, b) => a.localeCompare(b));
    expect(times).toEqual(sorted);
  });

  it('yemek slot sayısı 2 ile sınırlı', () => {
    const days: DayPlan[] = [dayBase({})];
    const filled = fillEmptyDays(days, [tokyoDest]);
    const meals = filled[0].items.filter((i) => i.kind === 'meal');
    expect(meals.length).toBeLessThanOrEqual(2);
  });
});
