import { useMemo, useState } from 'react';
import { getDestinationForDate, getDestinationProfile } from '@japan-trip/shared';
import type { DayPlan, TimelineItem, TripDestination } from '@japan-trip/shared';
import { PlaceDiscoveryModal, type DiscoveredPlace } from './PlaceDiscoveryModal';

interface Props {
  day: DayPlan;
  destinations: TripDestination[];
  expanded: boolean;
  onToggle: () => void;
  dragSource: { dayNumber: number; index: number } | null;
  onDragStart: (dayNumber: number, index: number) => void;
  onDragEnd: () => void;
  onDropOnDay: (dayNumber: number, atIndex?: number) => void;
  onReorder: (dayNumber: number, from: number, to: number) => void;
  onUpdateDay: (dayNumber: number, patch: Partial<DayPlan>) => void;
  onUpdateItem: (dayNumber: number, itemId: string, patch: Partial<TimelineItem>) => void;
  onRemoveItem: (dayNumber: number, itemId: string) => void;
  onAddItem: (dayNumber: number, title: string) => void;
  onAddDiscoveredPlace?: (dayNumber: number, place: DiscoveredPlace) => void;
  onOptimizeDay?: (dayNumber: number) => void;
  /** Mobile-friendly taşıma için tüm günlerin (dayNumber, date) listesi. */
  allDays?: { dayNumber: number; date: string }[];
  /** Item'ı başka güne taşı (mobil tıklama akışı). */
  onMoveItemToDay?: (fromDay: number, itemIndex: number, toDay: number) => void;
}

