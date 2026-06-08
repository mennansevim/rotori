import { mergeAiItinerary, type AiItineraryDay, type DayPlan, type Trip } from '@japan-trip/shared';

export type EditScope = 'all' | 'day' | 'today';

export interface EditRequest {
  trip: Trip;
  instruction: string;
  scope: EditScope;
  targetDayNumber?: number;
  weather?: string;
}

export interface EditResult {
  source: 'ai';
  scope: EditScope;
  summary: string;
  days: DayPlan[];
}

export type EditError =
  | { kind: 'not-configured' }
  | { kind: 'ai-failed' }
  | { kind: 'network' }
  | { kind: 'unknown' };

export type EditResponse = { ok: true; result: EditResult } | { ok: false; error: EditError };

/**
 * /api/edit'i çağırır, başarılı sonuçta AI günlerini mevcut trip iskeletine birleştirir.
 * Scope === 'all' ise tüm günler; aksi halde sadece hedef gün(ler) revize edilir,
 * diğerleri olduğu gibi korunur.
 */
export async function submitEdit(req: EditRequest): Promise<EditResponse> {
  let resp: Response;
  try {
    resp = await fetch('/api/edit', {
      method: 'POST',
      headers: { 'content-type': 'application/json', accept: 'application/json' },
      body: JSON.stringify(req),
    });
  } catch {
    return { ok: false, error: { kind: 'network' } };
  }

  if (resp.status === 501) return { ok: false, error: { kind: 'not-configured' } };
  if (resp.status === 502) return { ok: false, error: { kind: 'ai-failed' } };
  if (!resp.ok) return { ok: false, error: { kind: 'unknown' } };

  const data = (await resp.json()) as {
    source?: string;
    scope?: EditScope;
    summary?: string;
    days?: AiItineraryDay[];
    error?: string;
  };

  if (data.source !== 'ai' || !data.days?.length) {
    return { ok: false, error: { kind: 'ai-failed' } };
  }

  const mergedDays = mergeAiItinerary(req.trip.days, data.days);

  return {
    ok: true,
    result: {
      source: 'ai',
      scope: data.scope ?? req.scope,
      summary: data.summary ?? '',
      days: mergedDays,
    },
  };
}
