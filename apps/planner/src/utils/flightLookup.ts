import { getAirport, airlineIcao, type Airport } from '@japan-trip/shared';

export interface FlightEndpoint {
  iata: string;
  city?: string;
  countryCode?: string;
  countryName?: string;
  lat?: number;
  lng?: number;
}

export interface FlightLookupResult {
  departure?: FlightEndpoint;
  arrival?: FlightEndpoint;
  departureTime?: string;
  arrivalTime?: string;
  departureDate?: string;
}

export class FlightLookupNotConfigured extends Error {
  constructor() {
    super('flight-lookup-not-configured');
    this.name = 'FlightLookupNotConfigured';
  }
}

/** Anahtarsız ücretsiz yedek: uçuşu web'de aratan bağlantı (Google). */
export function flightSearchUrl(airline: string, flightNo: string, date?: string): string {
  const num = `${airline}${flightNo}`.replace(/\s+/g, '').toUpperCase();
  const q = `${num} uçuş${date ? ` ${date}` : ''} rota havaalanı`;
  return `https://www.google.com/search?q=${encodeURIComponent(q)}`;
}

/** Flightradar24 uçuş sayfası (rota/saat için iyi, ücretsiz görüntüleme). */
export function flightradarUrl(airline: string, flightNo: string): string {
  const num = `${airline}${flightNo}`.replace(/\s+/g, '').toLowerCase();
  return `https://www.flightradar24.com/data/flights/${num}`;
}

/** Bizim havaalanı veritabanımızla zenginleştirilmiş Airport nesnesi üretir. */
export function toAirport(ep: FlightEndpoint): Airport {
  const known = getAirport(ep.iata);
  return {
    iata: ep.iata,
    city: ep.city ?? known?.city ?? ep.iata,
    countryCode: ep.countryCode ?? known?.countryCode ?? '',
    countryName: ep.countryName ?? known?.countryName ?? ep.countryCode ?? '',
    lat: ep.lat ?? known?.lat ?? 0,
    lng: ep.lng ?? known?.lng ?? 0,
  };
}

/**
 * Uçuş numarası + tarih ile rotayı internetten getirir.
 * Sunucu tarafı proxy (`/api/flight`) üzerinden çalışır; anahtar sunucuda saklanır.
 * Yapılandırılmamışsa FlightLookupNotConfigured fırlatır.
 */
export async function lookupFlight(
  airline: string,
  flightNo: string,
  date: string,
): Promise<FlightLookupResult | null> {
  const number = `${airline}${flightNo}`.replace(/\s+/g, '').toUpperCase();
  const icao = airlineIcao(airline);
  const callsign = icao ? `${icao}${flightNo}`.replace(/\s+/g, '').toUpperCase() : '';
  const url =
    `/api/flight?number=${encodeURIComponent(number)}&date=${encodeURIComponent(date)}` +
    (callsign ? `&callsign=${encodeURIComponent(callsign)}` : '');

  let resp: Response;
  try {
    resp = await fetch(url, { headers: { accept: 'application/json' } });
  } catch {
    throw new Error('network');
  }

  if (resp.status === 404) return null;
  if (resp.status === 501) throw new FlightLookupNotConfigured();
  if (!resp.ok) throw new Error(`http-${resp.status}`);

  const data = (await resp.json()) as FlightLookupResult | { error?: string };
  if (data && 'error' in data && data.error) {
    if (data.error === 'not-configured') throw new FlightLookupNotConfigured();
    return null;
  }
  const result = data as FlightLookupResult;
  if (!result.departure && !result.arrival) return null;
  return result;
}