export function DayPlanCard({
  day,
  destinations,
  expanded,
  onToggle,
  dragSource,
  onDragStart,
  onDragEnd,
  onDropOnDay,
  onReorder,
  onUpdateDay,
  onUpdateItem,
  onRemoveItem,
  onAddItem,
  onAddDiscoveredPlace,
  onOptimizeDay,
  allDays,
  onMoveItemToDay,
}: Props) {
  const [moveMenuOpenForIdx, setMoveMenuOpenForIdx] = useState<number | null>(null);

  const [discoverOpen, setDiscoverOpen] = useState(false);
  const [pickedCountInRun, setPickedCountInRun] = useState(0);
  const dest = getDestinationForDate(destinations, day.date);
  const profile = dest ? getDestinationProfile(dest.countryCode) : undefined;
  const fallbackPlaces = useMemo(
    () =>
      profile?.popularPlaces.map((p) => ({
        id: p.id,
        name: p.name,
        emoji: p.emoji,
        category: p.category,
        typicalSteps: p.typicalSteps,
        mapsQuery: `${p.name} ${p.city}`,
        imageQuery: p.name,
        city: p.city,
      })),
    [profile],
  );
  void onAddItem;

  const handleModalOpen = () => {
    setPickedCountInRun(0);
    setDiscoverOpen(true);
  };

  const handleModalClose = () => {
    setDiscoverOpen(false);
    if (pickedCountInRun > 0) {
      onOptimizeDay?.(day.dayNumber);
    }
  };

  return (
    <article
      className={`itinerary-day-card${expanded ? ' expanded' : ''}`}
      onDragOver={(e) => e.preventDefault()}
      onDrop={() => {
        if (dragSource && dragSource.dayNumber !== day.dayNumber) {
          onDropOnDay(day.dayNumber);
        }
      }}
    >
      <header className="itinerary-day-head" onClick={onToggle}>
        <div className="itinerary-day-badge">{day.dayNumber}</div>
        <div className="itinerary-day-meta">
          <div className="itinerary-day-date">
            {day.date}
            {day.weekday && <span className="itinerary-day-wd">{day.weekday}</span>}
          </div>
          <input
            className="itinerary-day-theme"
            value={day.theme}
            onClick={(e) => e.stopPropagation()}
            onChange={(e) => onUpdateDay(day.dayNumber, { theme: e.target.value })}
          />
          {dest && (
            <span className="itinerary-day-loc">
              {profile?.flag} {dest.city || dest.countryName}
            </span>
          )}
        </div>
        <div className="itinerary-day-stats">
          {day.stepsEstimate != null && (
            <span className="itinerary-steps" title="Tahmini adım">
              👣 {(day.stepsEstimate / 1000).toFixed(0)}k
            </span>
          )}
          <span className="itinerary-item-count">{day.items.length} durak</span>
          <span className="itinerary-chevron" aria-hidden>
            {expanded ? '▾' : '▸'}
          </span>
        </div>
      </header>

      {day.tags.length > 0 && (
        <div className="itinerary-tags">
          {day.tags.map((t) => (
            <span key={t} className="itinerary-tag">
              {t}
            </span>
          ))}
        </div>
      )}

      {expanded && (
        <div className="itinerary-day-body">
          {day.highlights?.map((h, i) => (
            <div key={i} className="itinerary-highlight">
              <strong>{h.title}</strong>
              <p>{h.body}</p>
            </div>
          ))}

          <ol className="itinerary-timeline">
            {day.items.map((it, idx) => (
              <li
                key={it.id}
                className={`itinerary-tl-item${dragSource?.dayNumber === day.dayNumber && dragSource.index === idx ? ' dragging' : ''}`}
                draggable
                onDragStart={() => onDragStart(day.dayNumber, idx)}
                onDragOver={(e) => e.preventDefault()}
                onDrop={() => {
                  if (!dragSource) return;
                  if (dragSource.dayNumber === day.dayNumber) {
                    onReorder(day.dayNumber, dragSource.index, idx);
                  } else {
                    onDropOnDay(day.dayNumber, idx);
                  }
                  onDragEnd();
                }}
                onDragEnd={onDragEnd}
              >
                <span className="itinerary-tl-handle" aria-hidden>
                  ⠿
                </span>
                <input
                  type="time"
                  className="itinerary-tl-time"
                  value={it.time ?? it.scheduledTime ?? ''}
                  onChange={(e) =>
                    onUpdateItem(day.dayNumber, it.id, {
                      time: e.target.value,
                      scheduledTime: e.target.value,
                    })
                  }
                />
                <div className="itinerary-tl-content">
                  <input
                    className="itinerary-tl-title"
                    value={it.title}
                    onChange={(e) => onUpdateItem(day.dayNumber, it.id, { title: e.target.value })}
                  />
                  {it.description && (
                    <p className="itinerary-tl-desc">{it.description}</p>
                  )}
                  {it.tips && <p className="itinerary-tl-tips">💡 {it.tips}</p>}
                </div>
                {allDays && allDays.length > 1 && onMoveItemToDay && (
                  <div className="itinerary-tl-move-wrap">
                    <button
                      type="button"
                      className="itinerary-tl-move"
                      aria-label="Başka güne taşı"
                      aria-expanded={moveMenuOpenForIdx === idx}
                      onClick={() =>
                        setMoveMenuOpenForIdx((cur) => (cur === idx ? null : idx))
                      }
                    >
                      ↕
                    </button>
                    {moveMenuOpenForIdx === idx && (
                      <div className="itinerary-tl-move-menu" role="menu">
                        <div className="itinerary-tl-move-title">Hangi güne?</div>
                        {allDays
                          .filter((d) => d.dayNumber !== day.dayNumber)
                          .map((d) => (
                            <button
                              key={d.dayNumber}
                              type="button"
                              className="itinerary-tl-move-item"
                              onClick={() => {
                                onMoveItemToDay(day.dayNumber, idx, d.dayNumber);
                                setMoveMenuOpenForIdx(null);
                              }}
                            >
                              Gün {d.dayNumber} · {d.date.slice(5)}
                            </button>
                          ))}
                      </div>
                    )}
                  </div>
                )}
                <button
                  type="button"
                  className="itinerary-tl-remove"
                  aria-label="Sil"
                  onClick={() => onRemoveItem(day.dayNumber, it.id)}
                >
                  ×
                </button>
              </li>
            ))}
            {day.items.length === 0 && (
              <li className="itinerary-tl-empty">Bu güne aktivite ekleyin veya başka günden sürükleyin.</li>
            )}
          </ol>

          {dest && (
            <div className="itinerary-add-row">
              <button
                type="button"
                className="discover-trigger discover-trigger-block"
                onClick={handleModalOpen}
                title={`${dest.city || dest.countryName} keşif portalını aç`}
              >
                <span className="discover-trigger-plus" aria-hidden>+</span>
                <span className="discover-trigger-emoji" aria-hidden>🌍</span>
                Yeni durak ekle
              </button>
            </div>
          )}
        </div>
      )}

      {dest && (
        <PlaceDiscoveryModal
          open={discoverOpen}
          city={dest.city}
          country={dest.countryName}
          countryFlag={profile?.flag}
          fallbackPlaces={fallbackPlaces}
          onClose={handleModalClose}
          onPick={(place) => {
            onAddDiscoveredPlace?.(day.dayNumber, place);
            setPickedCountInRun((c) => c + 1);
          }}
        />
      )}
    </article>
  );
}
