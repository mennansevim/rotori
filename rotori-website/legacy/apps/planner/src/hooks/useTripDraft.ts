import { useCallback, useEffect, useState } from 'react';
import {
  tripSchema,
  createEmptyTrip,
  ensureTripDestinations,
  ensureTripGuide,
  ensureTripPreferences,
  applyTemplatePatch,
} from '@japan-trip/shared';

function normalize(t: Trip): Trip {
  return ensureTripGuide(ensureTripPreferences(ensureTripDestinations(tripSchema.parse(t))));
}
import type { Trip } from '@japan-trip/shared';
import japan14d from '../../../../data/templates/japan-14d.json';

/** URL'den ?u=username okur; yoksa kalıcı kullanıcı id'si üretir (cihaz başına). */
function resolveUsername(): string {
  if (typeof window === 'undefined') return 'default';
  const url = new URLSearchParams(window.location.search);
  const fromUrl = url.get('u');
  if (fromUrl && /^[a-zA-Z0-9_-]{1,32}$/.test(fromUrl)) {
    localStorage.setItem('trip:lastUser', fromUrl);
    return fromUrl;
  }
  const stored = localStorage.getItem('trip:lastUser');
  if (stored && /^[a-zA-Z0-9_-]{1,32}$/.test(stored)) return stored;
  const fresh = `user-${Math.random().toString(36).slice(2, 8)}`;
  localStorage.setItem('trip:lastUser', fresh);
  return fresh;
}

const USERNAME = resolveUsername();
const STORAGE_KEY = `trip:active:${USERNAME}`;
const HISTORY_KEY = `trip:history:${USERNAME}`;
const MAX_HISTORY = 20;

export function getCurrentUsername(): string {
  return USERNAME;
}

function loadInitial(): Trip {
  const raw = localStorage.getItem(STORAGE_KEY);
  if (raw) {
    try {
      return normalize(JSON.parse(raw));
    } catch {
      /* fall through */
    }
  }
  // Eski global key'i göç (geriye uyum)
  const legacy = localStorage.getItem('trip:draft:active');
  if (legacy) {
    try {
      const parsed = normalize(JSON.parse(legacy));
      localStorage.setItem(STORAGE_KEY, JSON.stringify(parsed));
      return parsed;
    } catch {
      /* ignore */
    }
  }
  return createEmptyTrip();
}

