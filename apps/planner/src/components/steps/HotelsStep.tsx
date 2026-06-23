import { useState } from 'react';
import { newHotelId } from '@japan-trip/shared';
import type { HotelStay, Trip } from '@japan-trip/shared';

interface Props {
  trip: Trip;
  onChange: (updater: (t: Trip) => Trip) => void;
}

const EMPTY_HOTEL = (start: string, end: string): HotelStay => ({
  id: newHotelId(),
  city: '',
  name: '',
  checkIn: start,
  checkOut: end,
  address: '',
});

interface ParsedBooking {
  name?: string;
  city?: string;
  checkIn?: string;
  checkOut?: string;
  mapsUrl?: string;
  source: 'booking' | 'hostelworld' | 'booking-mytrips' | 'unknown';
}

function titleCase(slug: string): string {
  return slug
    .replace(/[-_]+/g, ' ')
    .split(' ')
    .filter(Boolean)
    .map((w) => w.charAt(0).toUpperCase() + w.slice(1).toLowerCase())
    .join(' ');
}

export function parseBookingUrl(raw: string): ParsedBooking | null {
  const text = raw.trim();
  if (!text) return null;
  let url: URL;
  try {
    url = new URL(text);
  } catch {
    return null;
  }
  const host = url.hostname.toLowerCase();
  const checkIn = url.searchParams.get('checkin') || undefined;
  const checkOut = url.searchParams.get('checkout') || undefined;

  if (host.includes('booking.com')) {
    // /mytrips, /myreservations gibi hesap sayfaları — tek otel datası yok.
    const path = url.pathname.toLowerCase();
    if (
      path.includes('mytrips') ||
      path.includes('myreservations') ||
      path.includes('myaccount')
    ) {
      return { source: 'booking-mytrips' };
    }
    const m = url.pathname.match(/\/hotel\/([a-z]{2})\/([^./]+)/i);
    if (!m) return { source: 'booking', checkIn, checkOut };
    const slug = m[2];
    return {
      source: 'booking',
      name: titleCase(slug),
      checkIn,
      checkOut,
    };
  }

  if (host.includes('hostelworld.com')) {
    const segs = url.pathname.split('/').filter(Boolean);
    const idx = segs.findIndex((s) => /hosteldetails/i.test(s));
    const nameSlug = idx >= 0 ? segs[idx + 1] : segs[segs.length - 3];
    const citySlug = idx >= 0 ? segs[idx + 2] : segs[segs.length - 2];
    return {
      source: 'hostelworld',
      name: nameSlug ? titleCase(nameSlug) : undefined,
      city: citySlug ? titleCase(citySlug) : undefined,
      checkIn,
      checkOut,
    };
  }

  return { source: 'unknown', checkIn, checkOut };
}

export function hotelsComplete(trip: Trip): boolean {
  if (trip.hotels.length === 0) return false;
  return trip.hotels.every(
    (h) =>
      h.city.trim() &&
      h.name.trim() &&
      h.address.trim() &&
      h.checkIn &&
      h.checkOut,
  );
}

