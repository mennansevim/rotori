import { useEffect, useMemo, useRef, useState } from 'react';
import {
  getDestinationProfile,
  newItemId,
  optimizeDayItems,
  type DayPlan,
  type TimelineItem,
  type Trip,
} from '@japan-trip/shared';
import { DayPlanCard } from '../DayPlanCard';
import {
  generateItinerary,
  type ItineraryReason,
  type ItinerarySource,
} from '../../utils/itineraryLookup';

interface Props {
  trip: Trip;
  onChange: (updater: (t: Trip) => Trip) => void;
}

const PACE_LABELS: Record<string, string> = {
  relaxed: 'Rahat',
  moderate: 'Dengeli',
  intense: 'Yoğun',
};

export function PlanStep({ trip, onChange }: Props) {
  const destinations = useMemo(
    () => [...(trip.preferences.destinations ?? [])].sort((a, b) => a.order - b.order),
    [trip.preferences.destinations],
  );

  const [expanded, setExpanded] = useState<Set<number>>(
    () => new Set(trip.days.slice(0, 2).map((d) => d.dayNumber)),
  );
  const [generating, setGenerating] = useState(false);
  const [genSource, setGenSource] = useState<ItinerarySource | null>(null);
  const [genReason, setGenReason] = useState<ItineraryReason | null>(null);
  const [dragSource, setDragSource] = useState<{ dayNumber: number; index: number } | null>(null);
  const autoRanRef = useRef(false);

  const pace = trip.preferences.pace ?? 'moderate';
  const childrenCount = trip.preferences.childrenCount ?? 0;
  const totalDays = trip.days.length;

  const updateDays = (days: DayPlan[]) => {
    onChange((t) => ({ ...t, days }));
  };

  const updateDay = (dayNumber: number, patch: Partial<DayPlan>) => {
    onChange((t) => ({
      ...t,
      days: t.days.map((d) => (d.dayNumber === dayNumber ? { ...d, ...patch } : d)),
    }));
  };

  const updateItem = (dayNumber: number, itemId: string, patch: Partial<TimelineItem>) => {
    onChange((t) => ({
      ...t,
      days: t.days.map((d) =>
        d.dayNumber === dayNumber
          ? { ...d, items: d.items.map((it) => (it.id === itemId ? { ...it, ...patch } : it)) }
          : d,
      ),
    }));
  };

  const removeItem = (dayNumber: number, itemId: string) => {
    onChange((t) => ({
      ...t,
      days: t.days.map((d) =>
        d.dayNumber === dayNumber ? { ...d, items: d.items.filter((it) => it.id !== itemId) } : d,
      ),
    }));
  };

  const addItem = (dayNumber: number, title: string) => {
    const item: TimelineItem = {
      id: newItemId(dayNumber),
      title,
      kind: 'activity',
      time: '10:00',
      scheduledTime: '10:00',
    };
    onChange((t) => ({
      ...t,
      days: t.days.map((d) =>
        d.dayNumber === dayNumber ? { ...d, items: [...d.items, item] } : d,
      ),
    }));
  };

  const addDiscoveredPlace = (
    dayNumber: number,
    place: {
      id: string;
      name: string;
      emoji?: string;
      category?: string;
      description?: string;
      tips?: string;
      typicalSteps?: number;
      mapsQuery?: string;
      lat?: number;
      lng?: number;
      durationMin?: number;
    },
  ) => {
    onChange((t) => ({
      ...t,
      days: t.days.map((d) => {
        if (d.dayNumber !== dayNumber) return d;
        const usedTimes = new Set(d.items.map((it) => it.time).filter(Boolean));
        const slots = ['10:00', '11:30', '14:00', '15:30', '17:00', '19:00', '20:30'];
        const time = slots.find((s) => !usedTimes.has(s)) ?? '10:00';
        const item: TimelineItem = {
          id: newItemId(dayNumber),
          title: `${place.emoji ?? '📍'} ${place.name}`,
          description: place.description,
          tips: place.tips,
          kind:
            place.category === 'food'
              ? 'meal'
              : place.category === 'transport'
                ? 'transport'
                : 'activity',
          time,
          scheduledTime: time,
          mapUrl: place.mapsQuery
            ? `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(place.mapsQuery)}`
            : undefined,
          lat: place.lat,
          lng: place.lng,
          durationMin: place.durationMin,
        };
        return { ...d, items: [...d.items, item] };
      }),
    }));
  };

  const optimizeDay = (dayNumber: number) => {
    onChange((t) => ({
      ...t,
      days: t.days.map((d) =>
        d.dayNumber === dayNumber ? { ...d, items: optimizeDayItems(d.items) } : d,
      ),
    }));
  };

  const reorder = (dayNumber: number, from: number, to: number) => {
    if (from === to) return;
    onChange((t) => ({
      ...t,
      days: t.days.map((d) => {
        if (d.dayNumber !== dayNumber) return d;
        const items = [...d.items];
        const [moved] = items.splice(from, 1);
        items.splice(to, 0, moved);
        return { ...d, items };
      }),
    }));
  };

  const moveItemBetweenDays = (
    fromDay: number,
    fromIndex: number,
    toDay: number,
    toIndex?: number,
  ) => {
    onChange((t) => {
      const from = t.days.find((d) => d.dayNumber === fromDay);
      const to = t.days.find((d) => d.dayNumber === toDay);
      if (!from || !to) return t;
      const items = [...from.items];
      const [moved] = items.splice(fromIndex, 1);
      if (!moved) return t;
      const patched: TimelineItem = { ...moved, movedFromDay: fromDay };
      const destItems = [...to.items];
      const insertAt = toIndex ?? destItems.length;
      destItems.splice(insertAt, 0, patched);
      return {
        ...t,
        days: t.days.map((d) => {
          if (d.dayNumber === fromDay) return { ...d, items };
          if (d.dayNumber === toDay) return { ...d, items: destItems };
          return d;
        }),
      };
    });
  };

  const toggleExpanded = (dayNumber: number) => {
    setExpanded((prev) => {
      const next = new Set(prev);
      if (next.has(dayNumber)) next.delete(dayNumber);
      else next.add(dayNumber);
      return next;
    });
  };

  const handleGenerate = async () => {
    setGenerating(true);
    setGenSource(null);
    setGenReason(null);
    try {
      const result = await generateItinerary(trip);
      updateDays(result.days);
      setGenSource(result.source);
      setGenReason(result.reason);
      setExpanded(new Set(result.days.map((d) => d.dayNumber)));
    } finally {
      setGenerating(false);
    }
  };

  const allDaysEmpty = trip.days.length > 0 && trip.days.every((d) => d.items.length === 0);

  useEffect(() => {
    if (autoRanRef.current) return;
    if (!destinations.length) return;
    if (!allDaysEmpty) return;
    autoRanRef.current = true;
    void handleGenerate();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [destinations.length, allDaysEmpty]);

  const setPace = (p: 'relaxed' | 'moderate' | 'intense') => {
    onChange((t) => ({ ...t, preferences: { ...t.preferences, pace: p } }));
  };

  if (!destinations.length) {
    return (
      <>
        <h2 className="page-headline">Plan</h2>
        <p className="page-sub">Önce Rota adımında havaalanı/durak ekleyin.</p>
      </>
    );
  }

  const routeLabel = destinations
    .map((d) => {
      const flag = getDestinationProfile(d.countryCode)?.flag ?? '';
      return `${flag} ${d.city || d.countryName}`;
    })
    .join(' → ');

  return (
    <div className="plan-screen plan-screen-v2">
      <div className="plan-head">
        <h2 className="page-headline">Plan</h2>
        <p className="page-sub">
          {totalDays} gün · {routeLabel}
          {childrenCount > 0 && ` · ${childrenCount} çocuk`}
        </p>
      </div>

      <section className="plan-toolbar card">
        <div className="plan-toolbar-left">
          <span className="plan-toolbar-label">Tempo</span>
          <div className="pace-pills">
            {(['relaxed', 'moderate', 'intense'] as const).map((p) => (
              <button
                key={p}
                type="button"
                className={`pace-pill${pace === p ? ' active' : ''}`}
                onClick={() => setPace(p)}
              >
                {PACE_LABELS[p]}
              </button>
            ))}
          </div>
        </div>
        <div className="plan-toolbar-right">
          {genSource && (
            <span className="plan-gen-badge">
              {genSource === 'ai' ? '✨ AI planı' : '📋 Küratörlü plan'}
            </span>
          )}
          <button
            type="button"
            className="btn btn-primary"
            onClick={() => void handleGenerate()}
            disabled={generating}
          >
            {generating ? 'Oluşturuluyor…' : '✨ Rota oluştur'}
          </button>
        </div>
      </section>

      {genReason === 'not-configured' && (
        <div className="plan-banner plan-banner-warn">
          <strong>GROQ_API_KEY tanımlı değil.</strong> Detaylı AI planı için repo kökündeki{' '}
          <code>.env</code> dosyasına anahtarı ekle, sonra <code>npm run dev:planner</code>'ı
          yeniden başlat. Şu an küratörlü şablonlar kullanılıyor.
        </div>
      )}
      {genReason === 'ai-failed' && (
        <div className="plan-banner plan-banner-warn">
          <strong>AI yanıt vermedi.</strong> Geçici hata olabilir, tekrar deneyebilirsin. Şimdilik
          küratörlü şablonlar gösteriliyor.
        </div>
      )}
      {genReason === 'network' && (
        <div className="plan-banner plan-banner-warn">
          <strong>API'ye ulaşılamadı.</strong> Dev sunucusunu kontrol et veya tekrar dene.
        </div>
      )}

      <p className="plan-hint">
        Saat saat aktivite, ulaşım, restoran ve ipuçları AI tarafından üretilir. Ülkeye özel mutlaka
        görülmesi gereken yerler tempo ve konaklama günlerine göre dağıtılır. Günleri sürükleyerek
        düzenleyebilirsiniz.
      </p>

      <div className="itinerary-day-list">
        {trip.days.map((day) => (
          <DayPlanCard
            key={day.dayNumber}
            day={day}
            destinations={destinations}
            expanded={expanded.has(day.dayNumber)}
            onToggle={() => toggleExpanded(day.dayNumber)}
            dragSource={dragSource}
            onDragStart={(dayNumber, index) => setDragSource({ dayNumber, index })}
            onDragEnd={() => setDragSource(null)}
            onDropOnDay={(toDay, atIndex) => {
              if (!dragSource) return;
              moveItemBetweenDays(dragSource.dayNumber, dragSource.index, toDay, atIndex);
              setDragSource(null);
            }}
            onReorder={reorder}
            onUpdateDay={updateDay}
            onUpdateItem={updateItem}
            onRemoveItem={removeItem}
            onAddItem={addItem}
            onAddDiscoveredPlace={addDiscoveredPlace}
            onOptimizeDay={optimizeDay}
          />
        ))}
      </div>
    </div>
  );
}
