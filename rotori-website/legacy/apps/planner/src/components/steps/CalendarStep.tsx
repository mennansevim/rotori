import { useState } from 'react';
import {
  moveItemBetweenDays,
  suggestTaxiForDay,
  checkStepsOverLimit,
  newItemId,
} from '@japan-trip/shared';
import type { DayPlan, Trip } from '@japan-trip/shared';

interface Props {
  trip: Trip;
  onChange: (updater: (t: Trip) => Trip) => void;
}

export function CalendarStep({ trip, onChange }: Props) {
  const [selected, setSelected] = useState(trip.days[0]?.dayNumber ?? 1);
  const day = trip.days.find((d) => d.dayNumber === selected);

  const updateDay = (dayNumber: number, patch: Partial<DayPlan>) => {
    onChange((t) => ({
      ...t,
      days: t.days.map((d) =>
        d.dayNumber === dayNumber ? { ...d, ...patch } : d,
      ),
    }));
  };

  const addActivity = () => {
    if (!day) return;
    const title = prompt('Aktivite adı');
    if (!title?.trim()) return;
    onChange((t) => ({
      ...t,
      days: t.days.map((d) =>
        d.dayNumber === selected
          ? {
              ...d,
              items: [
                ...d.items,
                {
                  id: newItemId(selected),
                  title: title.trim(),
                  time: '10:00',
                  kind: 'activity' as const,
                },
              ],
            }
          : d,
      ),
    }));
  };

  if (!day) {
    return <p>Önce Başlık adımında tarih aralığı belirleyin.</p>;
  }

  const stepWarn = checkStepsOverLimit(day, trip.preferences.maxStepsPerDay);
  const taxi = suggestTaxiForDay(day, trip.preferences);

  return (
    <>
      <h2 className="page-headline">Takvim</h2>
      <p className="page-sub">
        Gün gün planınız — kaydırarak gezin, detayları düzenleyin.
      </p>

      <div className="calendar-strip">
        {trip.days.map((d) => {
          const warn = checkStepsOverLimit(d, trip.preferences.maxStepsPerDay);
          const isSel = d.dayNumber === selected;
          return (
            <button
              key={d.dayNumber}
              type="button"
              className={`cal-day${isSel ? ' selected' : ''}`}
              onClick={() => setSelected(d.dayNumber)}
              style={{ textAlign: 'left', cursor: 'pointer', font: 'inherit', color: 'inherit' }}
            >
              <div className="cal-day-head">
                <div className="cal-day-num">
                  Gün {d.dayNumber}
                  {d.weekday ? ` · ${d.weekday}` : ''}
                </div>
                <div className="cal-day-date">
                  {d.date.slice(8, 10)}.{d.date.slice(5, 7)}
                </div>
                <div className="cal-day-theme">{d.theme}</div>
                <div className="cal-day-meta">
                  <span className="cal-badge">{d.items.length} aktivite</span>
                  {d.stepsEstimate != null && (
                    <span className={`cal-badge${warn ? ' warn' : ''}`}>
                      👟 {(d.stepsEstimate / 1000).toFixed(0)}k
                    </span>
                  )}
                </div>
              </div>
              <div className="cal-day-body">
                {d.items.length === 0 ? (
                  <p className="cal-empty">Boş — Keşif’ten ekleyin</p>
                ) : (
                  d.items.slice(0, 4).map((item) => (
                    <div key={item.id} className="cal-item">
                      {item.time && (
                        <div className="cal-item-time">{item.time}</div>
                      )}
                      {item.title}
                    </div>
                  ))
                )}
                {d.items.length > 4 && (
                  <p className="cal-empty">+{d.items.length - 4} daha…</p>
                )}
              </div>
            </button>
          );
        })}
      </div>

      <div className="day-detail-panel card">
        <div className="card-title">
          Gün {day.dayNumber} detayı
        </div>
        {stepWarn && (
          <div className="alert-banner warn">⚠️ {stepWarn.message}</div>
        )}
        {taxi && (
          <div className="alert-banner info">
            🚕 Yoğun gün — GO / Japan Taxi düşünün
          </div>
        )}
        <div className="field">
          <label>Gün teması</label>
          <input
            value={day.theme}
            onChange={(e) => updateDay(selected, { theme: e.target.value })}
          />
        </div>
        {day.items.map((item) => (
          <div key={item.id} className="day-editor-row">
            <div>
              <strong>{item.time ? `${item.time} · ` : ''}{item.title}</strong>
              {item.movedFromDay != null && (
                <span style={{ fontSize: 12, color: 'var(--text-tertiary)' }}>
                  {' '}
                  (Gün {item.movedFromDay}&apos;den)
                </span>
              )}
            </div>
            <label style={{ fontSize: 13, color: 'var(--text-secondary)' }}>
              Taşı
              <select
                value={selected}
                onChange={(e) => {
                  const to = Number(e.target.value);
                  if (to === selected) return;
                  onChange((t) => ({
                    ...t,
                    days: moveItemBetweenDays(t.days, item.id, selected, to),
                  }));
                }}
                style={{ marginLeft: 8 }}
              >
                {trip.days.map((d) => (
                  <option key={d.dayNumber} value={d.dayNumber}>
                    Gün {d.dayNumber}
                  </option>
                ))}
              </select>
            </label>
          </div>
        ))}
        <button
          type="button"
          className="btn btn-secondary btn-block"
          style={{ marginTop: 12 }}
          onClick={addActivity}
        >
          + Aktivite ekle
        </button>
        <label
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: 8,
            marginTop: 16,
            fontSize: 15,
          }}
        >
          <input
            type="checkbox"
            checked={!!day.taxiRecommended}
            onChange={(e) =>
              updateDay(selected, { taxiRecommended: e.target.checked })
            }
          />
          Taksi öner
        </label>
      </div>
    </>
  );
}
