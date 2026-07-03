// Rota şehirlerinin "iç haritası" için küratörlü popüler nokta listesi.
// Koordinatlar yaklaşık gerçek lat/lng — mini-krokide göreli konumlandırma için kullanılır.
import { DEFAULT_MIN_DWELL, type Geofence, type Trip } from '@japan-trip/shared';

/** Geofence yarıçapı (m) — nokta merkezli ziyaret algılama. */
const PLACE_RADIUS_M = 120;
/** Bir noktada kazanılan XP. */
const PLACE_XP = 25;

export interface CityPlace {
  id: string;
  name: string;
  emoji: string;
  /** Kısa kategori etiketi (görsel ipucu). */
  category: string;
  lat: number;
  lng: number;
}

export interface CityData {
  /** Eşleştirme anahtarı (ör. "tokyo"). */
  key: string;
  label: string;
  emoji: string;
  /** trip içinde bu şehri yakalamak için aranan küçük-harf takma adlar. */
  aliases: string[];
  places: CityPlace[];
}

export const CITY_DATA: CityData[] = [
  {
    key: 'tokyo',
    label: 'Tokyo',
    emoji: '🗼',
    aliases: ['tokyo', 'tokio'],
    places: [
      { id: 'tk-skytree', name: 'Tokyo Skytree', emoji: '🗼', category: 'Manzara', lat: 35.7101, lng: 139.8107 },
      { id: 'tk-sensoji', name: 'Senso-ji (Asakusa)', emoji: '⛩️', category: 'Tapınak', lat: 35.7148, lng: 139.7967 },
      { id: 'tk-shibuya', name: 'Shibuya Crossing', emoji: '🚥', category: 'Şehir', lat: 35.6595, lng: 139.7005 },
      { id: 'tk-meiji', name: 'Meiji Jingu', emoji: '🌳', category: 'Tapınak', lat: 35.6764, lng: 139.6993 },
      { id: 'tk-teamlab', name: 'teamLab Planets', emoji: '✨', category: 'Müze', lat: 35.6486, lng: 139.7869 },
      { id: 'tk-shinjuku-gyoen', name: 'Shinjuku Gyoen', emoji: '🌸', category: 'Park', lat: 35.6852, lng: 139.71 },
      { id: 'tk-akihabara', name: 'Akihabara', emoji: '🎮', category: 'Alışveriş', lat: 35.7022, lng: 139.7745 },
      { id: 'tk-tower', name: 'Tokyo Tower', emoji: '🗼', category: 'Manzara', lat: 35.6586, lng: 139.7454 },
      { id: 'tk-ueno', name: 'Ueno Park', emoji: '🦖', category: 'Park', lat: 35.7156, lng: 139.7745 },
      { id: 'tk-ginza', name: 'Ginza', emoji: '🛍️', category: 'Alışveriş', lat: 35.6717, lng: 139.765 },
      { id: 'tk-tsukiji', name: 'Tsukiji Pazarı', emoji: '🍣', category: 'Yemek', lat: 35.6655, lng: 139.7707 },
      { id: 'tk-odaiba', name: 'Odaiba', emoji: '🎡', category: 'Eğlence', lat: 35.6276, lng: 139.7763 },
    ],
  },
  {
    key: 'kyoto',
    label: 'Kyoto',
    emoji: '⛩️',
    aliases: ['kyoto', 'kioto'],
    places: [
      { id: 'ky-fushimi', name: 'Fushimi Inari', emoji: '⛩️', category: 'Tapınak', lat: 34.9671, lng: 135.7727 },
      { id: 'ky-kinkakuji', name: 'Kinkaku-ji', emoji: '🏯', category: 'Tapınak', lat: 35.0394, lng: 135.7292 },
      { id: 'ky-arashiyama', name: 'Arashiyama Bambu', emoji: '🎋', category: 'Doğa', lat: 35.017, lng: 135.6716 },
      { id: 'ky-kiyomizu', name: 'Kiyomizu-dera', emoji: '🛕', category: 'Tapınak', lat: 34.9948, lng: 135.785 },
      { id: 'ky-gion', name: 'Gion', emoji: '🎎', category: 'Tarihi', lat: 35.0036, lng: 135.7752 },
      { id: 'ky-nijo', name: 'Nijo Kalesi', emoji: '🏯', category: 'Kale', lat: 35.0142, lng: 135.7483 },
      { id: 'ky-ginkakuji', name: 'Ginkaku-ji', emoji: '🏯', category: 'Tapınak', lat: 35.027, lng: 135.7982 },
      { id: 'ky-pontocho', name: 'Pontocho', emoji: '🏮', category: 'Yemek', lat: 35.005, lng: 135.7708 },
      { id: 'ky-nishiki', name: 'Nishiki Pazarı', emoji: '🍡', category: 'Yemek', lat: 35.005, lng: 135.7649 },
      { id: 'ky-tofukuji', name: 'Tofuku-ji', emoji: '🍁', category: 'Tapınak', lat: 34.9766, lng: 135.774 },
    ],
  },
  {
    key: 'osaka',
    label: 'Osaka',
    emoji: '🍜',
    aliases: ['osaka', 'ōsaka'],
    places: [
      { id: 'os-dotonbori', name: 'Dotonbori', emoji: '🍜', category: 'Yemek', lat: 34.6687, lng: 135.5031 },
      { id: 'os-castle', name: 'Osaka Kalesi', emoji: '🏯', category: 'Kale', lat: 34.6873, lng: 135.5259 },
      { id: 'os-usj', name: 'Universal Studios', emoji: '🎢', category: 'Eğlence', lat: 34.6654, lng: 135.4323 },
      { id: 'os-shinsekai', name: 'Shinsekai · Tsutenkaku', emoji: '🗼', category: 'Şehir', lat: 34.6525, lng: 135.5063 },
      { id: 'os-umeda', name: 'Umeda Sky Building', emoji: '🌆', category: 'Manzara', lat: 34.7054, lng: 135.4902 },
      { id: 'os-kuromon', name: 'Kuromon Pazarı', emoji: '🐟', category: 'Yemek', lat: 34.6657, lng: 135.506 },
      { id: 'os-namba', name: 'Namba', emoji: '🛍️', category: 'Alışveriş', lat: 34.6627, lng: 135.5023 },
      { id: 'os-sumiyoshi', name: 'Sumiyoshi Taisha', emoji: '⛩️', category: 'Tapınak', lat: 34.6126, lng: 135.4933 },
      { id: 'os-harukas', name: 'Abeno Harukas', emoji: '🏙️', category: 'Manzara', lat: 34.6456, lng: 135.5136 },
      { id: 'os-shitennoji', name: 'Shitenno-ji', emoji: '🛕', category: 'Tapınak', lat: 34.6543, lng: 135.5165 },
    ],
  },
  {
    key: 'nara',
    label: 'Nara',
    emoji: '🦌',
    aliases: ['nara'],
    places: [
      { id: 'nr-park', name: 'Nara Parkı (geyikler)', emoji: '🦌', category: 'Park', lat: 34.6851, lng: 135.843 },
      { id: 'nr-todaiji', name: 'Todai-ji', emoji: '🛕', category: 'Tapınak', lat: 34.689, lng: 135.8398 },
      { id: 'nr-kasuga', name: 'Kasuga Taisha', emoji: '🏮', category: 'Tapınak', lat: 34.6818, lng: 135.8483 },
      { id: 'nr-kofukuji', name: 'Kofuku-ji', emoji: '🗼', category: 'Tapınak', lat: 34.6833, lng: 135.8327 },
      { id: 'nr-isuien', name: 'Isuien Bahçesi', emoji: '🌳', category: 'Bahçe', lat: 34.6868, lng: 135.8366 },
      { id: 'nr-naramachi', name: 'Naramachi', emoji: '🏘️', category: 'Tarihi', lat: 34.6786, lng: 135.8295 },
    ],
  },
  {
    key: 'hiroshima',
    label: 'Hiroshima',
    emoji: '🕊️',
    aliases: ['hiroshima', 'miyajima'],
    places: [
      { id: 'hr-peace', name: 'Barış Anıtı Parkı', emoji: '🕊️', category: 'Anıt', lat: 34.3955, lng: 132.4536 },
      { id: 'hr-dome', name: 'Atom Bombası Kubbesi', emoji: '🏛️', category: 'Anıt', lat: 34.3955, lng: 132.4537 },
      { id: 'hr-miyajima', name: 'Itsukushima (Miyajima)', emoji: '⛩️', category: 'Tapınak', lat: 34.296, lng: 132.3197 },
      { id: 'hr-castle', name: 'Hiroshima Kalesi', emoji: '🏯', category: 'Kale', lat: 34.4026, lng: 132.4593 },
      { id: 'hr-shukkeien', name: 'Shukkeien Bahçesi', emoji: '🌳', category: 'Bahçe', lat: 34.4019, lng: 132.4664 },
    ],
  },
  {
    key: 'sapporo',
    label: 'Sapporo',
    emoji: '❄️',
    aliases: ['sapporo', 'hokkaido', 'hokkaıdo'],
    places: [
      { id: 'sp-odori', name: 'Odori Parkı', emoji: '🌳', category: 'Park', lat: 43.0606, lng: 141.3565 },
      { id: 'sp-moiwa', name: 'Moiwa Dağı', emoji: '🚠', category: 'Manzara', lat: 43.0276, lng: 141.3239 },
      { id: 'sp-beer', name: 'Sapporo Bira Müzesi', emoji: '🍺', category: 'Müze', lat: 43.0707, lng: 141.3709 },
      { id: 'sp-clock', name: 'Saat Kulesi', emoji: '🕰️', category: 'Tarihi', lat: 43.0628, lng: 141.3536 },
      { id: 'sp-susukino', name: 'Susukino', emoji: '🏮', category: 'Yemek', lat: 43.0556, lng: 141.3539 },
    ],
  },
  {
    key: 'kanazawa',
    label: 'Kanazawa',
    emoji: '🌿',
    aliases: ['kanazawa'],
    places: [
      { id: 'kz-kenrokuen', name: 'Kenroku-en', emoji: '🌿', category: 'Bahçe', lat: 36.5622, lng: 136.6624 },
      { id: 'kz-castle', name: 'Kanazawa Kalesi', emoji: '🏯', category: 'Kale', lat: 36.5653, lng: 136.6592 },
      { id: 'kz-higashi', name: 'Higashi Chaya', emoji: '🏮', category: 'Tarihi', lat: 36.5719, lng: 136.6669 },
      { id: 'kz-omicho', name: 'Omicho Pazarı', emoji: '🦀', category: 'Yemek', lat: 36.5715, lng: 136.6573 },
      { id: 'kz-21c', name: '21. Yüzyıl Müzesi', emoji: '🎨', category: 'Müze', lat: 36.5606, lng: 136.6585 },
    ],
  },
];

