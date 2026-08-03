import { useEffect, useState } from 'react';
import {
  getDestinationProfile,
  newTicketId,
  newDestinationId,
  isTransportTicket,
  syncTripFromDestinations,
  defaultFoodPrefsForDestination,
  getRouteLegs,
  formatRouteChain,
  airlineLabel,
  MAX_TRIP_DAYS,
  type Airport,
  type Airline,
  type Trip,
  type TripDestination,
  type TicketKind,
} from '@japan-trip/shared';

function addDays(iso: string, days: number): string {
  const d = new Date(iso + 'T00:00:00Z');
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}
import { AirportPicker } from '../AirportPicker';
import { AirlinePicker } from '../AirlinePicker';
import { TicketCard } from '../TicketCard';
import { AirportGuide } from '../AirportGuide';
import {
  extractTextFromImage,
  parseTicketFromText,
  readFileAsDataUrl,
} from '../../utils/ocr';
import {
  lookupFlight,
  toAirport,
  flightSearchUrl,
  flightradarUrl,
  FlightLookupNotConfigured,
} from '../../utils/flightLookup';

interface Props {
  trip: Trip;
  onChange: (updater: (t: Trip) => Trip) => void;
  /** "🇯🇵 Japonya planını yükle" butonu için hook. */
  onLoadJapanPlan?: () => void;
}

const JAPAN_AIRPORTS = ['HND', 'NRT', 'KIX'] as const;

