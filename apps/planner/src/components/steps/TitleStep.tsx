import type { Pace, Trip } from '@japan-trip/shared';

interface Props {
  trip: Trip;
  onChange: (updater: (t: Trip) => Trip) => void;
}

export function TitleStep({ trip, onChange }: Props) {
  const route =
    trip.preferences.originCity && trip.preferences.destinationCity
      ? `${trip.preferences.originCity} → ${trip.preferences.destinationCity}`
      : null;

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
            placeholder="ör. Yaz tatili 2027"
            onChange={(e) => onChange((t) => ({ ...t, title: e.target.value }))}
          />
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
