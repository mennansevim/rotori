import { useMemo, useState } from 'react';
import {
  getDestinationProfile,
  newItemId,
  optimizeDayItems,
  type DayPlan,
  type InterestTag,
  type Pace,
  type TimelineItem,
  type TransportPreference,
  type Trip,
  type WalkingTarget,
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

const INTEREST_OPTIONS: { tag: InterestTag; emoji: string; label: string }[] = [
  { tag: 'temples', emoji: '⛩️', label: 'Tapınaklar' },
  { tag: 'traditional', emoji: '🎎', label: 'Geleneksel' },
  { tag: 'anime', emoji: '🎌', label: 'Anime & manga' },
  { tag: 'pokemon', emoji: '🎮', label: 'Pokemon & oyun' },
  { tag: 'tech', emoji: '💻', label: 'Teknoloji' },
  { tag: 'shopping', emoji: '🛍️', label: 'Alışveriş' },
  { tag: 'food', emoji: '🍣', label: 'Yemek odaklı' },
  { tag: 'theme_parks', emoji: '🎢', label: 'Tema parklar' },
  { tag: 'kids', emoji: '👶', label: 'Çocuk dostu' },
  { tag: 'photography', emoji: '📷', label: 'Fotoğrafçılık' },
];

const WALKING_OPTIONS: { value: WalkingTarget; emoji: string; label: string; hint: string }[] = [
  { value: 'light', emoji: '🚶', label: 'Az', hint: '~7k adım/gün' },
  { value: 'moderate', emoji: '🚶‍♂️', label: 'Orta', hint: '~11k adım/gün' },
  { value: 'intense', emoji: '🏃', label: 'Yoğun', hint: '~15k+ adım/gün' },
];

const TRANSPORT_OPTIONS: { value: TransportPreference; emoji: string; label: string }[] = [
  { value: 'transit', emoji: '🚇', label: 'Toplu taşıma' },
  { value: 'mixed', emoji: '🔀', label: 'Karışık' },
  { value: 'taxi_assisted', emoji: '🚕', label: 'Taksi destekli' },
  { value: 'walking', emoji: '🚶', label: 'Yürüyüş ağırlıklı' },
];

const PACE_OPTIONS: { value: Pace; label: string; hint: string }[] = [
  { value: 'relaxed', label: 'Rahat', hint: 'Az durak, uzun molalar' },
  { value: 'moderate', label: 'Dengeli', hint: 'Standart tempo' },
  { value: 'intense', label: 'Yoğun', hint: 'Çok yer, sıkı program' },
];

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
  const [wizardOpen, setWizardOpen] = useState(false);
  const [mustSeeDraft, setMustSeeDraft] = useState('');
  const [notesDraft, setNotesDraft] = useState('');

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

  const openWizard = () => {
    setMustSeeDraft((trip.preferences.mustSee ?? []).join(', '));
    setNotesDraft(trip.subtitle ?? '');
    setWizardOpen(true);
  };

  const handleWizardGenerate = async () => {
    const mustSee = mustSeeDraft
      .split(',')
      .map((s) => s.trim())
      .filter(Boolean);
    onChange((t) => ({
      ...t,
      subtitle: notesDraft.trim() || t.subtitle,
      preferences: { ...t.preferences, mustSee },
    }));
    setWizardOpen(false);
    await handleGenerate();
  };

  const toggleInterest = (tag: InterestTag) => {
    onChange((t) => {
      const cur = new Set(t.preferences.interests ?? []);
      if (cur.has(tag)) cur.delete(tag);
      else cur.add(tag);
      return { ...t, preferences: { ...t.preferences, interests: [...cur] } };
    });
  };

  const setWalking = (w: WalkingTarget) => {
    onChange((t) => ({ ...t, preferences: { ...t.preferences, walkingTarget: w } }));
  };

  const setTransport = (tp: TransportPreference) => {
    onChange((t) => ({ ...t, preferences: { ...t.preferences, transportPreference: tp } }));
  };

  const allDaysEmpty = trip.days.length > 0 && trip.days.every((d) => d.items.length === 0);
  const totalSteps = trip.days.reduce((sum, d) => sum + (d.stepsEstimate ?? 0), 0);

  const setPace = (p: 'relaxed' | 'moderate' | 'intense') => {
    onChange((t) => ({ ...t, preferences: { ...t.preferences, pace: p } }));
  };

  const interestSet = new Set(trip.preferences.interests ?? []);
  const currentWalking = trip.preferences.walkingTarget ?? 'moderate';
  const currentTransport = trip.preferences.transportPreference ?? 'transit';

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
          {totalSteps > 0 && (
            <span className="plan-toolbar-steps" title="Tahmini toplam adım">
              👣 {(totalSteps / 1000).toFixed(0)}k adım
            </span>
          )}
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
            onClick={openWizard}
            disabled={generating}
          >
            {generating ? 'Oluşturuluyor…' : '✨ Gezi planı oluştur'}
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

      {allDaysEmpty && !generating ? (
        <div className="plan-empty">
          <div className="plan-empty-icon">🗺️</div>
          <h3>Henüz gezi planı yok</h3>
          <p>
            Yukarıdaki <strong>Gezi planı oluştur</strong> butonuyla {totalDays} günlük programı
            saat saat hazırlayalım.
          </p>
        </div>
      ) : (
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
      )}

      {wizardOpen && (
        <div
          className="modal-backdrop"
          role="dialog"
          aria-modal="true"
          onClick={() => setWizardOpen(false)}
        >
          <div
            className="modal plan-wizard"
            onClick={(e) => e.stopPropagation()}
          >
            <h3>✨ Optimum gezi planı</h3>
            <p className="plan-wizard-sub">
              Birkaç tercihini söyle, sana en uygun {totalDays} günlük programı saat saat
              kuralım.
            </p>

            <div className="plan-wizard-section">
              <div className="plan-wizard-label">İlgi alanların</div>
              <div className="plan-wizard-chips">
                {INTEREST_OPTIONS.map((o) => (
                  <button
                    key={o.tag}
                    type="button"
                    className={`chip${interestSet.has(o.tag) ? ' chip-active' : ''}`}
                    onClick={() => toggleInterest(o.tag)}
                  >
                    {o.emoji} {o.label}
                  </button>
                ))}
              </div>
            </div>

            <div className="plan-wizard-section">
              <div className="plan-wizard-label">Yürüyüş tempon</div>
              <div className="plan-wizard-chips">
                {WALKING_OPTIONS.map((o) => (
                  <button
                    key={o.value}
                    type="button"
                    className={`chip${currentWalking === o.value ? ' chip-active' : ''}`}
                    onClick={() => setWalking(o.value)}
                  >
                    {o.emoji} {o.label} <span className="chip-hint">· {o.hint}</span>
                  </button>
                ))}
              </div>
            </div>

            <div className="plan-wizard-section">
              <div className="plan-wizard-label">Ulaşım tercihi</div>
              <div className="plan-wizard-chips">
                {TRANSPORT_OPTIONS.map((o) => (
                  <button
                    key={o.value}
                    type="button"
                    className={`chip${currentTransport === o.value ? ' chip-active' : ''}`}
                    onClick={() => setTransport(o.value)}
                  >
                    {o.emoji} {o.label}
                  </button>
                ))}
              </div>
            </div>

            <div className="plan-wizard-section">
              <div className="plan-wizard-label">Plan temposu</div>
              <div className="plan-wizard-chips">
                {PACE_OPTIONS.map((o) => (
                  <button
                    key={o.value}
                    type="button"
                    className={`chip${pace === o.value ? ' chip-active' : ''}`}
                    onClick={() => setPace(o.value)}
                  >
                    {o.label} <span className="chip-hint">· {o.hint}</span>
                  </button>
                ))}
              </div>
            </div>

            <div className="plan-wizard-section">
              <label className="plan-wizard-label" htmlFor="plan-mustsee">
                Mutlaka görmek istediklerin
              </label>
              <input
                id="plan-mustsee"
                type="text"
                className="plan-wizard-input"
                placeholder="Skytree, Fushimi Inari, teamLab… (virgülle ayır)"
                value={mustSeeDraft}
                onChange={(e) => setMustSeeDraft(e.target.value)}
              />
            </div>

            <div className="plan-wizard-section">
              <label className="plan-wizard-label" htmlFor="plan-notes">
                Notlar (opsiyonel)
              </label>
              <textarea
                id="plan-notes"
                className="plan-wizard-input plan-wizard-textarea"
                placeholder="Örn: Sushi sevmem, deniz ürünü yemem, çocuk dostu yerler önemli…"
                rows={3}
                value={notesDraft}
                onChange={(e) => setNotesDraft(e.target.value)}
              />
            </div>

            <div className="modal-actions">
              <button
                type="button"
                className="btn btn-secondary"
                onClick={() => setWizardOpen(false)}
              >
                Vazgeç
              </button>
              <button
                type="button"
                className="btn btn-primary"
                onClick={() => void handleWizardGenerate()}
                disabled={generating}
              >
                {generating ? 'Oluşturuluyor…' : '✨ Optimum planı oluştur'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
