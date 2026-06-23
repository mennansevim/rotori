import { useMemo, useState } from 'react';
import { useTranslation } from 'react-i18next';
import {
  MAX_TRIP_DAYS,
  syncTripFromDestinations,
  type Trip,
} from '@japan-trip/shared';

function addDays(iso: string, days: number): string {
  const d = new Date(iso + 'T00:00:00Z');
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}

function daysBetween(startISO: string, endISO: string): number {
  const ms =
    new Date(endISO + 'T00:00:00Z').getTime() -
    new Date(startISO + 'T00:00:00Z').getTime();
  return Math.round(ms / 86400000) + 1;
}
import {
  AVOID_RANGES,
  BADGES,
  MONTHS,
  SUGGESTED_RANGES,
  type SeasonTag,
} from '../../data/japanSeasonality';

interface Props {
  trip: Trip;
  onChange: (updater: (t: Trip) => Trip) => void;
  onContinue: () => void;
}

type View = 'choose' | 'ticket' | 'plan';

interface TicketDraft {
  outboundDate: string;
  outboundFlightNo: string;
  returnDate: string;
  returnFlightNo: string;
  airline: string;
  origin: string;
  destination: string;
}

const emptyTicket: TicketDraft = {
  outboundDate: '',
  outboundFlightNo: '',
  returnDate: '',
  returnFlightNo: '',
  airline: '',
  origin: '',
  destination: 'Tokyo',
};

function Badge({ tag }: { tag: SeasonTag }) {
  const b = BADGES[tag];
  return (
    <span className={`season-badge season-badge-${b.tone}`} title={b.label}>
      {b.emoji} {b.label}
    </span>
  );
}

function formatDateTR(iso: string): string {
  const d = new Date(iso + 'T00:00:00Z');
  return d.toLocaleDateString('tr-TR', { day: 'numeric', month: 'long', year: 'numeric' });
}

