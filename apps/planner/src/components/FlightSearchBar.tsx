import type { Pace } from '@japan-trip/shared';

export type TripType = 'roundtrip' | 'oneway' | 'multicity';

interface FlightSearchBarProps {
  tripType: TripType;
  onTripTypeChange: (t: TripType) => void;
  originCity: string;
  originAirport: string;
  onOriginCity: (v: string) => void;
  onOriginAirport: (v: string) => void;
  destCity: string;
  destAirport: string;
  onDestCity: (v: string) => void;
  onDestAirport: (v: string) => void;
  startDate: string;
  endDate: string;
  onStartDate: (v: string) => void;
  onEndDate: (v: string) => void;
  partySize: number;
  pace: Pace;
  onPartySize: (n: number) => void;
  onPace: (p: Pace) => void;
  onSwap: () => void;
  destLabel?: string;
  nearbyOrigin?: boolean;
  nearbyDest?: boolean;
  onNearbyOrigin?: (v: boolean) => void;
  onNearbyDest?: (v: boolean) => void;
  directOnly?: boolean;
  onDirectOnly?: (v: boolean) => void;
}

function formatPlace(city: string, airport: string) {
  if (!city && !airport) return '';
  if (city && airport) return `${city} (${airport})`;
  return city || airport;
}

function Cell({
  label,
  children,
  className = '',
}: {
  label: string;
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <div className={`flight-cell ${className}`}>
      <span className="flight-cell-label">{label}</span>
      <div className="flight-cell-body">{children}</div>
    </div>
  );
}

export function FlightSearchBar({
  tripType,
  onTripTypeChange,
  originCity,
  originAirport,
  onOriginCity,
  onOriginAirport,
  destCity,
  destAirport,
  onDestCity,
  onDestAirport,
  startDate,
  endDate,
  onStartDate,
  onEndDate,
  partySize,
  pace,
  onPartySize,
  onPace,
  onSwap,
  destLabel = 'Nereye',
  nearbyOrigin = false,
  nearbyDest = false,
  onNearbyOrigin,
  onNearbyDest,
  directOnly = false,
  onDirectOnly,
}: FlightSearchBarProps) {
  const showReturn = tripType !== 'oneway';

  return (
    <div className="flight-search-wrap">
      <div className="flight-search-meta">
        <label className="flight-trip-type">
          <span className="flight-trip-type-label">Seyahat tipi</span>
          <select
            value={tripType}
            onChange={(e) => onTripTypeChange(e.target.value as TripType)}
          >
            <option value="roundtrip">Gidiş dönüş</option>
            <option value="oneway">Tek yön</option>
            <option value="multicity">Çoklu durak</option>
          </select>
        </label>
      </div>

      <div className="flight-search-bar" role="group" aria-label="Rota ve tarihler">
        <Cell label="Kalkış" className="flight-cell-from">
          <input
            type="text"
            className="flight-input"
            placeholder="Şehir"
            value={originCity}
            onChange={(e) => onOriginCity(e.target.value)}
            aria-label="Kalkış şehri"
          />
          <input
            type="text"
            className="flight-input flight-input-sub"
            placeholder="Havalimanı kodu"
            value={originAirport}
            onChange={(e) => onOriginAirport(e.target.value)}
            aria-label="Kalkış havalimanı"
          />
        </Cell>

        <button
          type="button"
          className="flight-swap"
          onClick={onSwap}
          aria-label="Kalkış ve varışı değiştir"
          title="Değiştir"
        >
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" aria-hidden>
            <path
              d="M7 16V4M7 4L3 8M7 4L11 8M17 8V20M17 20L21 16M17 20L13 16"
              stroke="currentColor"
              strokeWidth="2"
              strokeLinecap="round"
              strokeLinejoin="round"
            />
          </svg>
        </button>

        <Cell label={destLabel} className="flight-cell-to">
          <input
            type="text"
            className="flight-input"
            placeholder="Ülke, şehir veya havaalanı"
            value={destCity}
            onChange={(e) => onDestCity(e.target.value)}
            aria-label="Varış şehri"
          />
          <input
            type="text"
            className="flight-input flight-input-sub"
            placeholder="Havalimanı kodu"
            value={destAirport}
            onChange={(e) => onDestAirport(e.target.value)}
            aria-label="Varış havalimanı"
          />
        </Cell>

        <Cell label="Gidiş" className="flight-cell-date">
          <input
            type="date"
            className="flight-input flight-input-date"
            value={startDate}
            onChange={(e) => onStartDate(e.target.value)}
            aria-label="Gidiş tarihi"
          />
        </Cell>

        {showReturn && (
          <Cell label="Dönüş" className="flight-cell-date">
            <input
              type="date"
              className="flight-input flight-input-date"
              value={endDate}
              min={startDate}
              onChange={(e) => onEndDate(e.target.value)}
              aria-label="Dönüş tarihi"
            />
          </Cell>
        )}

        <Cell label="Yolcular" className="flight-cell-pax">
          <select
            className="flight-input flight-select"
            value={partySize}
            onChange={(e) => onPartySize(Number(e.target.value))}
            aria-label="Yolcu sayısı"
          >
            {[1, 2, 3, 4, 5, 6].map((n) => (
              <option key={n} value={n}>
                {n} {n === 1 ? 'yetişkin' : 'yetişkin'}
              </option>
            ))}
          </select>
          <select
            className="flight-input flight-select flight-input-sub"
            value={pace}
            onChange={(e) => onPace(e.target.value as Pace)}
            aria-label="Tempo"
          >
            <option value="relaxed">Rahat tempo</option>
            <option value="moderate">Dengeli tempo</option>
            <option value="intense">Yoğun tempo</option>
          </select>
        </Cell>
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
        {onNearbyDest && (
          <label className="flight-check">
            <input
              type="checkbox"
              checked={nearbyDest}
              onChange={(e) => onNearbyDest(e.target.checked)}
            />
            Yakındaki havaalanları (varış)
          </label>
        )}
        {onDirectOnly && (
          <label className="flight-check">
            <input
              type="checkbox"
              checked={directOnly}
              onChange={(e) => onDirectOnly(e.target.checked)}
            />
            Aktarmasız uçuşlar
          </label>
        )}
      </div>
    </div>
  );
}

/** Görüntüleme için birleşik metin (opsiyonel) */
export { formatPlace };
