export interface Geofence {
  id: string;
  name: string;
  city: string;
  lat: number;
  lng: number;
  radiusMeters: number;
  minDwellSeconds: number;
  xp: number;
  emoji: string;
  /** Stylized map coords in viewBox 0..600 x 0..360. */
  mapX: number;
  mapY: number;
}

export interface VisitRecord {
  geofenceId: string;
  totalDwellSeconds: number;
  firstSeenAt?: string;
  completedAt?: string;
}

export interface VisitState {
  records: Record<string, VisitRecord>;
}

export const DEFAULT_MIN_DWELL = 600;

/**
 * Mesafe (metre) — Haversine. Geofence kontrolü için yeterli hassasiyette.
 */
export function distanceMeters(
  a: { lat: number; lng: number },
  b: { lat: number; lng: number },
): number {
  const R = 6371000;
  const toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);
  const lat1 = toRad(a.lat);
  const lat2 = toRad(b.lat);
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}

/** Tohum POI listesi — kullanıcı doğrulanmış konum ziyaret edince rozet kazanır. */
export const POPULAR_GEOFENCES: Geofence[] = [
  {
    id: 'tokyo-skytree',
    name: 'Tokyo Skytree',
    city: 'Tokyo',
    lat: 35.7101,
    lng: 139.8107,
    radiusMeters: 120,
    minDwellSeconds: DEFAULT_MIN_DWELL,
    xp: 60,
    emoji: '🗼',
    mapX: 444,
    mapY: 346,
  },
  {
    id: 'fushimi-inari',
    name: 'Fushimi Inari',
    city: 'Kyoto',
    lat: 34.9671,
    lng: 135.7727,
    radiusMeters: 150,
    minDwellSeconds: DEFAULT_MIN_DWELL,
    xp: 60,
    emoji: '⛩️',
    mapX: 343,
    mapY: 369,
  },
  {
    id: 'dotonbori',
    name: 'Dotonbori',
    city: 'Osaka',
    lat: 34.6687,
    lng: 135.5031,
    radiusMeters: 150,
    minDwellSeconds: DEFAULT_MIN_DWELL,
    xp: 50,
    emoji: '🍜',
    mapX: 336,
    mapY: 378,
  },
  {
    id: 'nara-park',
    name: 'Nara geyikleri',
    city: 'Nara',
    lat: 34.6851,
    lng: 135.843,
    radiusMeters: 200,
    minDwellSeconds: DEFAULT_MIN_DWELL,
    xp: 50,
    emoji: '🦌',
    mapX: 345,
    mapY: 378,
  },
  {
    id: 'teamlab-borderless',
    name: 'teamLab Planets',
    city: 'Tokyo',
    lat: 35.6486,
    lng: 139.7869,
    radiusMeters: 80,
    minDwellSeconds: DEFAULT_MIN_DWELL,
    xp: 70,
    emoji: '✨',
    mapX: 443,
    mapY: 348,
  },
  {
    id: 'usj',
    name: 'Universal Studios Japan',
    city: 'Osaka',
    lat: 34.6654,
    lng: 135.4323,
    radiusMeters: 250,
    minDwellSeconds: DEFAULT_MIN_DWELL,
    xp: 80,
    emoji: '🎢',
    mapX: 335,
    mapY: 378,
  },
  {
    id: 'itsukushima',
    name: 'Itsukushima Torii',
    city: 'Hiroshima',
    lat: 34.2959,
    lng: 132.3199,
    radiusMeters: 150,
    minDwellSeconds: DEFAULT_MIN_DWELL,
    xp: 70,
    emoji: '⛩️',
    mapX: 257,
    mapY: 389,
  },
  {
    id: 'hiroshima-peace',
    name: 'Hiroşima Barış Parkı',
    city: 'Hiroshima',
    lat: 34.3955,
    lng: 132.4536,
    radiusMeters: 120,
    minDwellSeconds: DEFAULT_MIN_DWELL,
    xp: 60,
    emoji: '🕊️',
    mapX: 260,
    mapY: 386,
  },
  {
    id: 'kanazawa-kenrokuen',
    name: 'Kenroku-en',
    city: 'Kanazawa',
    lat: 36.5621,
    lng: 136.6624,
    radiusMeters: 120,
    minDwellSeconds: DEFAULT_MIN_DWELL,
    xp: 50,
    emoji: '🌸',
    mapX: 365,
    mapY: 320,
  },
  {
    id: 'sapporo-odori',
    name: 'Sapporo Odori',
    city: 'Sapporo',
    lat: 43.0606,
    lng: 141.3543,
    radiusMeters: 200,
    minDwellSeconds: DEFAULT_MIN_DWELL,
    xp: 60,
    emoji: '🌨️',
    mapX: 482,
    mapY: 109,
  },
  {
    id: 'okinawa-naha',
    name: 'Naha Kokusai',
    city: 'Naha',
    lat: 26.215,
    lng: 127.6792,
    radiusMeters: 200,
    minDwellSeconds: DEFAULT_MIN_DWELL,
    xp: 60,
    emoji: '🌊',
    mapX: 98,
    mapY: 524,
  },
  {
    id: 'kagoshima-sakurajima',
    name: 'Sakurajima',
    city: 'Kagoshima',
    lat: 31.5938,
    lng: 130.6571,
    radiusMeters: 300,
    minDwellSeconds: DEFAULT_MIN_DWELL,
    xp: 60,
    emoji: '🌋',
    mapX: 215,
    mapY: 470,
  },
];
