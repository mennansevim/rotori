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
  const addHotel = () => {
    onChange((t) => ({
      ...t,
      hotels: [...t.hotels, EMPTY_HOTEL(t.preferences.travelDates.start, t.preferences.travelDates.end)],
    }));
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
                  onChange={(e) => updateHotel(idx, { checkIn: e.target.value })}
                />
              </div>
              <div className="field">
                <label>Çıkış *</label>
                <input
                  type="date"
                  value={h.checkOut}
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
