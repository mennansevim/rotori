import { buildRouteLegs } from '../route.js';
import { generateDaysBetween } from '../tripFactory.js';
import { getDestinationProfile } from './profiles.js';
import type { DestinationFoodPrefs, Trip, TripDestination } from '../types.js';

export function newDestinationId() {
  return `dest-${Date.now().toString(36)}`;
}

export function defaultFoodPrefsForDestination(
  dest: TripDestination,
): DestinationFoodPrefs {
  const profile = getDestinationProfile(dest.countryCode);
  return {
    destinationId: dest.id,
    dietaryTags: [],
    foodLikes: [],
    foodDislikes: [],
    mealBudgetPerPerson: profile?.code === 'JP' ? 2500 : profile?.code === 'KR' ? 15000 : 50,
    mealBudgetCurrency: profile?.defaultCurrency ?? 'EUR',
  };
}

export function buildTripTitleFromDestinations(
  originCity: string,
  destinations: TripDestination[],
): string {
  const stops = destinations
    .sort((a, b) => a.order - b.order)
    .map((d) => d.city || d.countryName)
    .filter(Boolean);
  if (!originCity && !stops.length) return 'Yeni seyahat';
  if (!stops.length) return originCity;
  if (!originCity) return stops.join(' → ');
  return `${originCity} → ${stops.join(' → ')} → ${originCity}`;
}

/** Eski tek destinasyon alanlarından diziye geçir */
export function ensureTripDestinations(trip: Trip): Trip {
  if (trip.preferences.destinations?.length) {
    const food = trip.preferences.destinationFood ?? [];
    const patchedFood = trip.preferences.destinations.map((d) => {
      if (food.some((f) => f.destinationId === d.id)) return food;
      return [...food, defaultFoodPrefsForDestination(d)];
    });
    return {
      ...trip,
      preferences: {
        ...trip.preferences,
        destinationFood: patchedFood.flat().filter(
          (f, i, arr) => arr.findIndex((x) => x.destinationId === f.destinationId) === i,
        ),
      },
    };
  }

  const start = trip.preferences.travelDates.start;
  const end = trip.preferences.travelDates.end;
  const city = trip.preferences.destinationCity ?? trip.flights.outbound[1]?.city ?? '';
  const country = trip.preferences.destinationCountry ?? '';

  if (!city && !country) {
    return {
      ...trip,
      preferences: {
        ...trip.preferences,
        destinations: [],
        destinationFood: [],
      },
    };
  }

  const profile = country ? getDestinationProfile(country) : null;
  const dest: TripDestination = {
    id: newDestinationId(),
    countryCode: country,
    countryName: profile?.name ?? country,
    city,
    airport: trip.flights.outbound[1]?.airport,
    arrivalDate: start,
    departureDate: end,
    order: 0,
  };

  return syncTripFromDestinations(trip, {
    originCity: trip.preferences.originCity ?? trip.flights.outbound[0]?.city ?? '',
    destinations: [dest],
    destinationFood: [defaultFoodPrefsForDestination(dest)],
    travelStart: start,
    travelEnd: end,
  });
}

export function getDestinationForDate(
  destinations: TripDestination[],
  isoDate: string,
): TripDestination | undefined {
  const sorted = [...destinations].sort((a, b) => a.order - b.order);
  return sorted.find(
    (d) => isoDate >= d.arrivalDate && isoDate <= d.departureDate,
  );
}