export function useTripDraft() {
  const [trip, setTrip] = useState<Trip>(loadInitial);

  const persist = useCallback((next: Trip) => {
    const parsed = normalize(next);
    setTrip(parsed);
    localStorage.setItem(STORAGE_KEY, JSON.stringify(parsed));
    localStorage.setItem(`trip:${parsed.slug}`, JSON.stringify(parsed));
    localStorage.setItem(`trip:user:${USERNAME}:${parsed.slug}`, JSON.stringify(parsed));
  }, []);

  const pushHistory = useCallback((snapshot: Trip) => {
    const hist: Trip[] = JSON.parse(localStorage.getItem(HISTORY_KEY) ?? '[]');
    hist.unshift(snapshot);
    localStorage.setItem(HISTORY_KEY, JSON.stringify(hist.slice(0, MAX_HISTORY)));
  }, []);

  const updateTrip = useCallback(
    (updater: (t: Trip) => Trip) => {
      setTrip((current) => {
        pushHistory(current);
        const next = normalize(updater(current));
        localStorage.setItem(STORAGE_KEY, JSON.stringify(next));
        localStorage.setItem(`trip:${next.slug}`, JSON.stringify(next));
        localStorage.setItem(`trip:user:${USERNAME}:${next.slug}`, JSON.stringify(next));
        return next;
      });
    },
    [pushHistory],
  );

  const undo = useCallback(() => {
    const hist: Trip[] = JSON.parse(localStorage.getItem(HISTORY_KEY) ?? '[]');
    if (!hist.length) return;
    const [prev, ...rest] = hist;
    localStorage.setItem(HISTORY_KEY, JSON.stringify(rest));
    persist(prev);
  }, [persist]);

  useEffect(() => {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(trip));
  }, [trip]);

  // Multi-tab senkron: başka tabta aynı user'ın trip'i güncellenirse
  // burada da reflect et.
  useEffect(() => {
    const onStorage = (e: StorageEvent) => {
      if (e.key !== STORAGE_KEY || !e.newValue) return;
      try {
        const next = normalize(JSON.parse(e.newValue));
        setTrip((current) => {
          if (JSON.stringify(current) === JSON.stringify(next)) return current;
          return next;
        });
      } catch {
        /* ignore */
      }
    };
    window.addEventListener('storage', onStorage);
    return () => window.removeEventListener('storage', onStorage);
  }, []);

  const exportJson = useCallback(() => {
    const blob = new Blob([JSON.stringify(trip, null, 2)], {
      type: 'application/json',
    });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `${trip.slug}.json`;
    a.click();
    URL.revokeObjectURL(url);
  }, [trip]);

  const importJson = useCallback(
    (file: File) => {
      const reader = new FileReader();
      reader.onload = () => {
        try {
          const data = JSON.parse(reader.result as string);
          persist(tripSchema.parse(data));
        } catch {
          alert('Geçersiz JSON dosyası');
        }
      };
      reader.readAsText(file);
    },
    [persist],
  );

  const startFresh = useCallback(() => {
    pushHistory(trip);
    persist(createEmptyTrip());
  }, [trip, persist, pushHistory]);

  /** Japonya 14 günlük tam planı yükle — tarihler mevcut trip travelDates'ine kaydırılır.
   *  Kullanıcı uçuş tarihlerini girdikçe planın dayNumber bazlı içeriği yeni aralığa
   *  shift edilir (syncTripFromDestinations merge logic'i). */
  const loadJapanTemplate = useCallback(() => {
    pushHistory(trip);

    const fresh = createEmptyTrip();
    const userHasSetDates =
      trip.preferences.travelDates.start !== fresh.preferences.travelDates.start ||
      trip.preferences.travelDates.end !== fresh.preferences.travelDates.end;
    const start = userHasSetDates
      ? trip.preferences.travelDates.start
      : fresh.preferences.travelDates.start;

    const tpl = japan14d as Partial<Trip>;
    const originalStart = tpl.days?.[0]?.date ?? '2026-05-14';
    const startDate = new Date(start + 'T12:00:00');
    const origStartDate = new Date(originalStart + 'T12:00:00');
    const shiftMs = startDate.getTime() - origStartDate.getTime();
    const shiftIso = (iso: string): string => {
      const d = new Date(iso);
      if (isNaN(d.getTime())) return iso;
      return new Date(d.getTime() + shiftMs).toISOString().replace('Z', '+00:00');
    };
    const shiftDateOnly = (iso: string): string => {
      const d = new Date(iso + 'T12:00:00');
      return new Date(d.getTime() + shiftMs).toISOString().slice(0, 10);
    };

    const shiftedDays = (tpl.days ?? []).map((d) => ({ ...d, date: shiftDateOnly(d.date) }));
    const shiftedDeadlines: Record<string, string> = {};
    for (const [k, v] of Object.entries(tpl.deadlines ?? {})) {
      if (typeof v === 'string') shiftedDeadlines[k] = shiftIso(v);
    }
    const lastDate = shiftedDays.length ? shiftedDays[shiftedDays.length - 1].date : start;

    const merged = applyTemplatePatch(fresh, {
      ...tpl,
      id: fresh.id,
      slug: fresh.slug,
      tripStart: `${start}T08:00:00`,
      tripEnd: `${lastDate}T20:00:00`,
      days: shiftedDays,
      deadlines: shiftedDeadlines,
      preferences: {
        ...(tpl.preferences ?? {}),
        travelDates: { start, end: lastDate },
        destinations: (tpl.preferences?.destinations ?? []).map((d) => ({
          ...d,
          arrivalDate: d.arrivalDate ? shiftDateOnly(d.arrivalDate) : d.arrivalDate,
          departureDate: d.departureDate ? shiftDateOnly(d.departureDate) : d.departureDate,
        })),
      } as Partial<Trip>['preferences'],
    });
    persist(normalize(merged));
  }, [trip, persist, pushHistory]);

  return {
    trip,
    updateTrip,
    undo,
    exportJson,
    importJson,
    startFresh,
    loadJapanTemplate,
    username: USERNAME,
  };
}
