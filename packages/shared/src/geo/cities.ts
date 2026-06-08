import type { CityInfo } from './types.js';

/** Japonya gezisinde Plan adımında seçilebilecek büyük şehirler. */
export const CITIES: CityInfo[] = [
  { id: 'jp-tokyo', name: 'Tokyo', countryCode: 'JP', lat: 35.6762, lng: 139.6503 },
  { id: 'jp-osaka', name: 'Osaka', countryCode: 'JP', lat: 34.6937, lng: 135.5023 },
  { id: 'jp-kyoto', name: 'Kyoto', countryCode: 'JP', lat: 35.0116, lng: 135.7681 },
  { id: 'jp-nara', name: 'Nara', countryCode: 'JP', lat: 34.6851, lng: 135.8048 },
  { id: 'jp-kobe', name: 'Kobe', countryCode: 'JP', lat: 34.6901, lng: 135.1955 },
  { id: 'jp-hakone', name: 'Hakone', countryCode: 'JP', lat: 35.2324, lng: 139.1069 },
  { id: 'jp-hiroshima', name: 'Hiroşima', countryCode: 'JP', lat: 34.3853, lng: 132.4553 },
  { id: 'jp-fukuoka', name: 'Fukuoka', countryCode: 'JP', lat: 33.5904, lng: 130.4017 },
  { id: 'jp-sapporo', name: 'Sapporo', countryCode: 'JP', lat: 43.0618, lng: 141.3545 },
];

export function citiesForCountry(countryCode: string): CityInfo[] {
  return CITIES.filter((c) => c.countryCode === countryCode);
}

export function getCity(id: string): CityInfo | undefined {
  return CITIES.find((c) => c.id === id);
}
