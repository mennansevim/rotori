/**
 * Open-Meteo entegrasyonu — anahtar gerekmez.
 * https://open-meteo.com/en/docs
 *
 * Şehir/gün için günlük max sıcaklık, yağış olasılığı ve weather code döner.
 */

const CACHE = new Map<string, { ts: number; data: DayWeather[] }>();
const CACHE_TTL_MS = 30 * 60_000; // 30 dk

export interface DayWeather {
  date: string;
  /** WMO weather code (0=clear, 51-67=rain, 71-77=snow, 95+=thunder) */
  code: number;
  tMin: number;
  tMax: number;
  /** % yağış olasılığı */
  precipProb?: number;
  precipMm?: number;
}

export interface WeatherLabel {
  emoji: string;
  label: string;
  isWet: boolean;
  isHot: boolean;
}

const WMO_LABEL: Record<number, WeatherLabel> = {
  0: { emoji: '☀️', label: 'Açık', isWet: false, isHot: false },
  1: { emoji: '🌤️', label: 'Az bulutlu', isWet: false, isHot: false },
  2: { emoji: '⛅', label: 'Parçalı bulutlu', isWet: false, isHot: false },
  3: { emoji: '☁️', label: 'Bulutlu', isWet: false, isHot: false },
  45: { emoji: '🌫️', label: 'Sis', isWet: false, isHot: false },
  48: { emoji: '🌫️', label: 'Yoğun sis', isWet: false, isHot: false },
  51: { emoji: '🌦️', label: 'Çiseleme', isWet: true, isHot: false },
  53: { emoji: '🌦️', label: 'Çiseleme', isWet: true, isHot: false },
  55: { emoji: '🌧️', label: 'Yoğun çiseleme', isWet: true, isHot: false },
  61: { emoji: '🌧️', label: 'Hafif yağmur', isWet: true, isHot: false },
  63: { emoji: '🌧️', label: 'Yağmur', isWet: true, isHot: false },
  65: { emoji: '🌧️', label: 'Şiddetli yağmur', isWet: true, isHot: false },
  71: { emoji: '🌨️', label: 'Hafif kar', isWet: true, isHot: false },
  73: { emoji: '🌨️', label: 'Kar', isWet: true, isHot: false },
  75: { emoji: '❄️', label: 'Şiddetli kar', isWet: true, isHot: false },
  80: { emoji: '🌦️', label: 'Sağanak', isWet: true, isHot: false },
  81: { emoji: '🌧️', label: 'Sağanak', isWet: true, isHot: false },
  82: { emoji: '⛈️', label: 'Şiddetli sağanak', isWet: true, isHot: false },
  95: { emoji: '⛈️', label: 'Gök gürültülü', isWet: true, isHot: false },
  96: { emoji: '⛈️', label: 'Gök gürültülü', isWet: true, isHot: false },
  99: { emoji: '⛈️', label: 'Şiddetli fırtına', isWet: true, isHot: false },
};

export function labelForCode(code: number, tMax: number): WeatherLabel {
  const base = WMO_LABEL[code] ?? {
    emoji: '🌥️',
    label: 'Karışık',
    isWet: false,
    isHot: false,
  };
  return { ...base, isHot: tMax >= 30 };
}

export async function fetchDailyWeather(
  lat: number,
  lng: number,
  startDate: string,
  endDate: string,
): Promise<DayWeather[]> {
  const key = `${lat.toFixed(3)},${lng.toFixed(3)}:${startDate}:${endDate}`;
  const cached = CACHE.get(key);
  if (cached && Date.now() - cached.ts < CACHE_TTL_MS) return cached.data;

  const url = new URL('https://api.open-meteo.com/v1/forecast');
  url.searchParams.set('latitude', String(lat));
  url.searchParams.set('longitude', String(lng));
  url.searchParams.set('daily', 'weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,precipitation_sum');
  url.searchParams.set('timezone', 'Asia/Tokyo');
  url.searchParams.set('start_date', startDate);
  url.searchParams.set('end_date', endDate);

  const resp = await fetch(url.toString());
  if (!resp.ok) return [];
  const data = await resp.json();
  const times: string[] = data?.daily?.time ?? [];
  const codes: number[] = data?.daily?.weather_code ?? [];
  const maxT: number[] = data?.daily?.temperature_2m_max ?? [];
  const minT: number[] = data?.daily?.temperature_2m_min ?? [];
  const prob: number[] = data?.daily?.precipitation_probability_max ?? [];
  const sum: number[] = data?.daily?.precipitation_sum ?? [];

  const out: DayWeather[] = times.map((date, i) => ({
    date,
    code: codes[i] ?? 0,
    tMax: maxT[i] ?? 0,
    tMin: minT[i] ?? 0,
    precipProb: prob[i],
    precipMm: sum[i],
  }));
  CACHE.set(key, { ts: Date.now(), data: out });
  return out;
}

/** Hava bilgisini AI'ya gönderilecek kısa Türkçe stringe çevirir. */
export function formatWeatherForAi(w: DayWeather): string {
  const lbl = labelForCode(w.code, w.tMax);
  const tempPart = `${Math.round(w.tMin)}–${Math.round(w.tMax)}°C`;
  const rainPart =
    w.precipProb != null && w.precipProb >= 40
      ? `, ${w.precipProb}% yağış ihtimali`
      : '';
  return `${lbl.label} ${tempPart}${rainPart}`;
}