export function WelcomeStep({ trip, onChange, onContinue }: Props) {
  const { t } = useTranslation();
  const [view, setView] = useState<View>('choose');
  const [ticket, setTicket] = useState<TicketDraft>(emptyTicket);
  const [photoName, setPhotoName] = useState<string | null>(null);
  const [photoDataUrl, setPhotoDataUrl] = useState<string | null>(null);
  const [ocrStatus, setOcrStatus] = useState<'idle' | 'busy' | 'ok' | 'fail'>('idle');
  const [ocrMessage, setOcrMessage] = useState<string | null>(null);

  const ticketReady = useMemo(
    () => ticket.outboundDate.trim().length > 0,
    [ticket.outboundDate],
  );

  const applyDates = (start: string, end: string) => {
    onChange((t) => {
      const dests = (t.preferences.destinations ?? []).map((d) => ({
        ...d,
        arrivalDate: start,
        departureDate: end,
      }));
      const food = t.preferences.destinationFood ?? [];
      if (dests.length === 0) {
        return {
          ...t,
          tripStart: `${start}T08:00:00`,
          tripEnd: `${end}T20:00:00`,
          preferences: { ...t.preferences, travelDates: { start, end } },
        };
      }
      return syncTripFromDestinations(t, {
        originCity: t.preferences.originCity ?? '',
        originAirport: t.preferences.originAirport,
        originLat: t.preferences.originLat,
        originLng: t.preferences.originLng,
        destinations: dests,
        destinationFood: food,
        travelStart: start,
        travelEnd: end,
      });
    });
  };

  const handleTicketSubmit = () => {
    if (!ticketReady) return;
    const start = ticket.outboundDate;
    let end = ticket.returnDate || ticket.outboundDate;
    const maxEnd = addDays(start, MAX_TRIP_DAYS - 1);
    if (end > maxEnd) end = maxEnd;
    applyDates(start, end);

    if (photoDataUrl) {
      onChange((t) => ({
        ...t,
        tickets: [
          {
            id: `ticket-${Date.now()}`,
            kind: 'flight',
            label: ticket.outboundFlightNo
              ? `${ticket.airline} ${ticket.outboundFlightNo}`.trim()
              : 'Uçuş bileti',
            purchased: true,
            imageDataUrl: photoDataUrl,
          },
          ...t.tickets,
        ],
      }));
    }
    onContinue();
  };

  const handleRangePick = (start: string, end: string) => {
    applyDates(start, end);
    onContinue();
  };

  const handlePhoto = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    setPhotoName(file.name);
    const reader = new FileReader();
    reader.onload = async () => {
      const dataUrl = typeof reader.result === 'string' ? reader.result : null;
      setPhotoDataUrl(dataUrl);
      if (!dataUrl) return;
      setOcrStatus('busy');
      setOcrMessage('AI bilet bilgilerini çıkarıyor…');
      try {
        const resp = await fetch('/api/ticket-ocr', {
          method: 'POST',
          headers: { 'content-type': 'application/json' },
          body: JSON.stringify({ imageDataUrl: dataUrl }),
        });
        if (resp.status === 501) {
          setOcrStatus('fail');
          setOcrMessage('AI yapılandırılmamış — bilgileri manuel doldur.');
          return;
        }
        if (!resp.ok) {
          setOcrStatus('fail');
          setOcrMessage('Bilgileri okuyamadık — manuel doldurabilirsin.');
          return;
        }
        const data = await resp.json();
        setTicket((cur) => ({
          ...cur,
          outboundDate: data.outboundDate || cur.outboundDate,
          returnDate: data.returnDate || cur.returnDate,
          airline: data.airline || cur.airline,
          outboundFlightNo: data.flightNo || cur.outboundFlightNo,
        }));
        setOcrStatus('ok');
        const filled = [
          data.airline && 'havayolu',
          data.flightNo && 'uçuş no',
          data.outboundDate && 'gidiş tarihi',
          data.returnDate && 'dönüş tarihi',
        ].filter(Boolean);
        setOcrMessage(
          filled.length > 0
            ? `✓ Otomatik dolduruldu: ${filled.join(', ')}`
            : '✓ Foto kaydedildi (bilgi çıkmadı, manuel doldur)',
        );
      } catch {
        setOcrStatus('fail');
        setOcrMessage('Bağlantı hatası — manuel doldur.');
      }
    };
    reader.readAsDataURL(file);
  };

  if (view === 'choose') {
    return (
      <div className="welcome-screen">
        <div className="welcome-hero">
          <div className="welcome-flag">🇯🇵</div>
          <h1 className="welcome-title">{t('welcome.greeting')}</h1>
          <p className="welcome-sub">{t('welcome.subPrompt')}</p>
        </div>
        <div className="welcome-choices">
          <button
            type="button"
            className="welcome-card"
            onClick={() => {
              onChange((t) => ({
                ...t,
                preferences: { ...t.preferences, hasTicket: true },
              }));
              setView('ticket');
            }}
          >
            <div className="welcome-card-icon">✈️</div>
            <div className="welcome-card-title">{t('welcome.ticketCardTitle')}</div>
            <div className="welcome-card-desc">{t('welcome.ticketCardDesc')}</div>
          </button>
          <button
            type="button"
            className="welcome-card"
            onClick={() => {
              onChange((t) => ({
                ...t,
                preferences: { ...t.preferences, hasTicket: false },
              }));
              setView('plan');
            }}
          >
            <div className="welcome-card-icon">📅</div>
            <div className="welcome-card-title">{t('welcome.planCardTitle')}</div>
            <div className="welcome-card-desc">{t('welcome.planCardDesc')}</div>
          </button>
        </div>
      </div>
    );
  }

  if (view === 'ticket') {
    return (
      <div className="welcome-screen">
        <button type="button" className="welcome-back" onClick={() => setView('choose')}>
          ← Geri
        </button>
        <h2 className="welcome-step-title">Bilet bilgilerin</h2>
        <p className="welcome-step-sub">
          Sadece tarihler zorunlu — diğer alanları boş bırakabilirsin. En fazla{' '}
          {MAX_TRIP_DAYS} günlük plan oluşturuyoruz.
        </p>

        <div className="welcome-form card">
          <label className="welcome-field">
            <span>Gidiş tarihi</span>
            <input
              type="date"
              value={ticket.outboundDate}
              onChange={(e) => setTicket({ ...ticket, outboundDate: e.target.value })}
            />
          </label>
          <label className="welcome-field">
            <span>Dönüş tarihi</span>
            <input
              type="date"
              value={ticket.returnDate}
              min={ticket.outboundDate || undefined}
              max={
                ticket.outboundDate
                  ? addDays(ticket.outboundDate, MAX_TRIP_DAYS - 1)
                  : undefined
              }
              onChange={(e) => setTicket({ ...ticket, returnDate: e.target.value })}
            />
            {ticket.outboundDate &&
              ticket.returnDate &&
              daysBetween(ticket.outboundDate, ticket.returnDate) > MAX_TRIP_DAYS && (
                <span className="welcome-field-warn">
                  En fazla {MAX_TRIP_DAYS} günlük plan oluşturuyoruz —{' '}
                  {daysBetween(ticket.outboundDate, ticket.returnDate)} gün seçildi, otomatik
                  kısaltılacak.
                </span>
              )}
          </label>
          <label className="welcome-field">
            <span>Havayolu</span>
            <input
              type="text"
              placeholder="THY, JAL…"
              value={ticket.airline}
              onChange={(e) => setTicket({ ...ticket, airline: e.target.value })}
            />
          </label>
          <label className="welcome-field">
            <span>Uçuş no (gidiş)</span>
            <input
              type="text"
              placeholder="TK198"
              value={ticket.outboundFlightNo}
              onChange={(e) => setTicket({ ...ticket, outboundFlightNo: e.target.value })}
            />
          </label>
          <label className="welcome-field">
            <span>Uçuş no (dönüş)</span>
            <input
              type="text"
              placeholder="TK199"
              value={ticket.returnFlightNo}
              onChange={(e) => setTicket({ ...ticket, returnFlightNo: e.target.value })}
            />
          </label>

          <div className="welcome-photo">
            <label className="btn btn-secondary welcome-photo-btn">
              📷 Bilet fotoğrafı yükle
              <input
                type="file"
                accept="image/*"
                onChange={handlePhoto}
                hidden
                disabled={ocrStatus === 'busy'}
              />
            </label>
            {photoName && (
              <span className={`welcome-photo-name welcome-photo-${ocrStatus}`}>
                {ocrStatus === 'busy' && '⏳ '}
                {ocrStatus === 'ok' && ''}
                {ocrStatus === 'fail' && '⚠️ '}
                {ocrMessage ?? `✓ ${photoName}`}
              </span>
            )}
          </div>
        </div>

        <div className="welcome-actions">
          <button
            type="button"
            className="btn btn-primary"
            disabled={!ticketReady}
            onClick={handleTicketSubmit}
          >
            Devam
          </button>
        </div>
      </div>
    );
  }

  // view === 'plan'
  return (
    <div className="welcome-screen">
      <button type="button" className="welcome-back" onClick={() => setView('choose')}>
        ← Geri
      </button>
      <h2 className="welcome-step-title">Japonya'da hangi mevsim?</h2>
      <p className="welcome-step-sub">
        Aylar bir bakışta. Aşağıdaki önerilen aralıklardan birini seç, tarihleri otomatik dolduralım.
      </p>

      <section className="season-grid">
        {MONTHS.map((m) => {
          const now = new Date();
          const todayMonth = now.getUTCMonth() + 1;
          const todayYear = now.getUTCFullYear();
          const year = m.month >= todayMonth ? todayYear : todayYear + 1;
          const start = `${year}-${String(m.month).padStart(2, '0')}-01`;
          const endDate = new Date(start + 'T00:00:00Z');
          endDate.setUTCDate(endDate.getUTCDate() + 13);
          const end = endDate.toISOString().slice(0, 10);
          return (
            <button
              key={m.month}
              type="button"
              className="season-month season-month-clickable"
              onClick={() => handleRangePick(start, end)}
              title={`${m.label} ${year} — 14 günlük plan`}
            >
              <div className="season-month-head">
                <span className="season-month-num">{m.month}</span>
                <span className="season-month-label">
                  {m.label} <span className="season-month-year">{year}</span>
                </span>
              </div>
              <div className="season-badges">
                {m.tags.map((t) => (
                  <Badge key={t} tag={t} />
                ))}
              </div>
              <p className="season-note">{m.note}</p>
            </button>
          );
        })}
      </section>

      <h3 className="welcome-section-title">Önerilen 2 haftalık aralıklar</h3>
      <div className="suggested-ranges">
        {SUGGESTED_RANGES.map((r) => (
          <button
            key={r.id}
            type="button"
            className={`range-card range-${r.tone}`}
            onClick={() => handleRangePick(r.startISO, r.endISO)}
          >
            <div className="range-head">
              <span className="range-label">{r.label}</span>
              <div className="range-badges">
                {r.badges.map((t) => (
                  <Badge key={t} tag={t} />
                ))}
              </div>
            </div>
            <div className="range-dates">
              {formatDateTR(r.startISO)} — {formatDateTR(r.endISO)}
            </div>
            <p className="range-reason">{r.reason}</p>
          </button>
        ))}
      </div>

      <h3 className="welcome-section-title welcome-section-warn">
        ⚠️ Bu pencerelerden uzak dur
      </h3>
      <div className="avoid-ranges">
        {AVOID_RANGES.map((r) => (
          <div key={r.id} className="avoid-card">
            <div className="avoid-head">
              <span className="avoid-label">{r.label}</span>
              <div className="range-badges">
                {r.badges.map((t) => (
                  <Badge key={t} tag={t} />
                ))}
              </div>
            </div>
            <p className="avoid-reason">{r.reason}</p>
          </div>
        ))}
      </div>
    </div>
  );
}
