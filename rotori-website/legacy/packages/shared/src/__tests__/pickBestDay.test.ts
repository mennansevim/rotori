import { describe, it, expect } from 'vitest';
import { pickBestDayForDestination } from '../tripFactory';
import type { DayPlan } from '../types';

const makeDay = (n: number, activities = 0, steps = 0): DayPlan => ({
  dayNumber: n,
  date: `2026-10-${String(n).padStart(2, '0')}`,
  theme: '',
  tags: [],
  stepsEstimate: steps,
  items: Array.from({ length: activities }, (_, i) => ({
    id: `${n}-${i}`,
    title: `act ${i}`,
    kind: 'activity' as const,
  })),
});

describe('pickBestDayForDestination', () => {
  it('boş listede null döner', () => {
    expect(pickBestDayForDestination([makeDay(1, 0)], [])).toBeNull();
  });

  it('en az aktiviteli günü seçer', () => {
    const days = [makeDay(1, 3), makeDay(2, 0), makeDay(3, 2)];
    expect(pickBestDayForDestination(days, [1, 2, 3])).toBe(2);
  });

  it('eşit aktivitede daha düşük adım tahminini tercih eder', () => {
    const days = [makeDay(1, 2, 12000), makeDay(2, 2, 8000)];
    expect(pickBestDayForDestination(days, [1, 2])).toBe(2);
  });

  it('eşit metriklerde en erken günü tercih eder', () => {
    const days = [makeDay(2, 1, 9000), makeDay(1, 1, 9000)];
    expect(pickBestDayForDestination(days, [1, 2])).toBe(1);
  });

  it('sadece izin verilen günler arasından seçer', () => {
    const days = [makeDay(1, 0), makeDay(2, 5), makeDay(3, 0)];
    expect(pickBestDayForDestination(days, [2])).toBe(2);
  });
});
