import type { Airport } from './types.js';

/** Büyük uluslararası havaalanları — offline arama için. */
export const AIRPORTS: Airport[] = [
  // Türkiye
  { iata: 'IST', city: 'İstanbul', countryCode: 'TR', countryName: 'Türkiye', lat: 41.2753, lng: 28.7519 },
  { iata: 'SAW', city: 'İstanbul (Sabiha)', countryCode: 'TR', countryName: 'Türkiye', lat: 40.8986, lng: 29.3092 },
  { iata: 'ESB', city: 'Ankara', countryCode: 'TR', countryName: 'Türkiye', lat: 40.1281, lng: 32.9951 },
  { iata: 'ADB', city: 'İzmir', countryCode: 'TR', countryName: 'Türkiye', lat: 38.2924, lng: 27.157 },
  { iata: 'AYT', city: 'Antalya', countryCode: 'TR', countryName: 'Türkiye', lat: 36.8987, lng: 30.8005 },
  // Japonya
  { iata: 'HND', city: 'Tokyo (Haneda)', countryCode: 'JP', countryName: 'Japonya', lat: 35.5494, lng: 139.7798 },
  { iata: 'NRT', city: 'Tokyo (Narita)', countryCode: 'JP', countryName: 'Japonya', lat: 35.772, lng: 140.3929 },
  { iata: 'KIX', city: 'Osaka (Kansai)', countryCode: 'JP', countryName: 'Japonya', lat: 34.4347, lng: 135.244 },
  { iata: 'ITM', city: 'Osaka (Itami)', countryCode: 'JP', countryName: 'Japonya', lat: 34.7855, lng: 135.4382 },
  { iata: 'CTS', city: 'Sapporo', countryCode: 'JP', countryName: 'Japonya', lat: 42.7752, lng: 141.6923 },
  { iata: 'FUK', city: 'Fukuoka', countryCode: 'JP', countryName: 'Japonya', lat: 33.5859, lng: 130.451 },
  { iata: 'OKA', city: 'Okinawa', countryCode: 'JP', countryName: 'Japonya', lat: 26.1958, lng: 127.646 },
  // Güney Kore
  { iata: 'ICN', city: 'Seul (Incheon)', countryCode: 'KR', countryName: 'Güney Kore', lat: 37.4602, lng: 126.4407 },
  { iata: 'GMP', city: 'Seul (Gimpo)', countryCode: 'KR', countryName: 'Güney Kore', lat: 37.5583, lng: 126.7906 },
  { iata: 'PUS', city: 'Busan', countryCode: 'KR', countryName: 'Güney Kore', lat: 35.1795, lng: 128.9382 },
  { iata: 'CJU', city: 'Jeju', countryCode: 'KR', countryName: 'Güney Kore', lat: 33.5113, lng: 126.4929 },
  // Tayvan
  { iata: 'TPE', city: 'Taipei (Taoyuan)', countryCode: 'TW', countryName: 'Tayvan', lat: 25.0777, lng: 121.2328 },
  { iata: 'TSA', city: 'Taipei (Songshan)', countryCode: 'TW', countryName: 'Tayvan', lat: 25.0694, lng: 121.5519 },
  { iata: 'KHH', city: 'Kaohsiung', countryCode: 'TW', countryName: 'Tayvan', lat: 22.5771, lng: 120.3499 },
  // Tayland
  { iata: 'BKK', city: 'Bangkok (Suvarnabhumi)', countryCode: 'TH', countryName: 'Tayland', lat: 13.69, lng: 100.7501 },
  { iata: 'DMK', city: 'Bangkok (Don Mueang)', countryCode: 'TH', countryName: 'Tayland', lat: 13.9126, lng: 100.6068 },
  { iata: 'HKT', city: 'Phuket', countryCode: 'TH', countryName: 'Tayland', lat: 8.1132, lng: 98.3169 },
  { iata: 'CNX', city: 'Chiang Mai', countryCode: 'TH', countryName: 'Tayland', lat: 18.7668, lng: 98.9626 },
  // BAE / Orta Doğu
  { iata: 'DXB', city: 'Dubai', countryCode: 'AE', countryName: 'BAE', lat: 25.2532, lng: 55.3657 },
  { iata: 'AUH', city: 'Abu Dabi', countryCode: 'AE', countryName: 'BAE', lat: 24.433, lng: 54.6511 },
  { iata: 'DOH', city: 'Doha', countryCode: 'QA', countryName: 'Katar', lat: 25.2731, lng: 51.608 },
  // Fransa
  { iata: 'CDG', city: 'Paris (Charles de Gaulle)', countryCode: 'FR', countryName: 'Fransa', lat: 49.0097, lng: 2.5479 },
  { iata: 'ORY', city: 'Paris (Orly)', countryCode: 'FR', countryName: 'Fransa', lat: 48.7233, lng: 2.3794 },
  { iata: 'NCE', city: 'Nice', countryCode: 'FR', countryName: 'Fransa', lat: 43.6584, lng: 7.2159 },
  // İtalya
  { iata: 'FCO', city: 'Roma (Fiumicino)', countryCode: 'IT', countryName: 'İtalya', lat: 41.8003, lng: 12.2389 },
  { iata: 'MXP', city: 'Milano (Malpensa)', countryCode: 'IT', countryName: 'İtalya', lat: 45.6306, lng: 8.7281 },
  { iata: 'VCE', city: 'Venedik', countryCode: 'IT', countryName: 'İtalya', lat: 45.5053, lng: 12.3519 },
  // İspanya
  { iata: 'BCN', city: 'Barselona', countryCode: 'ES', countryName: 'İspanya', lat: 41.2974, lng: 2.0833 },
  { iata: 'MAD', city: 'Madrid', countryCode: 'ES', countryName: 'İspanya', lat: 40.4983, lng: -3.5676 },
  // İngiltere
  { iata: 'LHR', city: 'Londra (Heathrow)', countryCode: 'GB', countryName: 'İngiltere', lat: 51.47, lng: -0.4543 },
  { iata: 'LGW', city: 'Londra (Gatwick)', countryCode: 'GB', countryName: 'İngiltere', lat: 51.1537, lng: -0.1821 },
  // Almanya
  { iata: 'FRA', city: 'Frankfurt', countryCode: 'DE', countryName: 'Almanya', lat: 50.0379, lng: 8.5622 },
  { iata: 'MUC', city: 'Münih', countryCode: 'DE', countryName: 'Almanya', lat: 48.3537, lng: 11.775 },
  { iata: 'BER', city: 'Berlin', countryCode: 'DE', countryName: 'Almanya', lat: 52.3667, lng: 13.5033 },
  // Hollanda / diğer Avrupa hub
  { iata: 'AMS', city: 'Amsterdam', countryCode: 'NL', countryName: 'Hollanda', lat: 52.3105, lng: 4.7683 },
  // Yunanistan
  { iata: 'ATH', city: 'Atina', countryCode: 'GR', countryName: 'Yunanistan', lat: 37.9364, lng: 23.9445 },
  // ABD
  { iata: 'JFK', city: 'New York (JFK)', countryCode: 'US', countryName: 'Amerika', lat: 40.6413, lng: -73.7781 },
  { iata: 'LAX', city: 'Los Angeles', countryCode: 'US', countryName: 'Amerika', lat: 33.9416, lng: -118.4085 },
  { iata: 'SFO', city: 'San Francisco', countryCode: 'US', countryName: 'Amerika', lat: 37.6213, lng: -122.379 },
  { iata: 'ORD', city: 'Chicago', countryCode: 'US', countryName: 'Amerika', lat: 41.9742, lng: -87.9073 },
  // Singapur / Hong Kong / Çin
  { iata: 'SIN', city: 'Singapur', countryCode: 'SG', countryName: 'Singapur', lat: 1.3644, lng: 103.9915 },
  { iata: 'HKG', city: 'Hong Kong', countryCode: 'HK', countryName: 'Hong Kong', lat: 22.308, lng: 113.9185 },
  { iata: 'PEK', city: 'Pekin', countryCode: 'CN', countryName: 'Çin', lat: 40.0799, lng: 116.6031 },
  { iata: 'PVG', city: 'Şanghay', countryCode: 'CN', countryName: 'Çin', lat: 31.1443, lng: 121.8083 },
];

