import { useEffect, useState } from 'react';
import { tripPhase } from '@japan-trip/shared';
import type { Ticket, Trip } from '@japan-trip/shared';

function pad(n: number) {
  return String(n).padStart(2, '0');
}

function daysUntil(iso: string) {
  const diff = new Date(iso).getTime() - Date.now();
  return Math.max(0, Math.floor(diff / 86400000));
}

function isValidIso(s?: string): boolean {
  if (!s) return false;
  const d = new Date(s);
  return !Number.isNaN(d.getTime());
}

interface Props {
  trip: Trip;
  onOpenSettings?: () => void;
}

export function CountdownBar({ trip, onOpenSettings }: Props) {
  const [now, setNow] = useState(Date.now());

  useEffect(() => {
    const id = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(id);
  }, []);

  const hasDates = isValidIso(trip.tripStart) && isValidIso(trip.tripEnd);
  const phase = hasDates ? tripPhase(trip.tripStart, trip.tripEnd, new Date(now)) : 'before';
  const startMs = hasDates ? new Date(trip.tripStart).getTime() : 0;
  const diff = startMs - now;

  let label = '🇯🇵 Tatile';
  let timer: { d: number; h: number; m: number; s: number } | null = null;

  if (!hasDates) {
    label = '✈️ Yeni plan';
  } else if (phase === 'after') {
    // Yalnızca trip gerçekten geçmişse mesaj; default state'te tetiklemiyoruz.
    label = '✨ Plan tamamlandı';
  } else if (phase === 'during') {
    label = '🎉 Tatil başladı';
  } else if (diff > 0) {
    timer = {
      d: Math.floor(diff / 86400000),
      h: Math.floor((diff % 86400000) / 3600000),
      m: Math.floor((diff % 3600000) / 60000),
      s: Math.floor((diff % 60000) / 1000),
    };
  }

  const tickets = trip.tickets ?? [];

  return (
    <div className="top-countdown-bar">
      <div className="top-countdown-content">
        <span className="top-countdown-label">{label}</span>

        <div className="top-countdown-center">
          {timer && (
            <div className="top-countdown-timer" aria-label="Geri sayım">
              <span className="top-cd-value">{pad(timer.d)}</span>
              <span className="top-cd-unit">g</span>
              <span className="top-cd-sep">:</span>
              <span className="top-cd-value">{pad(timer.h)}</span>
              <span className="top-cd-unit">s</span>
              <span className="top-cd-sep">:</span>
              <span className="top-cd-value">{pad(timer.m)}</span>
              <span className="top-cd-unit">d</span>
              <span className="top-cd-sep">:</span>
              <span className="top-cd-value">{pad(timer.s)}</span>
              <span className="top-cd-unit">sn</span>
            </div>
          )}

          {tickets.length > 0 && (
            <div className="top-countdown-tickets">
              {tickets.slice(0, 5).map((t) => (
                <TicketBadge key={t.id} ticket={t} />
              ))}
            </div>
          )}
        </div>

        {onOpenSettings && (
          <button
            type="button"
            className="settings-button"
            onClick={onOpenSettings}
            aria-label="Ayarlar"
            title="Ayarlar ve tema"
          >
            ⚙ Ayarlar
          </button>
        )}
      </div>
    </div>
  );
}

function TicketBadge({ ticket }: { ticket: Ticket }) {
  const urgent =
    !ticket.purchased &&
    ticket.bookingOpens &&
    daysUntil(ticket.bookingOpens) <= 14;

  const labelShort = ticket.label.split(' ')[0] || ticket.label;
  const text = ticket.purchased
    ? `${ticket.emoji ?? '🎫'} ✓`
    : ticket.visitDate
      ? `${ticket.emoji ?? '🎫'} ${daysUntil(ticket.visitDate)}g`
      : `${ticket.emoji ?? '🎫'} ${labelShort}`;

  return (
    <a
      href={ticket.url ?? '#'}
      className={`ticket-badge${ticket.purchased ? ' purchased' : ''}${urgent ? ' urgent' : ''}`}
      target={ticket.url ? '_blank' : undefined}
      rel={ticket.url ? 'noopener noreferrer' : undefined}
      onClick={ticket.url ? undefined : (e) => e.preventDefault()}
      title={ticket.label}
    >
      {text}
    </a>
  );
}
