import { useEffect, useMemo, useRef, useState } from 'react';
import { fetchWikipediaThumbnail } from '../utils/wikipediaImage';
import { fetchWithTimeout } from '../utils/fetchWithTimeout';
import { useModalFocus } from '../hooks/useModalFocus';

export interface DiscoveredPlace {
  id: string;
  name: string;
  emoji?: string;
  category?: string;
  description?: string;
  tips?: string;
  typicalSteps?: number;
  imageQuery?: string;
  mapsQuery?: string;
  lat?: number;
  lng?: number;
  durationMin?: number;
  /** Yer hangi şehirde — şehirler arası transfer önerisi için. */
  city?: string;
}

interface Props {
  open: boolean;
  city?: string;
  country?: string;
  countryFlag?: string;
  /** AI'a ulaşılamazsa gösterilecek küratörlü liste (destination profile popularPlaces). */
  fallbackPlaces?: DiscoveredPlace[];
  onClose: () => void;
  onPick: (place: DiscoveredPlace) => void;
}

type Status = 'idle' | 'loading' | 'ok' | 'not-configured' | 'failed' | 'empty' | 'fallback';

const CATEGORY_LABELS: Record<string, { label: string; tint: string }> = {
  culture: { label: 'Kültür', tint: '#8b5cf6' },
  nature: { label: 'Doğa', tint: '#10b981' },
  food: { label: 'Yemek', tint: '#f59e0b' },
  fun: { label: 'Eğlence', tint: '#ec4899' },
  shopping: { label: 'Alışveriş', tint: '#0ea5e9' },
  transport: { label: 'Ulaşım', tint: '#64748b' },
};

