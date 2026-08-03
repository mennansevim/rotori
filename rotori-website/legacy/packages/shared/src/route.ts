import type { FlightLeg, Trip, TripDestination } from './types.js';

/** Kalkış → duraklar → eve dönüş uçuş zinciri */
export function buildRouteLegs(
  originCity: string,
  originAirport: string,
  destinations: TripDestination[],
  travelStart: string,
  travelEnd: string,
): FlightLeg[] {
  const sorted = [...destinations].sort((a, b) => a.order - b.order);
  if (!originCity.trim() && sorted.length === 0) return [];

  const legs: FlightLeg[] = [
    {
      city: originCity,
      airport: originAirport,
      dateTime: `${travelStart}T10:00:00`,
    },
  ];

  for (const dest of sorted) {
    if (!dest.city.trim() && !dest.countryName.trim()) continue;
    legs.push({
      city: dest.city || dest.countryName,
      airport: dest.airport ?? '',
      dateTime: `${dest.arrivalDate}T14:00:00`,
    });
  }

  if (originCity.trim() && sorted.some((d) => d.city.trim() || d.countryName.trim())) {
    legs.push({
      city: originCity,
      airport: originAirport,
      dateTime: `${travelEnd}T20:00:00`,
    });
  }

  return legs;
}

/** Eski outbound/return veya yeni legs alanından tam zincir */
export function getRouteLegs(trip: Trip): FlightLeg[] {
  if (trip.flights.legs?.length) return trip.flights.legs;

  const ob = trip.flights.outbound.filter((f) => f.city.trim() || f.airport.trim());
  const ret = trip.flights.return.filter((f) => f.city.trim() || f.airport.trim());
  if (!ob.length) return [];

  const chain = [...ob];
  if (ret.length) {
    const last = chain[chain.length - 1];
    const firstRet = ret[0];
    const samePlace =
      last.city === firstRet.city &&
      (last.airport === firstRet.airport || !firstRet.airport || !last.airport);
    chain.push(...(samePlace ? ret.slice(1) : ret));
  }
  return chain;
}

export function formatRouteChain(legs: FlightLeg[]): string {
  return legs
    .map((l) => {
      if (l.city && l.airport) return `${l.city} (${l.airport})`;
      return l.city || l.airport || '—';
    })
    .join(' → ');
}