export function HotelsStep({ trip, onChange }: Props) {
  const [importUrl, setImportUrl] = useState('');
  const [importStatus, setImportStatus] = useState<{
    kind: 'success' | 'error' | 'idle';
    message: string;
  }>({ kind: 'idle', message: '' });

  const addHotel = () => {
    onChange((t) => ({
      ...t,
      hotels: [...t.hotels, EMPTY_HOTEL(t.preferences.travelDates.start, t.preferences.travelDates.end)],
    }));
  };

  const importFromUrl = () => {
    const parsed = parseBookingUrl(importUrl);
    if (!parsed) {
      setImportStatus({ kind: 'error', message: 'Geçerli bir URL yapıştır (Booking veya Hostelworld).' });
      return;
    }
    if (parsed.source === 'booking-mytrips') {
      setImportStatus({
        kind: 'error',
        message:
          'Bu link Booking hesabındaki rezervasyon listesine gidiyor (üye girişi gerekir, tek bir otel bilgisi yok). Onaylama e-postandan veya rezervasyon detayından otelin sayfa linkini kopyala — örn. booking.com/hotel/jp/hotel-adi.html',
      });
      return;
    }
    if (parsed.source === 'unknown') {
      setImportStatus({
        kind: 'error',
        message: 'Bu site desteklenmiyor. Booking.com veya Hostelworld linki yapıştır.',
      });
      return;
    }
    const start = trip.preferences.travelDates.start;
    const end = trip.preferences.travelDates.end;
    const hotel: HotelStay = {
      id: newHotelId(),
      city: parsed.city ?? '',
      name: parsed.name ?? '',
      checkIn: parsed.checkIn ?? start,
      checkOut: parsed.checkOut ?? end,
      address: '',
      mapsUrl: importUrl.trim(),
    };
    onChange((t) => ({ ...t, hotels: [...t.hotels, hotel] }));
    setImportUrl('');
    const label = parsed.source === 'booking' ? 'Booking' : 'Hostelworld';
    setImportStatus({
      kind: 'success',
      message: `${label}'dan içe aktarıldı: ${parsed.name ?? 'isimsiz'}. Eksik alanları doldurmayı unutma.`,
    });
  };

  const updateHotel = (idx: number, patch: Partial<HotelStay>) => {
    onChange((t) => {
      const hotels = [...t.hotels];
      const prev = hotels[idx];
      hotels[idx] = {
        ...prev,
        ...patch,
        addressLocal: patch.addressLocal ?? patch.addressJa ?? prev.addressLocal ?? prev.addressJa,
      };
      return { ...t, hotels };
    });
  };

  const removeHotel = (idx: number) => {
    onChange((t) => ({
      ...t,
      hotels: t.hotels.filter((_, i) => i !== idx),
    }));
  };

  return (
    <>
      <h2 className="page-headline">Konaklama</h2>
      <p className="page-sub">
        Her otel için açık adres zorunludur — taksi ve pusulada kullanılır. Yerel dilde adresi de
        ekleyin (Japonca, Korece vb.).
      </p>

      <div className="booking-import">
        <div className="booking-import-title">🔗 Rezervasyondan içe aktar</div>
        <p className="booking-import-sub">
          Booking.com veya Hostelworld'de yaptığın rezervasyonun linkini yapıştır — otel adı ve
          tarihler otomatik dolar. Manuel ekleme her zaman aşağıdadır.
        </p>
        <div className="booking-import-links">
          <a
            className="booking-import-link"
            href="https://www.booking.com/myreservations.tr.html"
            target="_blank"
            rel="noopener noreferrer"
          >
            🛏️ Booking.com rezervasyonlarım
          </a>
          <a
            className="booking-import-link"
            href="https://www.hostelworld.com/myaccount/bookings"
            target="_blank"
            rel="noopener noreferrer"
          >
            🏨 Hostelworld rezervasyonlarım
          </a>
        </div>
        <div className="booking-import-row">
          <input
            value={importUrl}
            placeholder="https://www.booking.com/hotel/jp/..."
            onChange={(e) => setImportUrl(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter') {
                e.preventDefault();
                importFromUrl();
              }
            }}
          />
          <button
            type="button"
            className="btn btn-primary btn-sm"
            onClick={importFromUrl}
            disabled={!importUrl.trim()}
          >
            İçe aktar
          </button>
        </div>
        {importStatus.kind !== 'idle' && (
          <p className={`booking-import-feedback ${importStatus.kind}`}>
            {importStatus.message}
          </p>
        )}
      </div>

      {trip.hotels.length === 0 && (
        <div className="card">
          <p style={{ color: 'var(--text-secondary)', marginBottom: 16 }}>
            Henüz otel yok. En az bir konaklama ekleyin.
          </p>
          <button type="button" className="btn btn-primary btn-block" onClick={addHotel}>
            + Otel ekle
          </button>
        </div>
      )}

      {trip.hotels.map((h, idx) => {
        const addrMissing = !h.address?.trim();
        return (
          <div key={h.id} className="hotel-card">
            <div className="hotel-card-header">
              <strong>Otel {idx + 1}</strong>
              <button
                type="button"
                className="hotel-remove"
                aria-label="Sil"
                onClick={() => removeHotel(idx)}
              >
                ×
              </button>
            </div>
            <div className="grid-2">
              <div className="field">
                <label>Şehir *</label>
                <input
                  value={h.city}
                  placeholder="Tokyo"
                  onChange={(e) => updateHotel(idx, { city: e.target.value })}
                />
              </div>
              <div className="field">
                <label>Otel adı *</label>
                <input
                  value={h.name}
                  placeholder="Hotel Grand City"
                  onChange={(e) => updateHotel(idx, { name: e.target.value })}
                />
              </div>
            </div>
            <div className="grid-2">
              <div className="field">
                <label>Giriş *</label>
                <input
                  type="date"
                  value={h.checkIn}
                  min={trip.preferences.travelDates.start}
                  max={trip.preferences.travelDates.end}
                  onChange={(e) => updateHotel(idx, { checkIn: e.target.value })}
                />
              </div>
              <div className="field">
                <label>Çıkış *</label>
                <input
                  type="date"
                  value={h.checkOut}
                  min={h.checkIn || trip.preferences.travelDates.start}
                  max={trip.preferences.travelDates.end}
                  onChange={(e) => updateHotel(idx, { checkOut: e.target.value })}
                />
              </div>
            </div>
            <div className="field">
              <label>Açık adres (sokak, posta kodu) *</label>
              <input
                value={h.address ?? ''}
                placeholder="2-37-6 Ikebukuro, Toshima-ku, Tokyo 171-0014"
                className={addrMissing ? 'input-invalid' : undefined}
                onChange={(e) => updateHotel(idx, { address: e.target.value })}
              />
              {addrMissing && (
                <span className="field-hint field-hint-warn">Taksi ve harita için adres gerekli</span>
              )}
            </div>
            <div className="field">
              <label>Adres (yerel dil)</label>
              <input
                value={h.addressLocal ?? h.addressJa ?? ''}
                placeholder="ホテルグランドシティ池袋 東京都豊島区..."
                onChange={(e) => updateHotel(idx, { addressLocal: e.target.value })}
              />
            </div>
            <div className="grid-2">
              <div className="field">
                <label>Google Maps linki</label>
                <input
                  value={h.mapsUrl ?? ''}
                  placeholder="https://maps.google.com/..."
                  onChange={(e) => updateHotel(idx, { mapsUrl: e.target.value })}
                />
              </div>
              <div className="field">
                <label>Telefon</label>
                <input
                  value={h.phone ?? ''}
                  placeholder="+81 ..."
                  onChange={(e) => updateHotel(idx, { phone: e.target.value })}
                />
              </div>
            </div>
          </div>
        );
      })}

      {trip.hotels.length > 0 && (
        <button type="button" className="btn btn-secondary btn-block" onClick={addHotel}>
          + Başka otel ekle
        </button>
      )}
    </>
  );
}
