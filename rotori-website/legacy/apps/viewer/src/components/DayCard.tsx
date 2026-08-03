import { useEffect, useRef } from 'react';
import type { DayPlan, Trip } from '@japan-trip/shared';
import { TipBubble } from './TipBubble';
import { TimelineProgress } from './TimelineProgress';

function parseDayDate(value: string) {
  try {
    const date = new Date(`${value}T12:00:00`);
    if (Number.isNaN(date.getTime())) throw new Error('invalid date');
    return {
      dateNumber: new Intl.DateTimeFormat('tr-TR', { day: '2-digit' }).format(date),
      month: new Intl.DateTimeFormat('tr-TR', { month: 'short' })
        .format(date)
        .replace('.', ''),
      weekday: new Intl.DateTimeFormat('tr-TR', { weekday: 'short' })
        .format(date)
        .replace('.', ''),
    };
  } catch {
    return { dateNumber: String(value).slice(-2), month: '', weekday: '' };
  }
}

function itemVisual(kind: string | undefined, text: string) {
  const source = `${kind ?? ''} ${text}`.toLocaleLowerCase('tr-TR');
  if (/(uçuş|havaliman|airport|flight|varış)/.test(source)) return { icon: '✈️', tone: 'sky' };
  if (/(tren|metro|otobüs|otobü|shinkansen|transfer|taksi|ulaşım)/.test(source)) {
    return { icon: '🚆', tone: 'violet' };
  }
  if (/(otel|hotel|check-in|konaklama)/.test(source)) return { icon: '🛏️', tone: 'indigo' };
  if (/(kahvaltı|öğle|akşam|yemek|ramen|sushi|restoran|kafe|cafe)/.test(source)) {
    return { icon: '🍜', tone: 'coral' };
  }
  if (/(tapınak|senso|müze|saray|kale|kültür)/.test(source)) {
    return { icon: '⛩️', tone: 'sakura' };
  }
  if (/(park|bahçe|orman|göl|sahil|doğa)/.test(source)) return { icon: '🌿', tone: 'matcha' };
  if (/(alışveriş|mağaza|market|avm)/.test(source)) return { icon: '🛍️', tone: 'gold' };
  return { icon: '📍', tone: 'violet' };
}

function findNextItemIndex(items: DayPlan['items'], timezone: string) {
  try {
    const parts = new Intl.DateTimeFormat('en-GB', {
      timeZone: timezone,
      hour: '2-digit',
      minute: '2-digit',
      hour12: false,
    }).formatToParts(new Date());
    const currentHour = Number(parts.find((part) => part.type === 'hour')?.value ?? 0);
    const currentMinute = Number(parts.find((part) => part.type === 'minute')?.value ?? 0);
    const nowInMinutes = currentHour * 60 + currentMinute;
    const index = items.findIndex((item) => {
      const match = (item.scheduledTime ?? item.time ?? '').match(/(\d{1,2}):(\d{2})/);
      if (!match) return false;
      return Number(match[1]) * 60 + Number(match[2]) >= nowInMinutes;
    });
    return index;
  } catch {
    return items.length > 0 ? 0 : -1;
  }
}

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

  const dayTotal = day.items.reduce((s, it) => s + (it.cost ?? 0), 0);
  const dayCurrency = day.items.find((it) => it.costCurrency)?.costCurrency;
  const dateParts = parseDayDate(day.date);
  const nextItemIndex = isActive ? findNextItemIndex(day.items, trip.timezone) : -1;

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

  const weekday = day.weekday ?? dateParts.weekday;

  return (
    <article
      ref={ref}
      className={`day-card${expanded ? ' expanded' : ''}${isActive ? ' active' : ''}${isPast ? ' past' : ''}`}
      data-date={day.date}
    >
      <button type="button" className="day-header" onClick={onToggle} aria-expanded={expanded}>
        <div className="day-num">
          <span className="num">{dateParts.dateNumber}</span>
          {dateParts.month && <span className="day">{dateParts.month}</span>}
        </div>
        <div className="day-meta">
          <div className="day-kicker">
            <span>{day.dayNumber}. Gün{weekday ? ` · ${weekday}` : ''}</span>
            {isActive && <span className="day-status">Bugün</span>}
          </div>
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
        <div className="day-header-side" aria-hidden>
          <span className="day-country">🇯🇵</span>
          <span className="day-toggle">⌄</span>
        </div>
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
                <span className="day-steps-est">
                  <strong>👟 {stepsLabel}</strong> adım
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
            {day.items.map((item, itemIndex) => {
              const time = item.scheduledTime ?? item.time;
              const visual = itemVisual(item.kind, item.title);
              return (
                <div
                  key={item.id}
                  className={`timeline-item${itemIndex === nextItemIndex ? ' timeline-item-next' : ''}`}
                >
                  <div className="timeline-time">{time || 'Esnek'}</div>
                  <div className={`timeline-icon timeline-icon-${visual.tone}`} aria-hidden>
                    {visual.icon}
                  </div>
                  <div className="timeline-content">
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
                        <span aria-hidden>💡</span> {item.tips}
                      </div>
                    )}
                  </div>
                  {itemIndex === nextItemIndex && <span className="timeline-next-badge">Sıradaki</span>}
                  {item.mapUrl && <span className="timeline-chevron" aria-hidden>›</span>}
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
