export type Pace = 'relaxed' | 'moderate' | 'intense';

/** Günlük yürüyüş hedefi — UI üç kategori sunar, generator buradan maxStepsPerDay'i türetir. */
export type WalkingTarget = 'light' | 'moderate' | 'intense';

/** Kullanıcının tercih ettiği ulaşım karışımı. */
export type TransportPreference = 'transit' | 'taxi_assisted' | 'walking' | 'mixed';

/** Japonya'da öngörülen ödeme yöntemi. */
export type PaymentPreference = 'credit_card' | 'cash' | 'credit_and_cash' | 'ic_card';

export interface ChildProfile {
  id: string;
  age: number;
}

export type InterestTag =
  | 'anime'
  | 'pokemon'
  | 'shopping'
  | 'temples'
  | 'traditional'
  | 'tech'
  | 'kids'
  | 'theme_parks'
  | 'photography'
  | 'food';

export type FoodSensitivity =
  | 'no_pork'
  | 'no_pork_derivatives'
  | 'no_seafood'
  | 'halal_only'
  | 'kid_friendly'
  | 'turkish_palate'
  | 'vegetarian'
  | 'chicken_focus'
  | 'no_fatty_meat';

/** Walking target → günlük adım üst sınırı eşlemesi. */
export const WALKING_TARGET_STEPS: Record<WalkingTarget, number> = {
  light: 7000,
  moderate: 11000,
  intense: 15000,
};

export interface FlightLeg {
  city: string;
  airport: string;
  dateTime: string;
}

export interface HotelStay {
  id: string;
  city: string;
  name: string;
  checkIn: string;
  checkOut: string;
  /** Açık adres (zorunlu planlayıcıda) */
  address: string;
  /** Yerel dilde adres (taksi / pusula) */
  addressLocal?: string;
  mapsUrl?: string;
  phone?: string;
  /** Şablon önerileri / bölge tavsiyesi gibi serbest not */
  notes?: string;
  /** @deprecated addressLocal kullanın */
  addressJa?: string;
}

export type TicketKind =
  | 'flight'
  | 'train'
  | 'bus'
  | 'ferry'
  | 'attraction'
  | 'event'
  | 'other';

export interface Ticket {
  id: string;
  kind: TicketKind | string;
  label: string;
  visitDate?: string;
  bookingOpens?: string;
  purchased: boolean;
  url?: string;
  emoji?: string;
  /** Bilet fotoğrafı (base64 data URL) */
  imageDataUrl?: string;
  scannedText?: string;
}

export interface TripDestination {
  id: string;
  countryCode: string;
  countryName: string;
  city: string;
  airport?: string;
  lat?: number;
  lng?: number;
  arrivalDate: string;
  departureDate: string;
  order: number;
  /** Bu duraga ulastiran ucusun havayolu kodu (IATA) */
  airline?: string;
  /** Bu duraga ulastiran ucus numarasi */
  flightNo?: string;
}

export interface DestinationFoodPrefs {
  destinationId: string;
  dietaryTags: string[];
  foodLikes: string[];
  foodDislikes: string[];
  mealBudgetPerPerson?: number;
  mealBudgetCurrency?: string;
}

export interface TripPreferences {
  travelDates: { start: string; end: string };
  originCity?: string;
  originAirport?: string;
  originLat?: number;
  originLng?: number;
  /** Eve donus ucusunun havayolu kodu (IATA) */
  returnAirline?: string;
  /** Eve donus ucus numarasi */
  returnFlightNo?: string;
  destinationCity?: string;
  destinationCountry?: string;
  /** Çoklu rota: Japonya, Kore vb. */
  destinations?: TripDestination[];
  destinationFood?: DestinationFoodPrefs[];
  mustSee: string[];
  foodLikes: string[];
  foodDislikes: string[];
  dietary?: string[];
  /** Görsel çoklu seçim etiketleri (halal, no_pork, …) */
  dietaryTags?: string[];
  mealBudgetJpyPerPerson?: number;
  /** Kişi başı öğün bütçesi (herhangi para birimi) */
  mealBudgetPerPerson?: number;
  mealBudgetCurrency?: string;
  planMeals?: boolean;
  maxStepsPerDay?: number;
  pace: Pace;
  partySize?: number;
  /** Seyahatteki çocuk sayısı (çocuk dostu rota için) */
  childrenCount?: number;
  /** @deprecated Artık çok duraklı rota varsayılan; UI kullanmıyor */
  tripType?: 'roundtrip' | 'oneway' | 'multicity';
  nearbyAirportsOrigin?: boolean;
  nearbyAirportsDest?: boolean;
  directFlightsOnly?: boolean;
  /** Plan adımında seçilen gezilecek şehir id'leri (cities.ts) */
  selectedCityIds?: string[];

  /** Onboarding: günlük adım hedefi (UI kategori, maxStepsPerDay'i türetir). */
  walkingTarget?: WalkingTarget;
  /** Onboarding: tercih edilen ulaşım karışımı. */
  transportPreference?: TransportPreference;
  /** Onboarding: Japonya'da öngörülen ödeme yöntemi. */
  paymentPreference?: PaymentPreference;
  /** Onboarding: çocukların yaş profilleri (childrenCount ile geriye dönük uyumlu). */
  childProfiles?: ChildProfile[];
  /** Onboarding: kullanıcının ilgi alanları — itinerary generator ağırlandırması için. */
  interests?: InterestTag[];
  /** Onboarding: yemek hassasiyetleri (dietaryTags'a türetiliyor). */
  foodSensitivities?: FoodSensitivity[];
  /** Welcome akışında "Biletim var" mı yoksa "Gezi planla" mı seçildi.
   *  false → uçuş numarası/havayolu alanları gizlenir. */
  hasTicket?: boolean;
  /** Plan adımında gün listesi açıldı mı.
   *  Wizard generate veya Keşfet'ten Plana ekle ile true olur. */
  planRevealed?: boolean;
}

export interface TimelineItem {
  id: string;
  time?: string;
  title: string;
  description?: string;
  mapUrl?: string;
  tips?: string;
  kind?: 'activity' | 'transport' | 'meal' | 'hotel';
  movedFromDay?: number;
  /** Wanderlog tarzı plan alanları */
  lat?: number;
  lng?: number;
  scheduledTime?: string;
  durationMin?: number;
  cost?: number;
  costCurrency?: string;
  cityId?: string;
}

export interface DayHighlight {
  title: string;
  body: string;
}

export interface DayPlan {
  dayNumber: number;
  date: string;
  weekday?: string;
  theme: string;
  tags: string[];
  stepsEstimate?: number;
  stepsEstimateMax?: number;
  taxiRecommended?: boolean;
  route?: { mapsUrl: string };
  items: TimelineItem[];
  highlights?: DayHighlight[];
}

export interface Trip {
  id: string;
  slug: string;
  title: string;
  subtitle?: string;
  timezone: string;
  tripStart: string;
  tripEnd: string;
  flights: {
    /** Tam rota: kalkış → duraklar → eve dönüş */
    legs?: FlightLeg[];
    outbound: FlightLeg[];
    return: FlightLeg[];
  };
  hotels: HotelStay[];
  tickets: Ticket[];
  preferences: TripPreferences;
  days: DayPlan[];
  deadlines?: {
    shinkansenBooking?: string;
    skytreeVisit?: string;
    skytreeBookingOpens?: string;
  };
  /** Pratik bilgiler, alışveriş, yemek, pusula */
  guide?: import('./extras/types.js').TripGuide;
}
