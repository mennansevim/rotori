import type { DayPlan, TimelineItem } from './types.js';

/**
 * Bir günü saat + coğrafi açıdan optimize eder:
 * 1. Sabit ulaşım/otel kalemleri (transport, hotel) yerinde kalır.
 * 2. activity + meal kalemleri lat/lng varsa nearest-neighbor ile sıralanır.
 *    İlk nokta: ilk transport/hotel ya da en kuzey-batıdaki (sabah erken için).
 * 3. Yemek kalemleri öğle (12:30) ve akşam (19:00) civarına yakınsa orada,
 *    değilse sırayı bozmadan yerleştirilir.
 * 4. Saat yeniden atanır: activity 1.5 saat, meal 1 saat, transport 0.5 saat (varsa).
 */

interface Point {
  lat?: number;
  lng?: number;
}

function distance(a: Point, b: Point): number {
  if (a.lat == null || a.lng == null || b.lat == null || b.lng == null) return Infinity;
  const dLat = a.lat - b.lat;
  const dLng = a.lng - b.lng;
  return Math.sqrt(dLat * dLat + dLng * dLng);
}

function nearestNeighborOrder<T extends Point>(items: T[], startIdx = 0): T[] {
  if (items.length <= 2) return items.slice();
  const remaining = items.slice();
  const ordered: T[] = [];
  ordered.push(remaining.splice(startIdx, 1)[0]);
  while (remaining.length) {
    const last = ordered[ordered.length - 1];
    let bestIdx = 0;
    let bestDist = Infinity;
    for (let i = 0; i < remaining.length; i++) {
      const d = distance(last, remaining[i]);
      if (d < bestDist) {
        bestDist = d;
        bestIdx = i;
      }
    }
    ordered.push(remaining.splice(bestIdx, 1)[0]);
  }
  return ordered;
}

function timeToMin(t?: string): number {
  if (!t) return -1;
  const m = t.match(/^(\d{1,2}):(\d{2})$/);
  if (!m) return -1;
  return Number(m[1]) * 60 + Number(m[2]);
}