const CITY_BY_KEY = new Map(CITY_DATA.map((c) => [c.key, c]));

/** Bir şehir anahtarı için küratörlü veri. */
export function getCityData(key: string): CityData | undefined {
  return CITY_BY_KEY.get(key);
}

/**
 * Trip içinden rota şehirlerini tespit eder. destinations/oteller/uçuş ve gün
 * temaları taranır; küratörlü veriye sahip şehirler, ilk geçtikleri güne göre
 * rota sırasıyla döner.
 */
export function getRouteCities(trip: Trip): CityData[] {
  const dayThemes = (trip.days ?? []).map((d) =>
    `${d.theme ?? ''} ${(d.items ?? [])
      .map((i) => i.title ?? '')
      .join(' ')}`.toLowerCase(),
  );
  const staticSignals = [
    ...(trip.preferences?.destinations ?? []).map((d) => d.city ?? ''),
    ...(trip.hotels ?? []).map((h) => h.city ?? ''),
    ...(trip.flights?.legs ?? []).map((f) => f.city ?? ''),
    ...(trip.flights?.outbound ?? []).map((f) => f.city ?? ''),
    ...(trip.flights?.return ?? []).map((f) => f.city ?? ''),
    trip.title ?? '',
  ]
    .join(' | ')
    .toLowerCase();

  const scored: { city: CityData; firstDay: number }[] = [];
  for (const city of CITY_DATA) {
    const matches = (text: string) => city.aliases.some((a) => text.includes(a));
    let firstDay = dayThemes.findIndex((t) => matches(t));
    const inStatic = matches(staticSignals);
    if (firstDay < 0 && inStatic) firstDay = 999; // gün bilgisi yok ama statik sinyalde geçiyor
    if (firstDay >= 0) scored.push({ city, firstDay });
  }
  scored.sort((a, b) => a.firstDay - b.firstDay);
  return scored.map((s) => s.city);
}

/**
 * Şehir noktalarını GPS geofence'lerine çevirir. Ziyaret, kullanıcının nokta
 * yarıçapında en az 10 dk (DEFAULT_MIN_DWELL) kalmasıyla otomatik tamamlanır;
 * geofence id'si CityPlace id'si ile aynıdır (UI ile eşleşsin diye).
 */
export function cityPlacesToGeofences(cities: CityData[]): Geofence[] {
  return cities.flatMap((c) =>
    c.places.map((p) => ({
      id: p.id,
      name: p.name,
      city: c.label,
      lat: p.lat,
      lng: p.lng,
      radiusMeters: PLACE_RADIUS_M,
      minDwellSeconds: DEFAULT_MIN_DWELL,
      xp: PLACE_XP,
      emoji: p.emoji,
      mapX: 0,
      mapY: 0,
    })),
  );
}
