import { useState } from 'react';

export interface OrbitPlace {
  id: string;
  name: string;
  city?: string;
  emoji?: string;
  category?: string;
  rating?: number;
}

interface Props {
  places: OrbitPlace[];
  /** Hangi yerler zaten planda — bunlar pasif/✓ rozetli. */
  isInPlan: (place: OrbitPlace) => boolean;
  /** Tıklanınca eklenecek aksiyon. */
  onPick: (place: OrbitPlace) => void;
  /** Tıklamadan sonra gösterilen geçici metin (örn. "✓ Gün 3'e eklendi"). */
  feedback?: Record<string, string>;
}

function chunk<T>(arr: T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < arr.length; i += size) out.push(arr.slice(i, i + size));
  return out;
}

export function PlaceOrbitGrid({ places, isInPlan, onPick, feedback }: Props) {
  const [hover, setHover] = useState<string | null>(null);
  const rows = chunk(places, 4);

  return (
    <div className="orbit-grid" role="list">
      {rows.map((row, ri) => (
        <div className={`orbit-row${ri % 2 === 1 ? ' orbit-row-offset' : ''}`} key={ri}>
          {row.map((p) => {
            const inPlan = isInPlan(p);
            const cat = p.category ?? 'culture';
            const fb = feedback?.[p.id];
            return (
              <button
                key={p.id}
                type="button"
                role="listitem"
                className={`orbit-item orbit-cat-${cat}${inPlan ? ' is-in-plan' : ''}${
                  hover === p.id ? ' is-hover' : ''
                }`}
                disabled={inPlan && !fb}
                onMouseEnter={() => setHover(p.id)}
                onMouseLeave={() => setHover((h) => (h === p.id ? null : h))}
                onClick={() => onPick(p)}
                aria-label={`${p.name}${inPlan ? ' (planda)' : ''}`}
              >
                <span className="orbit-circle">
                  <span className="orbit-emoji" aria-hidden>
                    {p.emoji ?? '📍'}
                  </span>
                  {inPlan && (
                    <span className="orbit-check" aria-hidden>
                      ✓
                    </span>
                  )}
                </span>
                <span className="orbit-name">{p.name}</span>
                {fb ? (
                  <span className="orbit-feedback">{fb}</span>
                ) : (
                  p.city && <span className="orbit-city">{p.city}</span>
                )}
              </button>
            );
          })}
        </div>
      ))}
    </div>
  );
}