export function syncTripFromDestinations(
  trip: Trip,
  input: {
    originCity: string;
    originAirport?: string;
    originLat?: number;
    originLng?: number;
    destinations: TripDestination[];
    destinationFood: DestinationFoodPrefs[];
    travelStart: string;
    travelEnd: string;
  },
): Trip {
  const sorted = [...input.destinations].sort((a, b) => a.order - b.order);
  const first = sorted[0];
  const last = sorted[sorted.length - 1];

  // Mevcut günlerin item/theme/highlight içeriğini dayNumber'a göre koru —
  // kullanıcı bir paket yükledikten sonra uçuş tarihlerini değiştirdiğinde
  // küratörlü içerik kaybolmasın; sadece tarih+weekday yeni aralığa kayar.
  const previousByDayNumber = new Map(trip.days.map((d) => [d.dayNumber, d]));

  const days = generateDaysBetween(input.travelStart, input.travelEnd).map((day) => {
    const dest = getDestinationForDate(sorted, day.date);
    const previous = previousByDayNumber.get(day.dayNumber);
    const baseTags = previous?.tags?.length ? previous.tags : day.tags;
    const baseTheme = previous?.theme && previous.theme !== `Gün ${day.dayNumber}` ? previous.theme : day.theme;
    const baseItems = previous?.items ?? day.items;
    return {
      ...day,
      items: baseItems,
      stepsEstimate: previous?.stepsEstimate ?? day.stepsEstimate,
      stepsEstimateMax: previous?.stepsEstimateMax,
      taxiRecommended: previous?.taxiRecommended,
      route: previous?.route,
      highlights: previous?.highlights,
      tags: dest
        ? [
            `${getDestinationProfile(dest.countryCode)?.flag ?? ''} ${dest.countryName}`.trim(),
            ...baseTags.filter((t) => !t.startsWith('🇯🇵') && !t.startsWith('🇰🇷') && !t.startsWith('🇹🇼') && !t.startsWith('🇬🇧') && !t.startsWith('🇫🇷') && !t.startsWith('🇮🇹') && !t.startsWith('🇩🇪') && !t.startsWith('🇪🇸') && !t.startsWith('🇺🇸') && !t.startsWith('🇹🇷')),
          ]
        : baseTags,
      theme:
        dest && baseTheme === `Gün ${day.dayNumber}`
          ? `${dest.city || dest.countryName} — Gün ${day.dayNumber}`
          : baseTheme,
    };
  });

  const title = buildTripTitleFromDestinations(input.originCity, sorted);

  const originAirport = input.originAirport ?? trip.flights.outbound[0]?.airport ?? '';
  const legs = buildRouteLegs(
    input.originCity,
    originAirport,
    sorted,
    input.travelStart,
    input.travelEnd,
  );

  const outbound = legs.length >= 2 ? [legs[0], legs[1]] : legs.length ? [legs[0]] : [];
  const returnLegs =
    legs.length >= 2 ? [legs[legs.length - 2], legs[legs.length - 1]] : [];

  const countryCodes = [...new Set(sorted.map((d) => d.countryCode).filter(Boolean))];

  return {
    ...trip,
    title: trip.title === 'Yeni seyahat' || trip.title.includes('→') ? title : trip.title,
    timezone: getDestinationProfile(first?.countryCode ?? '')?.timezone ?? trip.timezone,
    tripStart: `${input.travelStart}T08:00:00`,
    tripEnd: `${input.travelEnd}T20:00:00`,
    flights: { legs, outbound, return: returnLegs },
    days,
    preferences: {
      ...trip.preferences,
      originCity: input.originCity,
      originAirport: originAirport || trip.preferences.originAirport,
      originLat: input.originLat ?? trip.preferences.originLat,
      originLng: input.originLng ?? trip.preferences.originLng,
      destinationCity: last?.city ?? first?.city ?? '',
      destinationCountry: countryCodes.length === 1 ? countryCodes[0] : countryCodes.join(','),
      destinations: sorted,
      destinationFood: input.destinationFood,
      travelDates: { start: input.travelStart, end: input.travelEnd },
    },
  };
}

export function addDestination(
  trip: Trip,
  partial: Omit<TripDestination, 'id' | 'order'> & { order?: number },
): Trip {
  const existing = trip.preferences.destinations ?? [];
  const order = partial.order ?? existing.length;
  const profile = getDestinationProfile(partial.countryCode);
  const dest: TripDestination = {
    ...partial,
    id: newDestinationId(),
    countryName: partial.countryName || profile?.name || partial.countryCode,
    order,
  };
  const destinations = [...existing, dest].map((d, i) => ({ ...d, order: i }));
  const food = [...(trip.preferences.destinationFood ?? []), defaultFoodPrefsForDestination(dest)];

  const travelStart = trip.preferences.travelDates.start;
  const travelEnd =
    partial.departureDate > trip.preferences.travelDates.end
      ? partial.departureDate
      : trip.preferences.travelDates.end;

  return syncTripFromDestinations(trip, {
    originCity: trip.preferences.originCity ?? '',
    destinations,
    destinationFood: food,
    travelStart,
    travelEnd,
  });
}

export function removeDestination(trip: Trip, destId: string): Trip {
  const destinations = (trip.preferences.destinations ?? []).filter((d) => d.id !== destId);
  const food = (trip.preferences.destinationFood ?? []).filter((f) => f.destinationId !== destId);
  if (!destinations.length) {
    return {
      ...trip,
      preferences: { ...trip.preferences, destinations: [], destinationFood: food },
    };
  }
  const start = destinations.reduce((min, d) => (d.arrivalDate < min ? d.arrivalDate : min), destinations[0].arrivalDate);
  const end = destinations.reduce((max, d) => (d.departureDate > max ? d.departureDate : max), destinations[0].departureDate);
  return syncTripFromDestinations(trip, {
    originCity: trip.preferences.originCity ?? '',
    destinations: destinations.map((d, i) => ({ ...d, order: i })),
    destinationFood: food,
    travelStart: start,
    travelEnd: end,
  });
}

export function updateDestination(
  trip: Trip,
  destId: string,
  patch: Partial<TripDestination>,
): Trip {
  const destinations = (trip.preferences.destinations ?? []).map((d) =>
    d.id === destId ? { ...d, ...patch } : d,
  );
  const start = destinations.reduce(
    (min, d) => (d.arrivalDate < min ? d.arrivalDate : min),
    trip.preferences.travelDates.start,
  );
  const end = destinations.reduce(
    (max, d) => (d.departureDate > max ? d.departureDate : max),
    trip.preferences.travelDates.end,
  );
  return syncTripFromDestinations(trip, {
    originCity: trip.preferences.originCity ?? '',
    destinations,
    destinationFood: trip.preferences.destinationFood ?? [],
    travelStart: start,
    travelEnd: end,
  });
}
