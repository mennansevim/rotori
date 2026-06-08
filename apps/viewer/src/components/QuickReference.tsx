import type { Trip } from '@japan-trip/shared';

interface Props {
  trip: Trip;
}

function nights(checkIn: string, checkOut: string): number {
  try {
    const a = new Date(checkIn).getTime();
    const b = new Date(checkOut).getTime();
    return Math.max(0, Math.round((b - a) / 86400000));
  } catch {
    return 0;
  }
}

export function QuickReference({ trip }: Props) {
  const hotels = trip.hotels ?? [];
  const tickets = trip.tickets ?? [];
  const purchasedTickets = tickets.filter((t) => t.purchased);
  const pendingTickets = tickets.filter((t) => !t.purchased);
  const mustSee = trip.preferences.mustSee ?? [];
  const dietary = trip.preferences.dietary ?? trip.preferences.dietaryTags ?? [];
  const partySize = trip.preferences.partySize ?? 1;
  const children = trip.preferences.childrenCount ?? 0;
  const pace = trip.preferences.pace ?? 'moderate';
  const paceLabel = pace === 'relaxed' ? 'Rahat' : pace === 'intense' ? 'Yoğun' : 'Dengeli';

  const totalNights = hotels.reduce((s, h) => s + nights(h.checkIn, h.checkOut), 0);
  const totalDays = (trip.days ?? []).length;
  const destinations = (trip.preferences.destinations ?? []).slice().sort((a, b) => a.order - b.order);

  return (
    <section className="section">
      <div className="section-header">
        <div className="section-icon">📋</div>
        <div>
          <h2 className="section-title">Hızlı Referans</h2>
          <div className="section-subtitle">Plan özeti — pratik bilgiler</div>
        </div>
      </div>

      <div className="info-grid">
        <div className="info-card">
          <div className="info-card-head">
            <div className="info-card-icon">🗺️</div>
            <div>
              <div className="info-card-title">Rota & Gün</div>
              <div className="info-card-sub">{totalDays} gün · {totalNights} gece</div>
            </div>
          </div>
          <div className="info-list">
            <strong>Destinasyonlar:</strong>
            <br />
            {destinations.length === 0 && '—'}
            {destinations.map((d) => (
              <div key={d.id}>
                • {d.city || d.countryName} {d.airport ? `(${d.airport})` : ''}
              </div>
            ))}
            <br />
            <strong>Tempo:</strong> {paceLabel}
            <br />
            <strong>Kişi:</strong> {partySize}{children > 0 && `, ${children} çocuk`}
          </div>
        </div>

        {hotels.length > 0 && (
          <div className="info-card">
            <div className="info-card-head">
              <div className="info-card-icon sakura">🏨</div>
              <div>
                <div className="info-card-title">Konaklama</div>
                <div className="info-card-sub">{hotels.length} otel</div>
              </div>
            </div>
            <div className="info-list">
              {hotels.map((h) => (
                <div key={h.id} style={{ marginBottom: 10 }}>
                  <strong>{h.name}</strong>
                  <br />
                  📍 {h.city} · {nights(h.checkIn, h.checkOut)} gece
                  <br />
                  <span style={{ fontSize: 12 }}>{h.checkIn} → {h.checkOut}</span>
                  {h.mapsUrl && (
                    <>
                      {' · '}
                      <a href={h.mapsUrl} target="_blank" rel="noopener noreferrer">Harita</a>
                    </>
                  )}
                </div>
              ))}
            </div>
          </div>
        )}

        {tickets.length > 0 && (
          <div className="info-card">
            <div className="info-card-head">
              <div className="info-card-icon gold">🎫</div>
              <div>
                <div className="info-card-title">Biletler</div>
                <div className="info-card-sub">
                  {purchasedTickets.length} alındı · {pendingTickets.length} bekliyor
                </div>
              </div>
            </div>
            <div className="info-list">
              {tickets.map((t) => (
                <div key={t.id}>
                  {t.purchased ? '✅' : '⏳'} {t.emoji ?? '🎫'} <strong>{t.label}</strong>
                  {t.visitDate && <span style={{ fontSize: 12, color: 'var(--text-muted)' }}> · {t.visitDate}</span>}
                </div>
              ))}
            </div>
          </div>
        )}

        {mustSee.length > 0 && (
          <div className="info-card">
            <div className="info-card-head">
              <div className="info-card-icon sunset">⭐</div>
              <div>
                <div className="info-card-title">Mutlaka gör</div>
                <div className="info-card-sub">{mustSee.length} öncelikli yer</div>
              </div>
            </div>
            <div className="info-list">
              {mustSee.map((m, i) => (
                <div key={i}>• {m}</div>
              ))}
            </div>
          </div>
        )}

        {dietary.length > 0 && (
          <div className="info-card">
            <div className="info-card-head">
              <div className="info-card-icon matcha">🍽️</div>
              <div>
                <div className="info-card-title">Yemek tercihi</div>
                <div className="info-card-sub">Diyet & kısıt</div>
              </div>
            </div>
            <div className="info-list">
              {dietary.map((d, i) => (
                <div key={i}>• {d}</div>
              ))}
            </div>
          </div>
        )}

        <div className="info-card">
          <div className="info-card-head">
            <div className="info-card-icon sky">📱</div>
            <div>
              <div className="info-card-title">Faydalı uygulamalar</div>
              <div className="info-card-sub">Telefona kurun</div>
            </div>
          </div>
          <div className="info-list">
            ✓ Google Maps (offline harita indir)
            <br />
            ✓ Google Translate (kamera modu)
            <br />
            ✓ Hedef ülkenin resmi turizm uygulaması
            <br />
            ✓ Yerel taksi uygulaması (GO, Bolt, Uber…)
            <br />
            ✓ XE Currency veya benzeri döviz
          </div>
        </div>
      </div>
    </section>
  );
}
