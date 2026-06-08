export interface GeoPoint {
  lat: number;
  lng: number;
}

export interface Airport extends GeoPoint {
  iata: string;
  city: string;
  countryCode: string;
  countryName: string;
}

export interface CityInfo extends GeoPoint {
  id: string;
  name: string;
  countryCode: string;
}
