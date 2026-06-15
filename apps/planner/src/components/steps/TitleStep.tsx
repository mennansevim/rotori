import type { Pace, Trip } from '@japan-trip/shared';

interface Props {
  trip: Trip;
  onChange: (updater: (t: Trip) => Trip) => void;
}

function suggestTitles(trip: Trip): string[] {
  const dests = (trip.preferences.destinations ?? [])
    .slice()
    .sort((a, b) => a.order - b.order);
  const cities = dests.map((d) => d.city).filter(Boolean);
  const days = trip.days.length;
  const month = trip.tripStart ? new Date(trip.tripStart).getUTCMonth() + 1 : 0;
  const seasonHint =
    month === 3 || month === 4
      ? 'Sakura'
      : month === 10 || month === 11
        ? 'Sonbahar'
        : month === 12 || month === 1 || month === 2
          ? 'Kış'
          : null;

  const out: string[] = ['Japonya Turu'];
  if (days > 0) out.push(`${days} Günde Japonya`);
  if (cities.length === 1) out.push(`${cities[0]} Macerası`);
  if (cities.length >= 2) out.push(`${cities.slice(0, 2).join(' & ')} Rotası`);
  if (seasonHint) out.push(`${seasonHint} Japonya'sı`);
  out.push('İlk Japonya Seyahatim');
  return [...new Set(out)];
}

export function TitleStep({ trip, onChange }: Props) {
  const route =
    trip.preferences.originCity && trip.preferences.destinationCity
      ? `${trip.preferences.originCity} → ${trip.preferences.destinationCity}`
      : null;
  const suggestions = suggestTitles(trip);

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
            placeholder="ör. Japonya Turu"
            onChange={(e) => onChange((t) => ({ ...t, title: e.target.value }))}
          />
          <div className="title-suggestions">
            <span className="title-suggestions-label">Öneriler:</span>
            {suggestions.map((s) => (
              <button
                key={s}
                type="button"
                className={`chip${trip.title === s ? ' chip-active' : ''}`}
                onClick={() => onChange((t) => ({ ...t, title: s }))}
              >
                {s}
              </button>
            ))}
          </div>
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