export function JourneyStep({ trip, onChange, onLoadJapanPlan }: Props) {
  const [scanning, setScanning] = useState(false);
  const [scanTarget, setScanTarget] = useState<string | null>(null);
  const [lookupBusy, setLookupBusy] = useState<number | null>(null);
  const [lookupMsg, setLookupMsg] = useState<Record<number, string>>({});

  const origin = trip.preferences.originCity ?? trip.flights.outbound[0]?.city ?? '';
  const originAirport = trip.preferences.originAirport ?? trip.flights.outbound[0]?.airport ?? '';
  const originSet = Boolean(originAirport);
  const destinations = [...(trip.preferences.destinations ?? [])].sort((a, b) => a.order - b.order);
  const transportTickets = trip.tickets.filter((t) => isTransportTicket(t.kind));
  const routePreview = formatRouteChain(getRouteLegs(trip));

  // Japonya-odaklı uygulama: ilk açılışta destinasyon boşsa otomatik Japonya kur.
  useEffect(() => {
    if ((trip.preferences.destinations ?? []).length > 0) return;
    onChange((t) => {
      const start = t.preferences.travelDates.start;
      const end = t.preferences.travelDates.end;
      const dest: TripDestination = {
        id: newDestinationId(),
        countryCode: 'JP',
        countryName: 'Japonya',
        city: 'Tokyo',
        airport: 'HND',
        arrivalDate: start,
        departureDate: end,
        order: 0,
      };
      const food = [defaultFoodPrefsForDestination(dest)];
      return syncTripFromDestinations(t, {
        originCity: t.preferences.originCity ?? '',
        originAirport: t.preferences.originAirport,
        destinations: [dest],
        destinationFood: food,
        travelStart: start,
        travelEnd: end,
      });
    });
  }, []);

  /** Tarihleri zincire göre yeniden hesaplayıp günleri üretir. */
  const commitDests = (
    t: Trip,
    rawDests: TripDestination[],
    returnDateOverride?: string,
  ): Trip => {
    const ordered = [...rawDests]
      .sort((a, b) => a.order - b.order)
      .map((d, i) => ({ ...d, order: i }));
    const travelStart = ordered[0]?.arrivalDate ?? t.preferences.travelDates.start;
    let returnDate = returnDateOverride ?? t.preferences.travelDates.end;
    const lastArrival = ordered[ordered.length - 1]?.arrivalDate ?? travelStart;
    if (returnDate < lastArrival) returnDate = lastArrival;
    for (let i = 0; i < ordered.length; i++) {
      ordered[i].departureDate = ordered[i + 1]?.arrivalDate ?? returnDate;
    }
    const food = (t.preferences.destinationFood ?? []).filter((f) =>
      ordered.some((d) => d.id === f.destinationId),
    );
    const foodIds = new Set(food.map((f) => f.destinationId));
    for (const d of ordered) if (!foodIds.has(d.id)) food.push(defaultFoodPrefsForDestination(d));

    return syncTripFromDestinations(
      { ...t, preferences: { ...t.preferences, tripType: 'multicity' } },
      {
        originCity: t.preferences.originCity ?? '',
        originAirport: t.preferences.originAirport,
        originLat: t.preferences.originLat,
        originLng: t.preferences.originLng,
        destinations: ordered,
        destinationFood: food,
        travelStart,
        travelEnd: returnDate,
      },
    );
  };

  const makeEmptyDest = (t: Trip, order: number): TripDestination => ({
    id: newDestinationId(),
    countryCode: '',
    countryName: '',
    city: '',
    airport: '',
    arrivalDate: t.preferences.travelDates.start,
    departureDate: t.preferences.travelDates.end,
    order,
  });

  /** legIndex'teki uçuşu (varış durağını) günceller; yoksa oluşturur. */
  const updateLeg = (legIndex: number, patch: Partial<TripDestination>) => {
    onChange((t) => {
      let dests = [...(t.preferences.destinations ?? [])].sort((a, b) => a.order - b.order);
      while (legIndex >= dests.length) {
        dests.push(makeEmptyDest(t, dests.length));
      }
      dests = dests.map((d, i) => (i === legIndex ? { ...d, ...patch } : d));
      return commitDests(t, dests);
    });
  };

  const setOrigin = (a: Airport) => {
    onChange((t) => {
      const t2 = {
        ...t,
        preferences: {
          ...t.preferences,
          originCity: a.city,
          originAirport: a.iata,
          originLat: a.lat,
          originLng: a.lng,
        },
      };
      return commitDests(t2, [...(t2.preferences.destinations ?? [])]);
    });
  };

  const setArrivalAirport = (legIndex: number, a: Airport) => {
    const profile = getDestinationProfile(a.countryCode);
    updateLeg(legIndex, {
      countryCode: a.countryCode,
      countryName: profile?.name ?? a.countryName,
      city: a.city,
      airport: a.iata,
      lat: a.lat,
      lng: a.lng,
    });
  };

  const setReturnDate = (date: string) => {
    onChange((t) => {
      const start = t.preferences.travelDates.start;
      const maxEnd = start ? addDays(start, MAX_TRIP_DAYS - 1) : date;
      const clamped = date > maxEnd ? maxEnd : date;
      return commitDests(t, [...(t.preferences.destinations ?? [])], clamped);
    });
  };

  const lookupLeg = async (legIndex: number) => {
    const dest = destinations[legIndex];
    const airline = dest?.airline;
    const flightNo = dest?.flightNo;
    const date = dest?.arrivalDate ?? trip.preferences.travelDates.start;
    if (!airline || !flightNo) return;
    setLookupBusy(legIndex);
    setLookupMsg((m) => ({ ...m, [legIndex]: '' }));
    try {
      const res = await lookupFlight(airline, flightNo, date);
      if (!res) {
        setLookupMsg((m) => ({
          ...m,
          [legIndex]: 'Bu uçuş/tarih için kayıt bulunamadı. Bilgileri elle girebilirsiniz.',
        }));
        return;
      }
      if (legIndex === 0 && res.departure) {
        setOrigin(toAirport(res.departure));
      }
      if (res.arrival) {
        setArrivalAirport(legIndex, toAirport(res.arrival));
      }
      const parts: string[] = [];
      if (res.departure?.iata && res.arrival?.iata)
        parts.push(`${res.departure.iata} → ${res.arrival.iata}`);
      if (res.departureTime) parts.push(`Kalkış ${res.departureTime}`);
      if (res.arrivalTime) parts.push(`Varış ${res.arrivalTime}`);
      setLookupMsg((m) => ({
        ...m,
        [legIndex]: parts.length ? `✓ ${parts.join(' · ')}` : '✓ Uçuş bulundu',
      }));
    } catch (err) {
      setLookupMsg((m) => ({
        ...m,
        [legIndex]:
          err instanceof FlightLookupNotConfigured
            ? 'Uçuş arama servisi yapılandırılmadı (API anahtarı gerekli).'
            : 'Arama başarısız. İnternet veya servis sorunu olabilir.',
      }));
    } finally {
      setLookupBusy(null);
    }
  };

  const setReturnAirline = (code: string) =>
    onChange((t) => ({ ...t, preferences: { ...t.preferences, returnAirline: code } }));
  const setReturnFlightNo = (no: string) =>
    onChange((t) => ({ ...t, preferences: { ...t.preferences, returnFlightNo: no } }));

  const RETURN_KEY = -1;

  const lookupReturn = async () => {
    const airline = trip.preferences.returnAirline;
    const flightNo = trip.preferences.returnFlightNo;
    const date = trip.preferences.travelDates.end;
    if (!airline || !flightNo) return;
    setLookupBusy(RETURN_KEY);
    setLookupMsg((m) => ({ ...m, [RETURN_KEY]: '' }));
    try {
      const res = await lookupFlight(airline, flightNo, date);
      if (!res) {
        setLookupMsg((m) => ({
          ...m,
          [RETURN_KEY]: 'Bu uçuş/tarih için kayıt bulunamadı. Tarihi elle girebilirsiniz.',
        }));
        return;
      }
      if (res.departureDate) setReturnDate(res.departureDate);
      const parts: string[] = [];
      if (res.departure?.iata && res.arrival?.iata)
        parts.push(`${res.departure.iata} → ${res.arrival.iata}`);
      if (res.departureTime) parts.push(`Kalkış ${res.departureTime}`);
      if (res.arrivalTime) parts.push(`Varış ${res.arrivalTime}`);
      let msg = parts.length ? `✓ ${parts.join(' · ')}` : '✓ Uçuş bulundu';
      if (res.arrival?.iata && originAirport && res.arrival.iata !== originAirport) {
        msg += ` (Not: varış ${res.arrival.iata}, başlangıç ${originAirport}'dan farklı)`;
      }
      setLookupMsg((m) => ({ ...m, [RETURN_KEY]: msg }));
    } catch (err) {
      setLookupMsg((m) => ({
        ...m,
        [RETURN_KEY]:
          err instanceof FlightLookupNotConfigured
            ? 'Uçuş arama servisi yapılandırılmadı (API anahtarı gerekli).'
            : 'Arama başarısız. İnternet veya servis sorunu olabilir.',
      }));
    } finally {
      setLookupBusy(null);
    }
  };

  const processImage = async (file: File, ticketId: string) => {
    setScanning(true);
    setScanTarget(ticketId);
    try {
      const [text, dataUrl] = await Promise.all([
        extractTextFromImage(file),
        readFileAsDataUrl(file),
      ]);
      const parsed = parseTicketFromText(text);
      onChange((t) => ({
        ...t,
        tickets: t.tickets.map((tk) =>
          tk.id === ticketId
            ? {
                ...tk,
                imageDataUrl: dataUrl,
                scannedText: text.slice(0, 2000),
                label: parsed.label ?? tk.label,
                visitDate: parsed.visitDate ?? tk.visitDate,
              }
            : tk,
        ),
      }));
    } catch {
      alert('Fotoğraf okunamadı.');
    } finally {
      setScanning(false);
      setScanTarget(null);
    }
  };

  const canContinue =
    originSet && destinations.length > 0 && destinations.every((d) => d.city.trim());

  const lastDest = destinations[destinations.length - 1];
  const hasTicket = trip.preferences.hasTicket !== false;
  const showReturn = Boolean(lastDest?.airport);

  // Render edilecek uçuş kartları: en az bir tane (ilk uçuş) her zaman görünür.
  const cards: { index: number; dest?: TripDestination }[] =
    destinations.length > 0
      ? destinations.map((dest, index) => ({ index, dest }))
      : [{ index: 0, dest: undefined }];

  const fromLabelFor = (index: number) =>
    index === 0
      ? origin
        ? `${origin}${originAirport ? ` (${originAirport})` : ''}`
        : ''
      : `${destinations[index - 1]?.city ?? ''}${
          destinations[index - 1]?.airport ? ` (${destinations[index - 1]?.airport})` : ''
        }`;

  return (
    <>
      <h2 className="page-headline">🇯🇵 Japonya rotası</h2>
      <p className="page-sub">
        {hasTicket
          ? 'Türkiye\'den Japonya\'ya gidiş ve dönüş uçuşlarını numarasıyla gir. "🔎 Uçuşu internetten bul" ile kalkış/varış saatleri otomatik dolar. Her uçuş kartının altında havaalanı rehberi var.'
          : 'Türkiye\'den nereden kalkacaksın ve Japonya\'da hangi şehre ineceksin? Bileti sonra ayırtacaksın, şimdilik şehir ve tarih yeter.'}
      </p>
      {onLoadJapanPlan && (
        <div className="japan-load-banner">
          <div>
            <strong>🇯🇵 Japonya 14 günlük tam plan</strong>
            <p>Tokyo → Kyoto → Nara → Osaka rotası; günler, tarihler ve oteller hazır.</p>
          </div>
          <button type="button" className="btn btn-primary btn-sm" onClick={onLoadJapanPlan}>
            Planı yükle
          </button>
        </div>
      )}

      <div className="flight-legs">
        {cards.map(({ index, dest }) => {
          const airline = dest?.airline;
          const flightNo = dest?.flightNo ?? '';
          const arrivalAirport = dest?.airport;
          const arrivalLabel = dest?.city
            ? `${dest.city}${dest.airport ? ` (${dest.airport})` : ''}`
            : undefined;
          const profile = getDestinationProfile(dest?.countryCode ?? '');
          const airlineSet = Boolean(airline);
          const fromSet = index === 0 ? originSet : true;

          return (
            <div className="flight-leg" key={dest?.id ?? `leg-${index}`}>
              <div className="flight-leg-head">
                <span className="flight-leg-num">
                  {hasTicket ? '✈︎ Gidiş — Türkiye → Japonya' : '📍 Rota — Türkiye → Japonya'}
                </span>
              </div>

              {hasTicket && (
                <div className="field">
                  <label>Havayolu</label>
                  <AirlinePicker
                    value={airline || undefined}
                    valueLabel={airline ? airlineLabel(airline) : undefined}
                    onSelect={(a: Airline) => updateLeg(index, { airline: a.code })}
                  />
                </div>
              )}

              {hasTicket && airlineSet && (
                <div className="field route-reveal">
                  <label>Uçuş numarası</label>
                  <div className="flightno-input">
                    <span className="flightno-prefix">{airline}</span>
                    <input
                      type="text"
                      inputMode="numeric"
                      placeholder="Uçuş numarası"
                      value={flightNo}
                      onChange={(e) =>
                        updateLeg(index, { flightNo: e.target.value.replace(/\s+/g, '') })
                      }
                    />
                  </div>
                </div>
              )}

              {(!hasTicket || (airlineSet && flightNo.trim())) && (
                <div className="field route-reveal">
                  <label>Tarih</label>
                  <input
                    type="date"
                    className="flight-leg-date"
                    value={dest?.arrivalDate ?? trip.preferences.travelDates.start}
                    onChange={(e) => updateLeg(index, { arrivalDate: e.target.value })}
                  />
                </div>
              )}

              {hasTicket && airlineSet && flightNo.trim() && (
                <div className="route-reveal flight-lookup-row">
                  <button
                    type="button"
                    className="btn btn-secondary btn-sm"
                    disabled={lookupBusy === index}
                    onClick={() => lookupLeg(index)}
                  >
                    {lookupBusy === index ? 'Araştırılıyor…' : '🔎 Uçuşu internetten bul'}
                  </button>
                  <a
                    className="flight-search-link"
                    href={flightSearchUrl(airline ?? '', flightNo, dest?.arrivalDate)}
                    target="_blank"
                    rel="noreferrer"
                  >
                    🌐 Web'de ara
                  </a>
                  <a
                    className="flight-search-link"
                    href={flightradarUrl(airline ?? '', flightNo)}
                    target="_blank"
                    rel="noreferrer"
                  >
                    Flightradar24
                  </a>
                  {lookupMsg[index] && <span className="flight-lookup-msg">{lookupMsg[index]}</span>}
                </div>
              )}

              {(!hasTicket || airlineSet) && (
                <div className="field route-reveal">
                  <label>Kalkış (Türkiye)</label>
                  {index === 0 ? (
                    <AirportPicker
                      value={originAirport || undefined}
                      valueLabel={origin || undefined}
                      placeholder="İstanbul (IST), Sabiha Gökçen (SAW)..."
                      countryCodes={['TR']}
                      onSelect={setOrigin}
                    />
                  ) : (
                    <div className="flight-from-fixed">{fromLabelFor(index) || '—'}</div>
                  )}
                </div>
              )}

              {(!hasTicket || (airlineSet && fromSet)) && (
                <div className="field route-reveal">
                  <label>Varış (Japonya)</label>
                  <AirportPicker
                    value={arrivalAirport || undefined}
                    valueLabel={arrivalLabel}
                    placeholder="Tokyo Haneda (HND), Narita (NRT), Osaka Kansai (KIX)"
                    countryCodes={['JP']}
                    onSelect={(a) => setArrivalAirport(index, a)}
                  />
                  {dest?.countryName && (
                    <p className="route-stop-country">
                      {profile?.flag} {dest.countryName}
                    </p>
                  )}
                </div>
              )}

              {(originAirport || arrivalAirport) && (
                <div className="airport-guides">
                  {originAirport && index === 0 && (
                    <AirportGuide iata={originAirport} role="origin" />
                  )}
                  {arrivalAirport && JAPAN_AIRPORTS.includes(arrivalAirport as 'HND' | 'NRT' | 'KIX') && (
                    <AirportGuide iata={arrivalAirport} role="destination" />
                  )}
                </div>
              )}
            </div>
          );
        })}

        {showReturn && (
          <div className="flight-leg flight-leg-return">
            <div className="flight-leg-head">
              <span className="flight-leg-num">🏠 Dönüş — Japonya → Türkiye</span>
              {hasTicket && <span className="flight-leg-hint">uçuş no ile bul</span>}
            </div>
            {hasTicket && (
              <div className="field">
                <label>Havayolu</label>
                <AirlinePicker
                  value={trip.preferences.returnAirline || undefined}
                  valueLabel={
                    trip.preferences.returnAirline
                      ? airlineLabel(trip.preferences.returnAirline)
                      : undefined
                  }
                  onSelect={(a: Airline) => setReturnAirline(a.code)}
                />
              </div>
            )}
            {hasTicket && trip.preferences.returnAirline && (
              <div className="field route-reveal">
                <label>Uçuş numarası</label>
                <div className="flightno-input">
                  <span className="flightno-prefix">{trip.preferences.returnAirline}</span>
                  <input
                    type="text"
                    inputMode="numeric"
                    placeholder="Uçuş numarası"
                    value={trip.preferences.returnFlightNo ?? ''}
                    onChange={(e) => setReturnFlightNo(e.target.value.replace(/\s+/g, ''))}
                  />
                </div>
              </div>
            )}
            {(!hasTicket ||
              (trip.preferences.returnAirline &&
                (trip.preferences.returnFlightNo ?? '').trim())) && (
              <div className="field route-reveal">
                <label>Tarih</label>
                <input
                  type="date"
                  className="flight-leg-date"
                  value={trip.preferences.travelDates.end}
                  min={lastDest?.arrivalDate}
                  max={
                    trip.preferences.travelDates.start
                      ? addDays(trip.preferences.travelDates.start, MAX_TRIP_DAYS - 1)
                      : undefined
                  }
                  onChange={(e) => setReturnDate(e.target.value)}
                />
              </div>
            )}
            {hasTicket && trip.preferences.returnAirline && (trip.preferences.returnFlightNo ?? '').trim() && (
              <>
                <div className="route-reveal flight-lookup-row">
                  <button
                    type="button"
                    className="btn btn-secondary btn-sm"
                    disabled={lookupBusy === RETURN_KEY}
                    onClick={lookupReturn}
                  >
                    {lookupBusy === RETURN_KEY ? 'Araştırılıyor…' : '🔎 Uçuşu internetten bul'}
                  </button>
                  <a
                    className="flight-search-link"
                    href={flightSearchUrl(
                      trip.preferences.returnAirline ?? '',
                      trip.preferences.returnFlightNo ?? '',
                      trip.preferences.travelDates.end,
                    )}
                    target="_blank"
                    rel="noreferrer"
                  >
                    🌐 Web'de ara
                  </a>
                  <a
                    className="flight-search-link"
                    href={flightradarUrl(
                      trip.preferences.returnAirline ?? '',
                      trip.preferences.returnFlightNo ?? '',
                    )}
                    target="_blank"
                    rel="noreferrer"
                  >
                    Flightradar24
                  </a>
                  {lookupMsg[RETURN_KEY] && (
                    <span className="flight-lookup-msg">{lookupMsg[RETURN_KEY]}</span>
                  )}
                </div>
              </>
            )}
            <div className="field route-reveal">
              <label>Kalkış (Japonya)</label>
              <div className="flight-from-fixed">
                {lastDest?.city}
                {lastDest?.airport ? ` (${lastDest.airport})` : ''}
              </div>
            </div>
            <div className="field route-reveal">
              <label>Varış (Türkiye)</label>
              <div className="flight-from-fixed">
                {origin}
                {originAirport ? ` (${originAirport})` : ''}
              </div>
            </div>
            {lastDest?.airport &&
              JAPAN_AIRPORTS.includes(lastDest.airport as 'HND' | 'NRT' | 'KIX') && (
                <div className="airport-guides">
                  <AirportGuide iata={lastDest.airport} role="return-origin" />
                </div>
              )}
          </div>
        )}
      </div>

      {destinations.length > 0 && routePreview && (
        <p className="route-preview">
          <strong>Rota:</strong> {routePreview}
        </p>
      )}

      {destinations.length > 0 && (
        <details className="route-advanced">
          <summary>Yolcu & seçenekler</summary>
          <div className="route-meta-row">
            <div className="field">
              <label>Yetişkin</label>
              <select
                value={trip.preferences.partySize ?? 2}
                onChange={(e) =>
                  onChange((t) => ({
                    ...t,
                    preferences: { ...t.preferences, partySize: Number(e.target.value) },
                  }))
                }
              >
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
                value={trip.preferences.childrenCount ?? 0}
                onChange={(e) =>
                  onChange((t) => ({
                    ...t,
                    preferences: { ...t.preferences, childrenCount: Number(e.target.value) },
                  }))
                }
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
              <select
                value={trip.preferences.pace}
                onChange={(e) =>
                  onChange((t) => ({
                    ...t,
                    preferences: { ...t.preferences, pace: e.target.value as Trip['preferences']['pace'] },
                  }))
                }
              >
                <option value="relaxed">Rahat</option>
                <option value="moderate">Dengeli</option>
                <option value="intense">Yoğun</option>
              </select>
            </div>
          </div>
        </details>
      )}

      {destinations.length > 0 && (
        <details className="card route-tickets">
          <summary className="card-title">Ulaşım biletleri (opsiyonel)</summary>
          <div className="route-tickets-body">
            {transportTickets.map((tk) => {
              const idx = trip.tickets.findIndex((x) => x.id === tk.id);
              return (
                <TicketCard
                  key={tk.id}
                  ticket={tk}
                  scanning={scanning && scanTarget === tk.id}
                  showKind
                  onUpdate={(patch) =>
                    onChange((t) => {
                      const tickets = [...t.tickets];
                      tickets[idx] = { ...tickets[idx], ...patch };
                      return { ...t, tickets };
                    })
                  }
                  onRemove={() =>
                    onChange((t) => ({
                      ...t,
                      tickets: t.tickets.filter((x) => x.id !== tk.id),
                    }))
                  }
                  onScanFile={(f) => f && void processImage(f, tk.id)}
                />
              );
            })}
            <button
              type="button"
              className="btn btn-secondary btn-sm"
              onClick={() =>
                onChange((t) => ({
                  ...t,
                  tickets: [
                    ...t.tickets,
                    {
                      id: newTicketId(),
                      kind: 'flight' as TicketKind,
                      label: 'Uçak bileti',
                      purchased: false,
                      emoji: '✈️',
                    },
                  ],
                }))
              }
            >
              + Bilet fotoğrafı ekle
            </button>
          </div>
        </details>
      )}

      {!canContinue && (
        <p className="alert-banner info">
          Devam için en az bir uçuş ekleyin: havayolu, kalkış ve varış havaalanı.
        </p>
      )}
    </>
  );
}
