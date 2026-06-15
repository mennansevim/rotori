import { useMemo, useState } from 'react';
import type { Trip } from '@japan-trip/shared';
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
  const [view, setView] = useState<View>('choose');
  const [ticket, setTicket] = useState<TicketDraft>(emptyTicket);
  const [photoName, setPhotoName] = useState<string | null>(null);
  const [photoDataUrl, setPhotoDataUrl] = useState<string | null>(null);

  const ticketReady = useMemo(
    () => ticket.outboundDate.trim().length > 0,
    [ticket.outboundDate],
  );

  const applyDates = (start: string, end: string) => {
    onChange((t) => ({
      ...t,
      tripStart: start,
      tripEnd: end,
      preferences: {
        ...t.preferences,
        travelDates: { start, end },
      },
    }));
  };

  const handleTicketSubmit = () => {
    if (!ticketReady) return;
    const start = ticket.outboundDate;
    const end = ticket.returnDate || ticket.outboundDate;
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
    reader.onload = () => setPhotoDataUrl(typeof reader.result === 'string' ? reader.result : null);
    reader.readAsDataURL(file);
  };

  if (view === 'choose') {
    return (
      <div className="welcome-screen">
        <div className="welcome-hero">
          <div className="welcome-flag">🇯🇵</div>
          <h1 className="welcome-title">Japonya'ya hoş geldin</h1>
          <p className="welcome-sub">Nereden başlayalım?</p>
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
            <div className="welcome-card-title">Biletim var</div>
            <div className="welcome-card-desc">
              Uçuş bilgilerini gir ya da bilet fotoğrafını yükle
            </div>
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
            <div className="welcome-card-title">Gezi planla</div>
            <div className="welcome-card-desc">
              Sana en uygun tarihleri birlikte seçelim
            </div>
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
          Sadece tarihler zorunlu — diğer alanları boş bırakabilirsin.
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
              onChange={(e) => setTicket({ ...ticket, returnDate: e.target.value })}
            />
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
              <input type="file" accept="image/*" onChange={handlePhoto} hidden />
            </label>
            {photoName && (
              <span className="welcome-photo-name">
                ✓ {photoName} — Şimdilik manuel doldur, sonra otomatik çıkarılacak.
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
        {MONTHS.map((m) => (
          <div key={m.month} className="season-month">
            <div className="season-month-head">
              <span className="season-month-num">{m.month}</span>
              <span className="season-month-label">{m.label}</span>
            </div>
            <div className="season-badges">
              {m.tags.map((t) => (
                <Badge key={t} tag={t} />
              ))}
            </div>
            <p className="season-note">{m.note}</p>
          </div>
        ))}
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
