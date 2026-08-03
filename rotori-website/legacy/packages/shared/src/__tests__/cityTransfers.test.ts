import { describe, it, expect } from 'vitest';
import {
  lookupTransfer,
  detectCityTransitions,
  hasExistingTransferTo,
} from '../cityTransfers';
import type { DayPlan, TripDestination } from '../types';

const dayBase = (overrides: Partial<DayPlan>): DayPlan => ({
  dayNumber: 1,
  date: '2026-10-01',
  theme: '',
  tags: [],
  items: [],
  ...overrides,
});

const destBase = (overrides: Partial<TripDestination>): TripDestination => ({
  id: 'd1',
  countryCode: 'JP',
  countryName: 'Japonya',
  city: 'Tokyo',
  arrivalDate: '2026-10-01',
  departureDate: '2026-10-10',
  order: 0,
  ...overrides,
});

describe('lookupTransfer', () => {
  it('bilinen Tokyo→Osaka çiftini bulur', () => {
    const t = lookupTransfer('Tokyo', 'Osaka');
    expect(t?.mode).toContain('Shinkansen');
    expect(t?.duration).toMatch(/2s/);
  });

  it('ters yönü de döndürür', () => {
    expect(lookupTransfer('Osaka', 'Tokyo')?.mode).toContain('Shinkansen');
  });

  it('parantezli şehir isimlerini normalize eder', () => {
    expect(lookupTransfer('Tokyo (Haneda)', 'Kyoto')?.mode).toContain('Shinkansen');
  });

  it('bilinmeyen çift için undefined', () => {
    expect(lookupTransfer('Tokyo', 'Pluto')).toBeUndefined();
  });
});

describe('detectCityTransitions', () => {
  it('item.cityId üzerinden geçişi bulur', () => {
    const days: DayPlan[] = [
      dayBase({
        dayNumber: 1,
        items: [{ id: 'i1', title: 'Senso-ji', cityId: 'Tokyo', kind: 'activity' }],
      }),
      dayBase({
        dayNumber: 2,
        date: '2026-10-02',
        items: [{ id: 'i2', title: 'Dotonbori', cityId: 'Osaka', kind: 'activity' }],
      }),
    ];
    const transitions = detectCityTransitions(days, []);
    expect(transitions).toHaveLength(1);
    expect(transitions[0].fromCity).toBe('Tokyo');
    expect(transitions[0].toCity).toBe('Osaka');
    expect(transitions[0].toDayNumber).toBe(2);
  });

  it('aynı şehirdeki ardışık günlerde transition yok', () => {
    const days: DayPlan[] = [
      dayBase({ dayNumber: 1, items: [{ id: 'i1', title: 'A', cityId: 'Tokyo' }] }),
      dayBase({ dayNumber: 2, items: [{ id: 'i2', title: 'B', cityId: 'Tokyo' }] }),
    ];
    expect(detectCityTransitions(days, [])).toHaveLength(0);
  });

  it('destinasyondan fallback eder (cityId yoksa)', () => {
    const days: DayPlan[] = [
      dayBase({ dayNumber: 1, date: '2026-10-01' }),
      dayBase({ dayNumber: 2, date: '2026-10-05' }),
    ];
    const dests: TripDestination[] = [
      destBase({ id: 'd1', city: 'Tokyo', arrivalDate: '2026-10-01', departureDate: '2026-10-03' }),
      destBase({ id: 'd2', city: 'Osaka', arrivalDate: '2026-10-04', departureDate: '2026-10-07', order: 1 }),
    ];
    const transitions = detectCityTransitions(days, dests);
    expect(transitions[0]?.fromCity).toBe('Tokyo');
    expect(transitions[0]?.toCity).toBe('Osaka');
  });
});

describe('hasExistingTransferTo', () => {
  it('mevcut transport item için true', () => {
    const day = dayBase({
      items: [
        {
          id: 't1',
          title: '🚄 Tokyo → Osaka • Shinkansen',
          kind: 'transport',
        },
      ],
    });
    expect(hasExistingTransferTo(day, 'Osaka')).toBe(true);
  });

  it('benzer activity item için false', () => {
    const day = dayBase({
      items: [{ id: 'a1', title: 'Osaka kalesi gezisi', kind: 'activity' }],
    });
    expect(hasExistingTransferTo(day, 'Osaka')).toBe(false);
  });
});
