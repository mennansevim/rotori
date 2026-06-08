import {
  generateItineraryFromTrip,
  mergeAiItinerary,
  type AiItineraryDay,
  type DayPlan,
  type Trip,
} from '@japan-trip/shared';

export type ItinerarySource = 'ai' | 'rules';
export type ItineraryReason = 'ok' | 'not-configured' | 'ai-failed' | 'network' | 'unknown';

export interface ItineraryResult {
  source: ItinerarySource;
  reason: ItineraryReason;
  days: DayPlan[];
}

function rules(trip: Trip, reason: ItineraryReason): ItineraryResult {
  return { source: 'rules', reason, days: generateItineraryFromTrip(trip) };
}

/** Önce AI dener; başarısızsa kural tabanlı üreticiye düşer. */
export async function generateItinerary(trip: Trip): Promise<ItineraryResult> {
  let resp: Response;
  try {
    resp = await fetch('/api/itinerary', {
      method: 'POST',
      headers: { 'content-type': 'application/json', accept: 'application/json' },
      body: JSON.stringify(trip),
    });
  } catch {
    return rules(trip, 'network');
  }

  if (resp.status === 501) return rules(trip, 'not-configured');
  if (resp.status === 502) return rules(trip, 'ai-failed');
  if (!resp.ok) return rules(trip, 'unknown');

  const data = (await resp.json()) as {
    source?: string;
    days?: AiItineraryDay[];
    error?: string;
  };

  if (data.source === 'ai' && data.days?.length) {
    return {
      source: 'ai',
      reason: 'ok',
      days: mergeAiItinerary(trip.days, data.days),
    };
  }

  return rules(trip, 'ai-failed');
}