function PlaceCard({
  place,
  picked,
  onPick,
}: {
  place: DiscoveredPlace;
  picked: boolean;
  onPick: () => void;
}) {
  const [img, setImg] = useState<string | null>(null);
  const [imgLoading, setImgLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;
    const q = place.imageQuery || place.name;
    if (!q) {
      setImgLoading(false);
      return;
    }
    setImgLoading(true);
    fetchWikipediaThumbnail(q)
      .then((url) => {
        if (!cancelled) {
          setImg(url);
          setImgLoading(false);
        }
      })
      .catch(() => {
        if (!cancelled) setImgLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [place.imageQuery, place.name]);

  const cat = place.category && CATEGORY_LABELS[place.category];

  return (
    <button
      type="button"
      className={`discover-card${picked ? ' picked' : ''}`}
      onClick={onPick}
      aria-pressed={picked}
    >
      <div className="discover-card-image">
        {img ? (
          <img src={img} alt={place.name} loading="lazy" />
        ) : (
          <div className="discover-card-image-fallback">
            <span style={{ fontSize: 48 }}>{place.emoji || '📍'}</span>
          </div>
        )}
        {imgLoading && <div className="discover-card-image-loading" aria-hidden />}
        {cat && (
          <span className="discover-card-cat" style={{ background: cat.tint }}>
            {cat.label}
          </span>
        )}
        {picked && (
          <span className="discover-card-check" aria-label="Eklendi">
            ✓
          </span>
        )}
      </div>
      <div className="discover-card-body">
        <div className="discover-card-title">
          <span className="discover-card-emoji">{place.emoji ?? '📍'}</span>
          <strong>{place.name}</strong>
        </div>
        {place.description && <p className="discover-card-desc">{place.description}</p>}
        {place.tips && <p className="discover-card-tip">💡 {place.tips}</p>}
      </div>
    </button>
  );
}

export function PlaceDiscoveryModal({
  open,
  city,
  country,
  countryFlag,
  fallbackPlaces,
  onClose,
  onPick,
}: Props) {
  const [status, setStatus] = useState<Status>('idle');
  const [places, setPlaces] = useState<DiscoveredPlace[]>([]);
  const [picked, setPicked] = useState<Set<string>>(new Set());
  const fallbackRef = useRef(fallbackPlaces);
  fallbackRef.current = fallbackPlaces;

  useEffect(() => {
    if (!open) return;
    setPlaces([]);
    setPicked(new Set());
    setStatus('loading');
    const params = new URLSearchParams();
    if (city) params.set('city', city);
    if (country) params.set('country', country);

    const useFallback = (reason: Status) => {
      const fb = fallbackRef.current;
      if (fb && fb.length > 0) {
        setPlaces(fb);
        setStatus('fallback');
      } else {
        setStatus(reason);
      }
    };

    let cancelled = false;
    fetchWithTimeout(`/api/discover?${params.toString()}`, { timeoutMs: 20_000 })
      .then(async (resp) => {
        if (cancelled) return;
        if (resp.status === 501) {
          setStatus('not-configured');
          return;
        }
        if (resp.status === 502 || !resp.ok) {
          useFallback('failed');
          return;
        }
        const data = (await resp.json()) as { places?: DiscoveredPlace[] };
        if (cancelled) return;
        const list = data.places ?? [];
        if (list.length) {
          setPlaces(list);
          setStatus('ok');
        } else {
          useFallback('empty');
        }
      })
      .catch(() => {
        if (!cancelled) useFallback('failed');
      });
    return () => {
      cancelled = true;
    };
  }, [open, city, country]);

  const headline = useMemo(() => {
    const flag = countryFlag ? `${countryFlag} ` : '';
    if (city && country) return `${flag}${city}, ${country}`;
    return `${flag}${city || country || ''}`;
  }, [city, country, countryFlag]);

  const modalRef = useModalFocus<HTMLDivElement>(open, onClose);

  if (!open) return null;

  const handlePick = (place: DiscoveredPlace) => {
    setPicked((cur) => {
      const next = new Set(cur);
      next.add(place.id);
      return next;
    });
    onPick(place);
  };

  return (
    <div className="modal-backdrop discover-backdrop" role="dialog" aria-modal="true" onClick={onClose}>
      <div className="discover-modal" ref={modalRef} onClick={(e) => e.stopPropagation()}>
        <header className="discover-head">
          <div>
            <div className="discover-overline">Keşif portalı</div>
            <h2 className="discover-title">{headline || 'Yer önerileri'}</h2>
            <p className="discover-sub">
              En çok ziyaret edilen yerler — kart üstüne tıklayınca plana eklenir.
            </p>
          </div>
          <button type="button" className="discover-close" onClick={onClose} aria-label="Kapat">
            ×
          </button>
        </header>

        <div className="discover-body">
          {status === 'loading' && (
            <div className="discover-state">
              <div className="discover-spinner" aria-hidden />
              <p>AI yer önerileri hazırlıyor…</p>
            </div>
          )}

          {status === 'not-configured' && (
            <div className="discover-state warn">
              <strong>GROQ_API_KEY tanımlı değil.</strong>
              <p>
                Keşif portalı için <code>.env</code> dosyasına anahtar ekle, sonra dev sunucusunu
                yeniden başlat.
              </p>
            </div>
          )}

          {status === 'failed' && (
            <div className="discover-state warn">
              <strong>AI ulaşılamadı.</strong>
              <p>Tekrar dene ya da daha sonra aç.</p>
            </div>
          )}

          {status === 'empty' && (
            <div className="discover-state">
              <p>Bu konum için öneri üretilemedi.</p>
            </div>
          )}

          {status === 'fallback' && (
            <>
              <div className="discover-state warn" style={{ marginBottom: 12 }}>
                <strong>AI şu an yanıt vermedi.</strong>
                <p>Küratörlü liste gösteriliyor — istediğinizi seçebilirsiniz.</p>
              </div>
              <div className="discover-grid">
                {places.map((p) => (
                  <PlaceCard
                    key={p.id}
                    place={p}
                    picked={picked.has(p.id)}
                    onPick={() => handlePick(p)}
                  />
                ))}
              </div>
            </>
          )}

          {status === 'ok' && (
            <div className="discover-grid">
              {places.map((p) => (
                <PlaceCard key={p.id} place={p} picked={picked.has(p.id)} onPick={() => handlePick(p)} />
              ))}
            </div>
          )}
        </div>

        <footer className="discover-foot">
          <span className="discover-foot-info">
            {picked.size > 0 ? `${picked.size} yer eklendi` : 'Birden fazla seçebilirsin'}
          </span>
          <button type="button" className="btn btn-primary" onClick={onClose}>
            Bitti
          </button>
        </footer>
      </div>
    </div>
  );
}