function minToTime(min: number): string {
  const h = Math.max(0, Math.min(23, Math.floor(min / 60)));
  const m = Math.max(0, Math.min(59, min % 60));
  return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}`;
}

function durationFor(item: TimelineItem): number {
  if (item.durationMin && item.durationMin > 0) return item.durationMin;
  if (item.kind === 'meal') return 60;
  if (item.kind === 'transport') return 30;
  if (item.kind === 'hotel') return 30;
  return 90;
}

/**
 * Item'ların GÖRSEL SIRASINI korur, yalnızca saatleri o sıraya göre yeniden
 * dağıtır: mevcut saatler artan sıraya konur ve yukarıdan aşağıya atanır.
 * Sürükle-bırak ile sıra değişince saatlerin de kronolojik kalması için.
 * Saatsiz kalemler olduğu gibi bırakılır.
 */
export function resequenceTimes(items: TimelineItem[]): TimelineItem[] {
  const sortedTimes = items
    .map((it) => it.time ?? it.scheduledTime)
    .filter((t): t is string => timeToMin(t) >= 0)
    .sort((a, b) => timeToMin(a) - timeToMin(b));
  if (sortedTimes.length === 0) return items;

  let ti = 0;
  return items.map((it) => {
    const cur = it.time ?? it.scheduledTime;
    if (timeToMin(cur) < 0) return it; // saatsiz — dokunma
    const t = sortedTimes[ti++];
    if (t === it.time && t === it.scheduledTime) return it;
    return { ...it, time: t, scheduledTime: t };
  });
}

/**
 * Bir günün item'larını saat ve coğrafi sıraya göre yeniden düzenler.
 * Mevcut item id'lerini korur — sadece time/scheduledTime günceller.
 */
export function optimizeDayItems(items: TimelineItem[]): TimelineItem[] {
  if (items.length <= 1) return items;

  // Transport ve hotel kalemleri sabit (uçuş, check-in vb.) — kendi saatlerini tut.
  const anchors: TimelineItem[] = [];
  const flexible: TimelineItem[] = [];
  for (const it of items) {
    if (it.kind === 'transport' || it.kind === 'hotel') {
      anchors.push(it);
    } else {
      flexible.push(it);
    }
  }

  // Flexible'ları coğrafi olarak sırala (lat/lng varsa).
  const haveCoords = flexible.filter((f) => f.lat != null && f.lng != null);
  let ordered: TimelineItem[];
  if (haveCoords.length >= 2 && haveCoords.length === flexible.length) {
    // En kuzeydeki noktadan başla (sabah erken, daha iyi tempo).
    let startIdx = 0;
    let maxLat = -Infinity;
    for (let i = 0; i < flexible.length; i++) {
      const lat = flexible[i].lat;
      if (lat != null && lat > maxLat) {
        maxLat = lat;
        startIdx = i;
      }
    }
    ordered = nearestNeighborOrder(flexible, startIdx);
  } else {
    // Koordinat yoksa mevcut zaman sırasını koru.
    ordered = flexible
      .slice()
      .sort((a, b) => {
        const ta = timeToMin(a.time ?? a.scheduledTime);
        const tb = timeToMin(b.time ?? b.scheduledTime);
        if (ta < 0 && tb < 0) return 0;
        if (ta < 0) return 1;
        if (tb < 0) return -1;
        return ta - tb;
      });
  }

  // Anchor'ları başlangıç sırasında ve kendi saatlerinde tut.
  // Stratejisi: anchor'lar zaman çizelgesine ekle, flexible'ları aralara doldur.

  // Önce anchor'ları saate göre sırala.
  const anchorsSorted = anchors.slice().sort((a, b) => {
    const ta = timeToMin(a.time ?? a.scheduledTime);
    const tb = timeToMin(b.time ?? b.scheduledTime);
    if (ta < 0 && tb < 0) return 0;
    if (ta < 0) return 1;
    if (tb < 0) return -1;
    return ta - tb;
  });

  // Akıllı zaman dağıtımı:
  // Sabah 09:00 başla. Anchor'ın kendi saati varsa onu kullan, sonraki flexible
  // o saatten sonra yerleştir.
  const out: TimelineItem[] = [];
  let cursorMin = 9 * 60; // 09:00 default
  const anchorIter = anchorsSorted[Symbol.iterator]();
  let nextAnchor = anchorIter.next();

  // En erken anchor 09:00'dan önceyse oradan başla (örn. 06:00 uçuş).
  const firstAnchorMin = anchorsSorted[0]
    ? timeToMin(anchorsSorted[0].time ?? anchorsSorted[0].scheduledTime)
    : -1;
  if (firstAnchorMin >= 0 && firstAnchorMin < cursorMin) {
    cursorMin = firstAnchorMin;
  }

  const flexQueue = ordered.slice();
  let lastMealMin = -1;

  while (flexQueue.length || !nextAnchor.done) {
    const anchor = nextAnchor.done ? null : nextAnchor.value;
    const anchorMin = anchor ? timeToMin(anchor.time ?? anchor.scheduledTime) : Infinity;

    if (anchor && anchorMin >= 0 && anchorMin <= cursorMin) {
      // Anchor sırası geldi — kendi saatini kullan.
      out.push({ ...anchor, time: minToTime(anchorMin), scheduledTime: minToTime(anchorMin) });
      cursorMin = anchorMin + durationFor(anchor);
      nextAnchor = anchorIter.next();
      continue;
    }

    if (!flexQueue.length) {
      // Sadece geleceğe ait anchor kaldı — onu da ekle.
      if (anchor) {
        out.push({
          ...anchor,
          time: minToTime(anchorMin >= 0 ? anchorMin : cursorMin),
          scheduledTime: minToTime(anchorMin >= 0 ? anchorMin : cursorMin),
        });
        cursorMin = (anchorMin >= 0 ? anchorMin : cursorMin) + durationFor(anchor);
        nextAnchor = anchorIter.next();
      }
      continue;
    }

    // Sıradaki flexible'ı yerleştir.
    let next = flexQueue.shift()!;

    // Yemek slot tercihi: öğle (12:00-13:30) ve akşam (18:30-20:00).
    if (next.kind === 'meal') {
      const lunchOk = lastMealMin < 0 && cursorMin >= 11 * 60 + 30;
      const dinnerOk = lastMealMin > 0 && cursorMin >= 17 * 60 + 30;
      if (!lunchOk && !dinnerOk && cursorMin < 11 * 60 + 30) {
        // Çok erken — flexible'ları yeniden sırala ki meal sonra gelsin.
        const swap = flexQueue.findIndex((f) => f.kind !== 'meal');
        if (swap >= 0) {
          flexQueue.unshift(next);
          next = flexQueue.splice(swap + 1, 1)[0];
        }
      }
    }

    // Anchor'a çok yakınsa anchor'ı önce ekle.
    if (anchor && anchorMin >= 0 && cursorMin + durationFor(next) > anchorMin) {
      out.push({ ...anchor, time: minToTime(anchorMin), scheduledTime: minToTime(anchorMin) });
      cursorMin = anchorMin + durationFor(anchor);
      nextAnchor = anchorIter.next();
      flexQueue.unshift(next);
      continue;
    }

    out.push({ ...next, time: minToTime(cursorMin), scheduledTime: minToTime(cursorMin) });
    if (next.kind === 'meal') lastMealMin = cursorMin;
    cursorMin += durationFor(next) + 30; // 30 dk geçiş

    // Öğle aralığına ulaştıysak yemek zorla.
    if (cursorMin >= 12 * 60 + 30 && lastMealMin < 0) {
      const mealIdx = flexQueue.findIndex((f) => f.kind === 'meal');
      if (mealIdx > 0) {
        flexQueue.unshift(flexQueue.splice(mealIdx, 1)[0]);
      }
    }
  }

  return out;
}

export function optimizeDay(day: DayPlan): DayPlan {
  return { ...day, items: optimizeDayItems(day.items) };
}
