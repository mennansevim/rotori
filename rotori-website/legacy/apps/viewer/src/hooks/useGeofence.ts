import { useCallback, useEffect, useRef, useState } from 'react';
import {
  distanceMeters,
  type Geofence,
  type VisitState,
} from '@japan-trip/shared';
import { loadVisits, saveVisits, upsertRecord } from '../utils/visitStore';

export type GeofencePermission = 'idle' | 'requesting' | 'granted' | 'denied' | 'unsupported';

interface Options {
  username: string;
  fences: Geofence[];
  /** Geofence dışına çıkınca dwell sayacının sıfırlanmasına kadar verilen tolerans (sn). */
  graceSeconds?: number;
  onCompleted?: (fence: Geofence) => void;
}

interface ActiveSession {
  startedAt: number;
  lastTick: number;
}

/**
 * Foreground geofence motoru.
 * - navigator.geolocation.watchPosition ile konum okur (yalnız sayfa açıkken).
 * - Her tick'te aktif fence'lere dwell saniyesi ekler; minDwell'i geçince complete tetikler.
 * - Persistans localStorage'da; tekrar açıldığında kazanılmış rozetler korunur.
 */
export function useGeofence({
  username,
  fences,
  graceSeconds = 120,
  onCompleted,
}: Options) {
  const [permission, setPermission] = useState<GeofencePermission>(
    typeof navigator === 'undefined' || !('geolocation' in navigator)
      ? 'unsupported'
      : 'idle',
  );
  const [position, setPosition] = useState<GeolocationPosition | null>(null);
  const [visits, setVisits] = useState<VisitState>(() => loadVisits(username));
  const sessionRef = useRef<Record<string, ActiveSession>>({});
  const watchIdRef = useRef<number | null>(null);
  /** Sekme arka plana alınınca takip duraklatıldıysa true (öne gelince sürdür). */
  const pausedRef = useRef(false);
  const onCompletedRef = useRef(onCompleted);
  useEffect(() => {
    onCompletedRef.current = onCompleted;
  }, [onCompleted]);

  const persist = useCallback(
    (next: VisitState) => {
      setVisits(next);
      saveVisits(username, next);
    },
    [username],
  );

  const handlePosition = useCallback(
    (pos: GeolocationPosition) => {
      setPosition(pos);
      const now = pos.timestamp || Date.now();
      const here = { lat: pos.coords.latitude, lng: pos.coords.longitude };
      const accuracy = pos.coords.accuracy ?? 50;

      setVisits((cur) => {
        let next = cur;
        for (const f of fences) {
          if (next.records[f.id]?.completedAt) continue;
          const d = distanceMeters(here, { lat: f.lat, lng: f.lng });
          const inside = d <= f.radiusMeters + Math.min(accuracy, 80);
          const session = sessionRef.current[f.id];

          if (inside) {
            if (!session) {
              sessionRef.current[f.id] = { startedAt: now, lastTick: now };
              next = upsertRecord(next, f.id, {
                firstSeenAt:
                  next.records[f.id]?.firstSeenAt ??
                  new Date(now).toISOString(),
              });
            } else {
              const delta = Math.max(0, (now - session.lastTick) / 1000);
              if (delta > 0) {
                const total =
                  (next.records[f.id]?.totalDwellSeconds ?? 0) +
                  Math.min(delta, graceSeconds + 60);
                next = upsertRecord(next, f.id, { totalDwellSeconds: total });
                if (total >= f.minDwellSeconds && !next.records[f.id].completedAt) {
                  next = upsertRecord(next, f.id, {
                    completedAt: new Date(now).toISOString(),
                  });
                  queueMicrotask(() => onCompletedRef.current?.(f));
                }
              }
              session.lastTick = now;
            }
          } else if (session) {
            const sinceLast = (now - session.lastTick) / 1000;
            if (sinceLast > graceSeconds) {
              delete sessionRef.current[f.id];
            }
          }
        }
        saveVisits(username, next);
        return next;
      });
    },
    [fences, graceSeconds, username],
  );

  const handleError = useCallback((err: GeolocationPositionError) => {
    if (err.code === err.PERMISSION_DENIED) setPermission('denied');
  }, []);

  const start = useCallback(() => {
    if (permission === 'unsupported' || permission === 'denied') return;
    if (watchIdRef.current != null) return;
    setPermission('requesting');
    watchIdRef.current = navigator.geolocation.watchPosition(
      (pos) => {
        setPermission('granted');
        handlePosition(pos);
      },
      handleError,
      { enableHighAccuracy: true, maximumAge: 15_000, timeout: 30_000 },
    );
  }, [permission, handlePosition, handleError]);

  const stop = useCallback(() => {
    if (watchIdRef.current != null) {
      navigator.geolocation.clearWatch(watchIdRef.current);
      watchIdRef.current = null;
    }
    pausedRef.current = false;
    sessionRef.current = {};
  }, []);

  useEffect(() => {
    return () => stop();
  }, [stop]);

  // Optimum GPS: sekme arka plandayken konum izlemeyi duraklat, öne gelince
  // sürdür. Dwell oturumları korunur; böylece pil tüketimi azalır.
  useEffect(() => {
    if (typeof document === 'undefined') return;
    const onVisibility = () => {
      if (document.hidden) {
        if (watchIdRef.current != null) {
          navigator.geolocation.clearWatch(watchIdRef.current);
          watchIdRef.current = null;
          pausedRef.current = true;
        }
      } else if (pausedRef.current) {
        pausedRef.current = false;
        start();
      }
    };
    document.addEventListener('visibilitychange', onVisibility);
    return () => document.removeEventListener('visibilitychange', onVisibility);
  }, [start]);

  /** Test/debug: manuel olarak konum simüle et. */
  const simulate = useCallback(
    (coords: { lat: number; lng: number; accuracy?: number }) => {
      handlePosition({
        coords: {
          latitude: coords.lat,
          longitude: coords.lng,
          accuracy: coords.accuracy ?? 20,
          altitude: null,
          altitudeAccuracy: null,
          heading: null,
          speed: null,
        } as GeolocationCoordinates,
        timestamp: Date.now(),
      } as GeolocationPosition);
    },
    [handlePosition],
  );

  const reset = useCallback(() => {
    const empty: VisitState = { records: {} };
    sessionRef.current = {};
    persist(empty);
  }, [persist]);

  return {
    permission,
    position,
    visits,
    start,
    stop,
    simulate,
    reset,
  };
}
