import { describe, it, expect } from 'vitest';
import { MAX_TRIP_DAYS } from '../types';

describe('MAX_TRIP_DAYS', () => {
  it('31 sabit (yaklaşık 1 ay)', () => {
    expect(MAX_TRIP_DAYS).toBe(31);
  });

  it('clamp davranışı: end > start+MAX-1 → kısıt', () => {
    // Welcome/Journey'de uygulanan clamp formülünün doğruluğu
    const start = '2026-10-01';
    const maxEnd = (() => {
      const d = new Date(start + 'T00:00:00Z');
      d.setUTCDate(d.getUTCDate() + MAX_TRIP_DAYS - 1);
      return d.toISOString().slice(0, 10);
    })();
    expect(maxEnd).toBe('2026-10-31');
  });
});
