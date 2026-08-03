export interface Airline {
  /** IATA kodu (2 karakter) */
  code: string;
  name: string;
  /** Ana ülke (opsiyonel bilgi) */
  country?: string;
  /** ICAO kodu (3 karakter) — callsign tabanlı sorgular için */
  icao?: string;
}

export const AIRLINES: Airline[] = [
  { code: 'TK', name: 'Turkish Airlines', country: 'Türkiye', icao: 'THY' },
  { code: 'PC', name: 'Pegasus Airlines', country: 'Türkiye', icao: 'PGT' },
  { code: 'XQ', name: 'SunExpress', country: 'Türkiye', icao: 'SXS' },
  { code: 'JL', name: 'Japan Airlines', country: 'Japonya', icao: 'JAL' },
  { code: 'NH', name: 'ANA (All Nippon Airways)', country: 'Japonya', icao: 'ANA' },
  { code: 'KE', name: 'Korean Air', country: 'Güney Kore', icao: 'KAL' },
  { code: 'OZ', name: 'Asiana Airlines', country: 'Güney Kore', icao: 'AAR' },
  { code: 'CI', name: 'China Airlines', country: 'Tayvan', icao: 'CAL' },
  { code: 'BR', name: 'EVA Air', country: 'Tayvan', icao: 'EVA' },
  { code: 'CX', name: 'Cathay Pacific', country: 'Hong Kong', icao: 'CPA' },
  { code: 'SQ', name: 'Singapore Airlines', country: 'Singapur', icao: 'SIA' },
  { code: 'TG', name: 'Thai Airways', country: 'Tayland', icao: 'THA' },
  { code: 'QR', name: 'Qatar Airways', country: 'Katar', icao: 'QTR' },
  { code: 'EK', name: 'Emirates', country: 'BAE', icao: 'UAE' },
  { code: 'EY', name: 'Etihad Airways', country: 'BAE', icao: 'ETD' },
  { code: 'SV', name: 'Saudia', country: 'S. Arabistan', icao: 'SVA' },
  { code: 'LH', name: 'Lufthansa', country: 'Almanya', icao: 'DLH' },
  { code: 'AF', name: 'Air France', country: 'Fransa', icao: 'AFR' },
  { code: 'KL', name: 'KLM', country: 'Hollanda', icao: 'KLM' },
  { code: 'BA', name: 'British Airways', country: 'Birleşik Krallık', icao: 'BAW' },
  { code: 'IB', name: 'Iberia', country: 'İspanya', icao: 'IBE' },
  { code: 'AZ', name: 'ITA Airways', country: 'İtalya', icao: 'ITY' },
  { code: 'LX', name: 'SWISS', country: 'İsviçre', icao: 'SWR' },
  { code: 'OS', name: 'Austrian Airlines', country: 'Avusturya', icao: 'AUA' },
  { code: 'SU', name: 'Aeroflot', country: 'Rusya', icao: 'AFL' },
  { code: 'AA', name: 'American Airlines', country: 'ABD', icao: 'AAL' },
  { code: 'UA', name: 'United Airlines', country: 'ABD', icao: 'UAL' },
  { code: 'DL', name: 'Delta Air Lines', country: 'ABD', icao: 'DAL' },
  { code: 'AC', name: 'Air Canada', country: 'Kanada', icao: 'ACA' },
  { code: 'QF', name: 'Qantas', country: 'Avustralya', icao: 'QFA' },
  { code: 'CA', name: 'Air China', country: 'Çin', icao: 'CCA' },
  { code: 'MU', name: 'China Eastern', country: 'Çin', icao: 'CES' },
  { code: 'CZ', name: 'China Southern', country: 'Çin', icao: 'CSN' },
  { code: 'FZ', name: 'flydubai', country: 'BAE', icao: 'FDB' },
  { code: 'W6', name: 'Wizz Air', country: 'Macaristan', icao: 'WZZ' },
  { code: 'FR', name: 'Ryanair', country: 'İrlanda', icao: 'RYR' },
  { code: 'U2', name: 'easyJet', country: 'Birleşik Krallık', icao: 'EZY' },
];

export function searchAirlines(query: string, limit = 8): Airline[] {
  const q = query.trim().toLowerCase();
  if (!q) return AIRLINES.slice(0, limit);
  const scored = AIRLINES.map((a) => {
    const name = a.name.toLowerCase();
    const code = a.code.toLowerCase();
    let score = -1;
    if (code === q) score = 0;
    else if (name.startsWith(q)) score = 1;
    else if (code.startsWith(q)) score = 2;
    else if (name.includes(q)) score = 3;
    return { a, score };
  }).filter((x) => x.score >= 0);
  scored.sort((x, y) => x.score - y.score);
  return scored.slice(0, limit).map((x) => x.a);
}

export function getAirline(code: string): Airline | undefined {
  return AIRLINES.find((a) => a.code.toUpperCase() === code.toUpperCase());
}

export function airlineLabel(code?: string): string {
  if (!code) return '';
  return getAirline(code)?.name ?? code;
}

/** IATA kodundan ICAO kodu (callsign için). Bilinmiyorsa undefined. */
export function airlineIcao(code?: string): string | undefined {
  if (!code) return undefined;
  return getAirline(code)?.icao;
}
