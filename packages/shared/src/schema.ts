import { z } from 'zod';

const flightLegSchema = z.object({
  city: z.string(),
  airport: z.string(),
  dateTime: z.string(),
});

export const tripSchema = z.object({
  id: z.string().uuid().or(z.string().min(1)),
  slug: z.string().regex(/^[a-z0-9-]+$/),
  title: z.string().min(1),
  subtitle: z.string().optional(),
  timezone: z.string().default('Asia/Tokyo'),
  tripStart: z.string(),
  tripEnd: z.string(),
  flights: z.object({
    legs: z.array(flightLegSchema).optional(),
    outbound: z.array(flightLegSchema),
    return: z.array(flightLegSchema),
  }),
  hotels: z.array(
    z.object({
      id: z.string(),
      city: z.string(),
      name: z.string(),
      checkIn: z.string(),
      checkOut: z.string(),
      address: z.string().default(''),
      addressLocal: z.string().optional(),
      addressJa: z.string().optional(),
      mapsUrl: z.string().optional(),
      phone: z.string().optional(),
      notes: z.string().optional(),
    }),
  ),
  tickets: z.array(
    z.object({
      id: z.string(),
      kind: z.string(),
      label: z.string(),
      visitDate: z.string().optional(),
      bookingOpens: z.string().optional(),
      purchased: z.boolean(),
      url: z.string().optional(),
      emoji: z.string().optional(),
      imageDataUrl: z.string().optional(),
      scannedText: z.string().optional(),
    }),
  ),
  preferences: z.object({
    travelDates: z.object({ start: z.string(), end: z.string() }),
    originCity: z.string().optional(),
    originAirport: z.string().optional(),
    originLat: z.number().optional(),
    originLng: z.number().optional(),
    returnAirline: z.string().optional(),
    returnFlightNo: z.string().optional(),
    destinationCity: z.string().optional(),
    destinationCountry: z.string().optional(),
    destinations: z
      .array(
        z.object({
          id: z.string(),
          countryCode: z.string(),
          countryName: z.string(),
          city: z.string(),
          airport: z.string().optional(),
          lat: z.number().optional(),
          lng: z.number().optional(),
          arrivalDate: z.string(),
          departureDate: z.string(),
          order: z.number(),
          airline: z.string().optional(),
          flightNo: z.string().optional(),
        }),
      )
      .optional(),
    destinationFood: z
      .array(
        z.object({
          destinationId: z.string(),
          dietaryTags: z.array(z.string()),
          foodLikes: z.array(z.string()),
          foodDislikes: z.array(z.string()),
          mealBudgetPerPerson: z.number().optional(),
          mealBudgetCurrency: z.string().optional(),
        }),
      )
      .optional(),
    mustSee: z.array(z.string()),
    foodLikes: z.array(z.string()),
    foodDislikes: z.array(z.string()),
    dietary: z.array(z.string()).optional(),
    dietaryTags: z.array(z.string()).optional(),
    mealBudgetJpyPerPerson: z.number().optional(),
    mealBudgetPerPerson: z.number().optional(),
    mealBudgetCurrency: z.string().optional(),
    planMeals: z.boolean().optional(),
    maxStepsPerDay: z.number().optional(),
    pace: z.enum(['relaxed', 'moderate', 'intense']),
    partySize: z.number().optional(),
    childrenCount: z.number().optional(),
    tripType: z.enum(['roundtrip', 'oneway', 'multicity']).optional(),
    nearbyAirportsOrigin: z.boolean().optional(),
    nearbyAirportsDest: z.boolean().optional(),
    directFlightsOnly: z.boolean().optional(),
    selectedCityIds: z.array(z.string()).optional(),
    walkingTarget: z.enum(['light', 'moderate', 'intense']).optional(),
    transportPreference: z
      .enum(['transit', 'taxi_assisted', 'walking', 'mixed'])
      .optional(),
    paymentPreference: z
      .enum(['credit_card', 'cash', 'credit_and_cash', 'ic_card'])
      .optional(),
    childProfiles: z
      .array(z.object({ id: z.string(), age: z.number().int().min(0).max(18) }))
      .optional(),
    interests: z
      .array(
        z.enum([
          'anime',
          'pokemon',
          'shopping',
          'temples',
          'traditional',
          'tech',
          'kids',
          'theme_parks',
          'photography',
          'food',
        ]),
      )
      .optional(),
    foodSensitivities: z
      .array(
        z.enum([
          'no_pork',
          'no_pork_derivatives',
          'no_seafood',
          'halal_only',
          'kid_friendly',
          'turkish_palate',
          'vegetarian',
          'chicken_focus',
          'no_fatty_meat',
        ]),
      )
      .optional(),
  }),
  days: z.array(
    z.object({
      dayNumber: z.number().int().positive(),
      date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
      weekday: z.string().optional(),
      theme: z.string(),
      tags: z.array(z.string()),
      stepsEstimate: z.number().optional(),
      stepsEstimateMax: z.number().optional(),
      taxiRecommended: z.boolean().optional(),
      route: z.object({ mapsUrl: z.string().url() }).optional(),
      items: z.array(
        z.object({
          id: z.string(),
          time: z.string().optional(),
          title: z.string(),
          description: z.string().optional(),
          mapUrl: z.string().optional(),
          tips: z.string().optional(),
          kind: z.enum(['activity', 'transport', 'meal', 'hotel']).optional(),
          movedFromDay: z.number().optional(),
          lat: z.number().optional(),
          lng: z.number().optional(),
          scheduledTime: z.string().optional(),
          durationMin: z.number().optional(),
          cost: z.number().optional(),
          costCurrency: z.string().optional(),
          cityId: z.string().optional(),
        }),
      ),
      highlights: z
        .array(z.object({ title: z.string(), body: z.string() }))
        .optional(),
    }),
  ),
  deadlines: z
    .object({
      shinkansenBooking: z.string().optional(),
      skytreeVisit: z.string().optional(),
      skytreeBookingOpens: z.string().optional(),
    })
    .optional(),
  guide: z
    .object({
      useSuggestions: z.boolean().optional(),
      practicalTips: z.array(
        z.object({
          id: z.string(),
          icon: z.string().optional(),
          title: z.string(),
          body: z.string(),
          source: z.enum(['user', 'suggestion']).optional(),
        }),
      ),
      shopping: z.array(
        z.object({
          id: z.string(),
          text: z.string(),
          category: z.string(),
          checked: z.boolean().optional(),
          source: z.enum(['user', 'suggestion']).optional(),
        }),
      ),
      foodSpots: z.array(
        z.object({
          id: z.string(),
          name: z.string(),
          area: z.string().optional(),
          category: z.string().optional(),
          note: z.string().optional(),
          mapsUrl: z.string().optional(),
          source: z.enum(['user', 'suggestion']).optional(),
        }),
      ),
      compass: z.array(
        z.object({
          id: z.string(),
          title: z.string(),
          kind: z.enum(['emergency', 'phrases', 'money', 'transport', 'hotel', 'custom']),
          content: z.string(),
          source: z.enum(['user', 'suggestion']).optional(),
        }),
      ),
    })
    .optional(),
});

export type TripInput = z.infer<typeof tripSchema>;
