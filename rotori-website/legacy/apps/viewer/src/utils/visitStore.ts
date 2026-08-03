import type { VisitRecord, VisitState } from '@japan-trip/shared';

const KEY = (username: string) => `viewer:visits:${username}`;

export function loadVisits(username: string): VisitState {
  if (typeof window === 'undefined') return { records: {} };
  try {
    const raw = localStorage.getItem(KEY(username));
    if (!raw) return { records: {} };
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== 'object') return { records: {} };
    return { records: parsed.records ?? {} };
  } catch {
    return { records: {} };
  }
}

export function saveVisits(username: string, state: VisitState): void {
  try {
    localStorage.setItem(KEY(username), JSON.stringify(state));
  } catch {
    /* quota */
  }
}

export function upsertRecord(
  state: VisitState,
  geofenceId: string,
  patch: Partial<VisitRecord>,
): VisitState {
  const cur: VisitRecord = state.records[geofenceId] ?? {
    geofenceId,
    totalDwellSeconds: 0,
  };
  return {
    ...state,
    records: { ...state.records, [geofenceId]: { ...cur, ...patch } },
  };
}
