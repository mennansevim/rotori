import { useState } from 'react';
import { newTicketId, isTransportTicket } from '@japan-trip/shared';
import type { Trip } from '@japan-trip/shared';
import { TicketCard } from '../TicketCard';
import {
  extractTextFromImage,
  parseTicketFromText,
  readFileAsDataUrl,
} from '../../utils/ocr';

interface Props {
  trip: Trip;
  onChange: (updater: (t: Trip) => Trip) => void;
}

/** Müze, park, konser vb. — uçak/tren Seyahat adımında */
export function TicketsStep({ trip, onChange }: Props) {
  const [scanning, setScanning] = useState(false);
  const [scanTarget, setScanTarget] = useState<string | null>(null);

  const activityTickets = trip.tickets.filter((t) => !isTransportTicket(t.kind));

  const addTicket = () => {
    onChange((t) => ({
      ...t,
      tickets: [
        ...t.tickets,
        {
          id: newTicketId(),
          kind: 'attraction',
          label: 'Etkinlik / giriş bileti',
          purchased: false,
          emoji: '🎟️',
        },
      ],
    }));
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

  return (
    <>
      <h2 className="page-headline">Etkinlik biletleri</h2>
      <p className="page-sub">
        Müze, tema parkı, konser — uçak ve tren biletleri Seyahat adımında.
      </p>

      {activityTickets.map((tk) => {
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

      <button type="button" className="btn btn-primary btn-block" onClick={addTicket}>
        + Bilet ekle
      </button>
    </>
  );
}
