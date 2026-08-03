import { useEffect } from 'react';
import type { Pace, Trip } from '@japan-trip/shared';

interface Props {
  trip: Trip;
  onChange: (updater: (t: Trip) => Trip) => void;
}

function autoTitle(trip: Trip): string {
  const source = trip.tripStart || trip.preferences.travelDates?.start;
  const year = source ? new Date(source).getUTCFullYear() : new Date().getUTCFullYear();
  return `Japonya ${year}`;
}

export function TitleStep({ trip, onChange }: Props) {
  const route =
    trip.preferences.originCity && trip.preferences.destinationCity
      ? `${trip.preferences.originCity} → ${trip.preferences.destinationCity}`
      : null;
  const computed = autoTitle(trip);

  useEffect(() => {
    const current = (trip.title ?? '').trim();
    if (current === computed) return;
    if (current && current !== 'Japonya Turu' && !/^Japonya \d{4}$/.test(current)) return;
    onChange((t) => ({ ...t, title: computed }));
  }, [computed, trip.title, onChange]);

  return (
    <>
      <h2 className="page-headline">Planına isim ver</h2>
      <p className="page-sub">
        {route ? (
          <>
            Rotanız: <strong>{route}</strong> · {trip.days.length} gün
          </>
        ) : (
          'Önce Seyahat adımında rotayı tamamlayın.'
        )}
      </p>

      <div className="card">
        <div className="card-title">Görünen ad</div>
        <div className="field">
          <label>Başlık</label>
          <input
            value={trip.title}
            placeholder={computed}
            onChange={(e) => onChange((t) => ({ ...t, title: e.target.value }))}
          />
          <p className="field-hint">
            Gezinin yılına göre otomatik belirlenir (örn. <strong>{computed}</strong>). İstersen
            elle değiştirebilirsin.
          </p>
        </div>
        <div className="field">
          <label>Açıklama (opsiyonel)</label>
          <input
            value={trip.subtitle ?? ''}
            placeholder="Kısa bir not"
            onChange={(e) => onChange((t) => ({ ...t, subtitle: e.target.value }))}
          />
        </div>
        <div className="grid-2">
          <div className="field">
            <label>Kişi sayısı</label>
            <input
              type="number"
              min={1}
              value={trip.preferences.partySize ?? 2}
              onChange={(e) =>
                onChange((t) => ({
                  ...t,
                  preferences: {
                    ...t.preferences,
                    partySize: Number(e.target.value),
                  },
                }))
              }
            />
          </div>
          <div className="field">
            <label>Tempo</label>
            <select
              value={trip.preferences.pace}
              onChange={(e) =>
                onChange((t) => ({
                  ...t,
                  preferences: {
                    ...t.preferences,
                    pace: e.target.value as Pace,
                  },
                }))
              }
            >
              <option value="relaxed">Rahat</option>
              <option value="moderate">Dengeli</option>
              <option value="intense">Yoğun</option>
            </select>
          </div>
        </div>
      </div>
    </>
  );
}
