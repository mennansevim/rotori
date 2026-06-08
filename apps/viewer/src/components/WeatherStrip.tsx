import { useEffect, useState } from 'react';
import type { DayPlan, Trip } from '@japan-trip/shared';
import {
  fetchDailyWeather,
  formatWeatherForAi,
  labelForCode,
  type DayWeather,
} from '../utils/weather';

interface Props {
  trip: Trip;
  activeDayNumber: number | null;
  /** "Hava'ya göre planla" tıklanınca aktif gün için modal'ı açar. */
  onReplan: (instruction: string, weatherSummary: string) => void;
}

function pickWeatherForDay(map: Map<string, DayWeather>, day: DayPlan): DayWeather | null {
  return map.get(day.date) ?? null;
}

export function WeatherStrip({ trip, activeDayNumber, onReplan }: Props) {
  const [byDate, setByDate] = useState<Map<string, DayWeather>>(new Map());
  const [loading, setLoading] = useState(false);
  const [available, setAvailable] = useState<boolean | null>(null);

  useEffect(() => {
    const dest = trip.preferences.destinations?.[0];
    const lat = dest?.lat ?? 35.6762;
    const lng = dest?.lng ?? 139.6503;
    const dates = trip.days.map((d) => d.date).filter(Boolean).sort();
    if (dates.length === 0) return;
    const start = dates[0];
    const end = dates[dates.length - 1];

    let cancelled = false;
    setLoading(true);
    (async () => {
      try {
        const list = await fetchDailyWeather(lat, lng, start, end);
        if (cancelled) return;
        const m = new Map(list.map((w) => [w.date, w]));
        setByDate(m);
        setAvailable(list.length > 0);
      } catch {
        if (!cancelled) setAvailable(false);
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [trip]);

  const activeDay = trip.days.find((d) => d.dayNumber === activeDayNumber);
  const activeWeather = activeDay ? pickWeatherForDay(byDate, activeDay) : null;

  if (loading) {
    return <div className="weather-strip-loading">🌤️ Hava durumu yükleniyor…</div>;
  }
  if (available === false || byDate.size === 0) return null;

  return (
    <section className="weather-strip" aria-label="Hava durumu">
      <div className="weather-strip-head">
        <strong>🌤️ Hava durumu</strong>
        {activeWeather && (
          <button
            type="button"
            className="weather-replan-btn"
            onClick={() => {
              const summary = formatWeatherForAi(activeWeather);
              const lbl = labelForCode(activeWeather.code, activeWeather.tMax);
              const instruction = lbl.isWet
                ? 'Yağmur var, bugünkü planı kapalı alanlara göre düzenle (AVM, müze, teamLab, akvaryum, alışveriş).'
                : lbl.isHot
                  ? 'Çok sıcak, öğlen açık alan aktivitelerini azalt, gölgeli/serin yerlere ağırlık ver.'
                  : 'Hava bugün için uygun, mevcut planı koruyarak küçük iyileştirmeler yap.';
              onReplan(instruction, summary);
            }}
          >
            🪄 Hava'ya göre planla
          </button>
        )}
      </div>
      <div className="weather-strip-row">
        {trip.days.map((d) => {
          const w = pickWeatherForDay(byDate, d);
          if (!w) return null;
          const lbl = labelForCode(w.code, w.tMax);
          const isActive = d.dayNumber === activeDayNumber;
          return (
            <div
              key={d.dayNumber}
              className={`weather-pill${isActive ? ' active' : ''}${lbl.isWet ? ' wet' : ''}`}
              title={`${lbl.label} · ${Math.round(w.tMin)}–${Math.round(w.tMax)}°C${
                w.precipProb != null ? ` · ${w.precipProb}% yağış` : ''
              }`}
            >
              <span className="weather-pill-day">G{d.dayNumber}</span>
              <span className="weather-pill-emoji">{lbl.emoji}</span>
              <span className="weather-pill-temp">{Math.round(w.tMax)}°</span>
            </div>
          );
        })}
      </div>
    </section>
  );
}
