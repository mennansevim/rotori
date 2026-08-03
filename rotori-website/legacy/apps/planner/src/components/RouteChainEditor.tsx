import type { Airport, Pace } from '@japan-trip/shared';
import { AirportPicker } from './AirportPicker';

interface Props {
  originCode?: string;
  originLabel?: string;
  originSet: boolean;
  onOriginSelect: (airport: Airport) => void;
  travelStart: string;
  travelEnd: string;
  onTravelStart: (v: string) => void;
  onTravelEnd: (v: string) => void;
  hasStops: boolean;
  partySize: number;
  pace: Pace;
  childrenCount: number;
  onPartySize: (n: number) => void;
  onPace: (p: Pace) => void;
  onChildrenCount: (n: number) => void;
  nearbyOrigin?: boolean;
  onNearbyOrigin?: (v: boolean) => void;
  directOnly?: boolean;
  onDirectOnly?: (v: boolean) => void;
  children?: React.ReactNode;
}

export function RouteChainEditor({
  originCode,
  originLabel,
  originSet,
  onOriginSelect,
  travelStart,
  travelEnd,
  onTravelStart,
  onTravelEnd,
  hasStops,
  partySize,
  pace,
  childrenCount,
  onPartySize,
  onPace,
  onChildrenCount,
  nearbyOrigin = false,
  onNearbyOrigin,
  directOnly = false,
  onDirectOnly,
  children,
}: Props) {
  return (
    <div className="route-chain-wrap">
      <div className="route-chain">
        <div className="route-node route-node-origin">
          <span className="route-node-badge">Nereden</span>
          <div className="route-node-fields">
            <AirportPicker
              value={originCode}
              valueLabel={originLabel}
              placeholder="Kalkış havaalanı (örn. İstanbul, IST)"
              onSelect={onOriginSelect}
            />
            {originSet && (
              <div className="field route-reveal">
                <label>Gidiş tarihi</label>
                <input
                  type="date"
                  value={travelStart}
                  onChange={(e) => onTravelStart(e.target.value)}
                />
              </div>
            )}
          </div>
        </div>

        {originSet && children}

        {hasStops && (
          <>
            <div className="route-connector" aria-hidden>
              <span className="route-arrow">↓</span>
            </div>
            <div className="route-node route-node-return">
              <span className="route-node-badge">Eve dönüş</span>
              <div className="route-node-fields route-node-return-body">
                <p className="route-return-label">
                  {originLabel || 'Kalkış havaalanı'}
                  {originCode ? ` (${originCode})` : ''}
                </p>
                <div className="field">
                  <label>Dönüş tarihi</label>
                  <input
                    type="date"
                    value={travelEnd}
                    min={travelStart}
                    onChange={(e) => onTravelEnd(e.target.value)}
                  />
                </div>
              </div>
            </div>
          </>
        )}
      </div>

      {originSet && (
        <details className="route-advanced">
          <summary>Yolcu & seçenekler</summary>
          <div className="route-meta-row">
            <div className="field">
              <label>Yetişkin</label>
              <select value={partySize} onChange={(e) => onPartySize(Number(e.target.value))}>
                {[1, 2, 3, 4, 5, 6].map((n) => (
                  <option key={n} value={n}>
                    {n}
                  </option>
                ))}
              </select>
            </div>
            <div className="field">
              <label>Çocuk</label>
              <select
                value={childrenCount}
                onChange={(e) => onChildrenCount(Number(e.target.value))}
              >
                {[0, 1, 2, 3, 4].map((n) => (
                  <option key={n} value={n}>
                    {n}
                  </option>
                ))}
              </select>
            </div>
            <div className="field">
              <label>Tempo</label>
              <select value={pace} onChange={(e) => onPace(e.target.value as Pace)}>
                <option value="relaxed">Rahat</option>
                <option value="moderate">Dengeli</option>
                <option value="intense">Yoğun</option>
              </select>
            </div>
          </div>
          <div className="flight-search-options">
            {onNearbyOrigin && (
              <label className="flight-check">
                <input
                  type="checkbox"
                  checked={nearbyOrigin}
                  onChange={(e) => onNearbyOrigin(e.target.checked)}
                />
                Yakındaki havaalanları (kalkış)
              </label>
            )}
            {onDirectOnly && (
              <label className="flight-check">
                <input
                  type="checkbox"
                  checked={directOnly}
                  onChange={(e) => onDirectOnly(e.target.checked)}
                />
                Aktarmasız uçuşlar (mümkünse)
              </label>
            )}
          </div>
        </details>
      )}
    </div>
  );
}

export function RouteStopCard({
  index,
  flag,
  countryName,
  children,
  onRemove,
}: {
  index: number;
  flag?: string;
  countryName: string;
  children: React.ReactNode;
  onRemove: () => void;
}) {
  return (
    <>
      <div className="route-connector" aria-hidden>
        <span className="route-arrow">↓</span>
      </div>
      <div className="route-node route-node-stop">
        <div className="route-node-header">
          <span className="route-node-badge">
            {flag} Durak {index + 1}
          </span>
          <button type="button" className="hotel-remove" aria-label="Durak sil" onClick={onRemove}>
            ×
          </button>
        </div>
        {countryName && <p className="route-stop-country">{countryName}</p>}
        <div className="route-node-fields">{children}</div>
      </div>
    </>
  );
}