const BY_IATA = new Map(AIRPORTS.map((a) => [a.iata, a]));

export function getAirport(iata: string): Airport | undefined {
  return BY_IATA.get(iata.toUpperCase());
}

export function searchAirports(
  query: string,
  limit = 8,
  countryCodes?: string[],
): Airport[] {
  const filter = countryCodes && countryCodes.length > 0 ? new Set(countryCodes) : null;
  const pool = filter ? AIRPORTS.filter((a) => filter.has(a.countryCode)) : AIRPORTS;
  const q = query.trim().toLowerCase();
  if (!q) return pool.slice(0, limit);
  const scored = pool.map((a) => {
    const iata = a.iata.toLowerCase();
    const city = a.city.toLowerCase();
    const country = a.countryName.toLowerCase();
    let score = -1;
    if (iata === q) score = 100;
    else if (iata.startsWith(q)) score = 90;
    else if (city.startsWith(q)) score = 80;
    else if (city.includes(q)) score = 60;
    else if (country.startsWith(q)) score = 50;
    else if (country.includes(q)) score = 40;
    return { a, score };
  }).filter((s) => s.score >= 0);
  scored.sort((x, y) => y.score - x.score);
  return scored.slice(0, limit).map((s) => s.a);
}

export function formatAirport(a: Airport): string {
  return `${a.city} · ${a.iata}`;
}
