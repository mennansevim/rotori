import type { GeoPoint } from './types.js';

const R_KM = 6371;

function toRad(deg: number): number {
  return (deg * Math.PI) / 180;
}

/** İki nokta arası büyük-daire mesafesi (km). */
export function haversineKm(a: GeoPoint, b: GeoPoint): number {
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);
  const lat1 = toRad(a.lat);
  const lat2 = toRad(b.lat);
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) ** 2;
  return 2 * R_KM * Math.asin(Math.min(1, Math.sqrt(h)));
}

/**
 * Mesafeye göre tahmini seyahat süresi (dakika).
 * Kısa mesafe yürüme/şehir içi, uzun mesafe araç varsayımı (kaba).
 */
export function estimateTravelMinutes(km: number): number {
  if (km <= 1.5) return Math.round((km / 4.5) * 60); // yürüme ~4.5 km/s
  if (km <= 40) return Math.round((km / 25) * 60); // şehir içi ~25 km/s
  return Math.round((km / 70) * 60); // şehirlerarası ~70 km/s
}

export function formatDistance(km: number): string {
  if (km < 1) return `${Math.round(km * 1000)} m`;
  return `${km.toFixed(km < 10 ? 1 : 0)} km`;
}

export function formatDuration(min: number): string {
  if (min < 60) return `${min} dk`;
  const h = Math.floor(min / 60);
  const m = min % 60;
  return m ? `${h} sa ${m} dk` : `${h} sa`;
}

/**
 * Nearest-neighbor ile sırayı optimize et. İlk öğe sabit başlangıç kabul edilir.
 * Koordinatı olmayan öğeler sırada en sona, göreli sırayı koruyarak eklenir.
 */
export function optimizeOrder<T>(
  items: T[],
  getPoint: (item: T) => GeoPoint | undefined,
): T[] {
  const withPoint = items.filter((i) => getPoint(i));
  const withoutPoint = items.filter((i) => !getPoint(i));
  if (withPoint.length <= 2) return [...withPoint, ...withoutPoint];

  const remaining = [...withPoint];
  const ordered: T[] = [remaining.shift()!];

  while (remaining.length) {
    const last = getPoint(ordered[ordered.length - 1])!;
    let bestIdx = 0;
    let bestDist = Infinity;
    remaining.forEach((cand, idx) => {
      const d = haversineKm(last, getPoint(cand)!);
      if (d < bestDist) {
        bestDist = d;
        bestIdx = idx;
      }
    });
    ordered.push(remaining.splice(bestIdx, 1)[0]);
  }

  return [...ordered, ...withoutPoint];
}
