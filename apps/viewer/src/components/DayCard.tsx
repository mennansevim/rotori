import { useEffect, useRef } from 'react';
import { checkStepsOverLimit } from '@japan-trip/shared';
import type { DayPlan, Trip } from '@japan-trip/shared';
import { TipBubble } from './TipBubble';
import { TimelineProgress } from './TimelineProgress';

function money(n: number, cur?: string) {
  try {
    return new Intl.NumberFormat('tr-TR', {
      style: 'currency',
      currency: cur ?? 'EUR',
      maximumFractionDigits: 0,
    }).format(n);
  } catch {
    return `${n} ${cur ?? ''}`;
  }
}

function tagClass(label: string): string {
  const lower = label.toLowerCase();
  if (/(yemek|food|ramen|sushi|kahval|öğle|akşam|restoran|cafe|kafe)/i.test(lower)) return 'tag-food';
  if (/(taksi|metro|tren|shinkansen|uçuş|transfer|otobü|ulaş)/i.test(lower)) return 'tag-transport';
  if (/(tapın|müze|saray|kale|kültür|kilise|cami)/i.test(lower)) return 'tag-culture';
  if (/(park|doğa|bahçe|orman|göl|deniz|sahil)/i.test(lower)) return 'tag-nature';
  if (/(eğlence|park|disney|usj|teamlab|gece|alışveriş)/i.test(lower)) return 'tag-fun';
  return '';
}

interface Props {
  day: DayPlan;
  trip: Trip;
  expanded: boolean;
  isActive: boolean;
  isPast: boolean;
  onToggle: () => void;
}

export function DayCard({ day, trip, expanded, isActive, isPast, onToggle }: Props) {
  const ref = useRef<HTMLElement>(null);
  const stepWarn = checkStepsOverLimit(day, trip.preferences.maxStepsPerDay);

  const dayTotal = day.items.reduce((s, it) => s + (it.cost ?? 0), 0);
  const dayCurrency = day.items.find((it) => it.costCurrency)?.costCurrency;

  useEffect(() => {
    if (isActive && expanded && ref.current) {
      ref.current.scrollIntoView({ behavior: 'smooth', block: 'start' });
    }
    // sadece ilk aktif scroll için
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isActive]);

  const stepsLabel =
    day.stepsEstimateMax && day.stepsEstimateMax !== day.stepsEstimate
      ? `~${day.stepsEstimate?.toLocaleString('tr-TR')}–${day.stepsEstimateMax.toLocaleString('tr-TR')}`
      : day.stepsEstimate
        ? `~${day.stepsEstimate.toLocaleString('tr-TR')}`
        : null;

  const weekday = day.weekday ?? '';

  return (
    <article
      ref={ref}
      className={`day-card${expanded ? ' expanded' : ''}${isActive ? ' active' : ''}${isPast ? ' past' : ''}`}
      data-date={day.date}
    >
      <button type="button" className="day-header" onClick={onToggle} aria-expanded={expanded}>
        <div className="day-num">
          <span className="num">{day.dayNumber}</span>
          {weekday && <span className="day">{weekday}</span>}
        </div>
        <div className="day-meta">
          <div className="day-date">{day.date}</div>
          <div className="day-theme">{day.theme || `Gün ${day.dayNumber}`}</div>
          {day.tags.length > 0 && (
            <div className="day-tags">
              {day.tags.map((t) => (
                <span key={t} className={`tag ${tagClass(t)}`}>
                  {t}
                </span>
              ))}
            </div>
          )}
        </div>
        <span className="day-toggle" aria-hidden>
          ▾
        </span>
      </button>

      {expanded && (
        <div className="day-body">
          {(day.route || stepsLabel || day.taxiRecommended) && (
            <div className="day-route-bar">
              {day.route && (
                <a href={day.route.mapsUrl} target="_blank" rel="noopener noreferrer">
                  🗺️ Günlük rota
                </a>
              )}
              {stepsLabel && (
                <span className={`day-steps-est${stepWarn ? ' steps-warn' : ''}`}>
                  <strong>👟 {stepsLabel}</strong> adım
                  {stepWarn && ' · limit aşıldı'}
                </span>
              )}
              {day.taxiRecommended && <span>🚕 Taksi önerilir</span>}
              {dayTotal > 0 && (
                <span>💴 Bütçe: {money(dayTotal, dayCurrency)}</span>
              )}
            </div>
          )}

          {isActive && <TimelineProgress day={day} timezone={trip.timezone} />}

          <div className="timeline">
            {day.items.map((item) => {
              const time = item.scheduledTime ?? item.time;
              return (
                <div key={item.id} className="timeline-item">
                  {time && <div className="timeline-time">{time}</div>}
                  <div className="timeline-title">
                    {item.mapUrl ? (
                      <a href={item.mapUrl} target="_blank" rel="noopener noreferrer">
                        {item.title}
                      </a>
                    ) : (
                      item.title
                    )}
                    {item.cost != null && item.cost > 0 && (
                      <span className="timeline-cost">{money(item.cost, item.costCurrency)}</span>
                    )}
                  </div>
                  {item.description && <div className="timeline-desc">{item.description}</div>}
                  {item.tips && (
                    <div className="timeline-tips">
                      💡 {item.tips}
                    </div>
                  )}
                </div>
              );
            })}
          </div>

          {day.highlights && day.highlights.length > 0 && (
            <div className="highlight-card">
              {day.highlights.map((h) => (
                <div key={h.title}>
                  <h4>✨ {h.title}</h4>
                  <p>{h.body}</p>
                </div>
              ))}
            </div>
          )}

          <TipBubble seed={day.dayNumber} />
        </div>
      )}
    </article>
  );
}
