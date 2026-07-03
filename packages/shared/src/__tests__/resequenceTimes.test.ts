import { describe, it, expect } from 'vitest';
import { resequenceTimes } from '../dayOptimizer';
import type { TimelineItem } from '../types';

const item = (id: string, time: string, extra: Partial<TimelineItem> = {}): TimelineItem => ({
  id,
  title: id,
  kind: 'activity',
  time,
  scheduledTime: time,
  ...extra,
});

describe('resequenceTimes', () => {
  it('mevcut saatleri yeni sıraya göre kronolojik dağıtır', () => {
    // Kullanıcı öğle yemeğini tapınağın üstüne sürükledi (13:00 üstte, 10:00 altta).
    const dragged = [item('lunch', '13:00'), item('temple', '10:00')];
    const out = resequenceTimes(dragged);
    // Sıra korunur ama saatler yukarıdan aşağı artan olur.
    expect(out.map((i) => i.id)).toEqual(['lunch', 'temple']);
    expect(out.map((i) => i.time)).toEqual(['10:00', '13:00']);
    expect(out.map((i) => i.scheduledTime)).toEqual(['10:00', '13:00']);
  });

  it('üç kalemi yeni sıraya göre yeniden zamanlar', () => {
    const items = [item('c', '18:00'), item('a', '09:00'), item('b', '12:30')];
    const out = resequenceTimes(items);
    expect(out.map((i) => i.id)).toEqual(['c', 'a', 'b']);
    expect(out.map((i) => i.time)).toEqual(['09:00', '12:30', '18:00']);
  });

  it('zaten sıralıysa aynı referansları döndürür (gereksiz güncelleme yok)', () => {
    const items = [item('a', '10:00'), item('b', '14:00')];
    const out = resequenceTimes(items);
    expect(out[0]).toBe(items[0]);
    expect(out[1]).toBe(items[1]);
  });

  it('saatsiz kalemlere dokunmaz, saatlileri kendi arasında sıralar', () => {
    const noTime = item('x', '');
    const items = [item('late', '16:00'), noTime, item('early', '08:00')];
    const out = resequenceTimes(items);
    expect(out.map((i) => i.id)).toEqual(['late', 'x', 'early']);
    expect(out[0].time).toBe('08:00'); // late pozisyonu en erken saati aldı
    expect(out[1]).toBe(noTime); // saatsiz aynen kaldı
    expect(out[2].time).toBe('16:00');
  });

  it('hiç saat yoksa diziyi olduğu gibi bırakır', () => {
    const items = [item('a', ''), item('b', '')];
    expect(resequenceTimes(items)).toBe(items);
  });
});
