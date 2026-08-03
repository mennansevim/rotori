import type { GeoPoint } from './types.js';

export interface ProjectOptions {
  width: number;
  height: number;
}

/** Equirectangular: lng[-180,180]→x, lat[90,-90]→y. Tüm dünya. */
export function projectEquirect(p: GeoPoint, opts: ProjectOptions) {
  const x = ((p.lng + 180) / 360) * opts.width;
  const y = ((90 - p.lat) / 180) * opts.height;
  return { x, y };
}

export interface BBox {
  minLat: number;
  maxLat: number;
  minLng: number;
  maxLng: number;
}

export function boundsOf(points: GeoPoint[], pad = 0.15): BBox | null {
  if (!points.length) return null;
  let minLat = Infinity;
  let maxLat = -Infinity;
  let minLng = Infinity;
  let maxLng = -Infinity;
  for (const p of points) {
    minLat = Math.min(minLat, p.lat);
    maxLat = Math.max(maxLat, p.lat);
    minLng = Math.min(minLng, p.lng);
    maxLng = Math.max(maxLng, p.lng);
  }
  const latSpan = Math.max(0.05, maxLat - minLat);
  const lngSpan = Math.max(0.05, maxLng - minLng);
  return {
    minLat: minLat - latSpan * pad,
    maxLat: maxLat + latSpan * pad,
    minLng: minLng - lngSpan * pad,
    maxLng: maxLng + lngSpan * pad,
  };
}

/** Bir bbox'ı verilen kutuya sığacak şekilde projeksiyon (en-boy korunur). */
export function projectInBounds(
  p: GeoPoint,
  bbox: BBox,
  opts: ProjectOptions,
) {
  const latSpan = bbox.maxLat - bbox.minLat || 1;
  const lngSpan = bbox.maxLng - bbox.minLng || 1;
  const x = ((p.lng - bbox.minLng) / lngSpan) * opts.width;
  const y = ((bbox.maxLat - p.lat) / latSpan) * opts.height;
  return { x, y };
}

/**
 * İki nokta arası yay kontrol noktası (basit kuadratik bezier ile "uçuş" eğrisi).
 * Projeksiyon sonrası ekran koordinatlarıyla kullanılır.
 */
export function arcControlPoint(
  x1: number,
  y1: number,
  x2: number,
  y2: number,
  curvature = 0.22,
) {
  const mx = (x1 + x2) / 2;
  const my = (y1 + y2) / 2;
  const dx = x2 - x1;
  const dy = y2 - y1;
  const len = Math.hypot(dx, dy) || 1;
  // dik vektör yönünde yukarı doğru kavis
  const nx = -dy / len;
  const ny = dx / len;
  const lift = len * curvature;
  return { cx: mx + nx * lift, cy: my + ny * lift };
}
