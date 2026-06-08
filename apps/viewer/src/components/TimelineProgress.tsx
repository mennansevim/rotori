import { useEffect, useMemo, useState } from 'react';
import type { DayPlan } from '@japan-trip/shared';

function parseHHMM(time: string | undefined): number | null {
  if (!time) return null;
  const m = time.match(/^(\d{1,2}):(\d{2})/);
  if (!m) return null;
  const h = Number(m[1]);
  const mm = Number(m[2]);
  if (Number.isNaN(h) || Number.isNaN(mm)) return null;
  return h * 60 + mm;
}

function nowMinutes(timezone?: string): number {
  const now = new Date();
  if (timezone) {
    try {
      const parts = new Intl.DateTimeFormat('en-US', {
        timeZone: timezone,
        hour: '2-digit',
        minute: '2-digit',
        hour12: false,
      }).formatToParts(now);
      const h = Number(parts.find((p) => p.type === 'hour')?.value ?? 0);
      const m = Number(parts.find((p) => p.type === 'minute')?.value ?? 0);
      return h * 60 + m;
    } catch {
      /* fall through */
    }
  }
  return now.getHours() * 60 + now.getMinutes();
}

function formatHHMM(mins: number): string {
  const h = Math.floor(mins / 60);
  const m = mins % 60;
  return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}`;
}

interface Props {
  day: DayPlan;
  timezone?: string;
}

/**
 * Aktif günün ilk-son aktivite saatleri arasında ilerleyen progress bar.
 * Saatlik tick + şu anki konum noktası gösterir.
 */
export function TimelineProgress({ day, timezone }: Props) {
  const [tick, setTick] = useState(() => nowMinutes(timezone));

  useEffect(() => {
    const id = window.setInterval(() => setTick(nowMinutes(timezone)), 60_000);
    return () => window.clearInterval(id);
  }, [timezone]);

  const { startMin, endMin, ticks } = useMemo(() => {
    const itemTimes = day.items
      .map((it) => parseHHMM(it.scheduledTime ?? it.time))
      .filter((v): v is number => v != null);
    if (itemTimes.length === 0) {
      return { startMin: null, endMin: null, ticks: [] as number[] };
    }
    const min = Math.min(...itemTimes);
    const max = Math.max(...itemTimes);
    // Görsel olarak nefes alsın: 30 dk pad
    const startMin = Math.max(0, min - 30);
    const endMin = Math.min(24 * 60, max + 60);
    // Saatlik tick'ler
    const ticks: number[] = [];
    const firstHour = Math.ceil(startMin / 60);
    const lastHour = Math.floor(endMin / 60);
    for (let h = firstHour; h <= lastHour; h++) ticks.push(h * 60);
    return { startMin, endMin, ticks };
  }, [day.items]);

  if (startMin == null || endMin == null) return null;

  const totalRange = endMin - startMin;
  if (totalRange <= 0) return null;

  const clamped = Math.max(startMin, Math.min(endMin, tick));
  const percent = ((clamped - startMin) / totalRange) * 100;
  const beforeStart = tick < startMin;
  const afterEnd = tick > endMin;

  return (
    <div className="timeline-progress" aria-label="Bugünün ilerlemesi">
      <div className="timeline-progress-bar">
        <div
          className="timeline-progress-fill"
          style={{ width: `${percent}%` }}
        />
        {!beforeStart && !afterEnd && (
          <div
            className="timeline-progress-dot"
            style={{ left: `${percent}%` }}
            title={`Şu an: ${formatHHMM(tick)}`}
          >
            <span className="timeline-progress-dot-label">{formatHHMM(tick)}</span>
          </div>
        )}
      </div>
      <div className="timeline-progress-ticks">
        {ticks.map((t) => {
          const pos = ((t - startMin) / totalRange) * 100;
          return (
            <span
              key={t}
              className="timeline-progress-tick"
              style={{ left: `${pos}%` }}
            >
              {formatHHMM(t)}
            </span>
          );
        })}
      </div>
      {beforeStart && (
        <div className="timeline-progress-note">
          Plan {formatHHMM(startMin)}’da başlıyor — şu an {formatHHMM(tick)}.
        </div>
      )}
      {afterEnd && (
        <div className="timeline-progress-note">
          Bugünün planı tamamlandı (son {formatHHMM(endMin)}).
        </div>
      )}
    </div>
  );
}
