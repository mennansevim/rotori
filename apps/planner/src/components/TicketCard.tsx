import type { Ticket } from '@japan-trip/shared';

interface Props {
  ticket: Ticket;
  scanning: boolean;
  onUpdate: (p: Partial<Ticket>) => void;
  onRemove: () => void;
  onScanFile: (f: File | undefined) => void;
  showKind?: boolean;
}

const KIND_LABELS: Record<string, string> = {
  flight: 'Uçak',
  train: 'Tren',
  bus: 'Otobüs',
  ferry: 'Feribot',
  attraction: 'Mekan / müze',
  event: 'Etkinlik',
  other: 'Diğer',
};

export function TicketCard({
  ticket,
  scanning,
  onUpdate,
  onRemove,
  onScanFile,
  showKind = false,
}: Props) {
  return (
    <div className="ticket-card">
      <div style={{ display: 'flex', justifyContent: 'space-between' }}>
        <span style={{ fontWeight: 600 }}>{ticket.emoji ?? '🎫'} Bilet</span>
        <button type="button" className="hotel-remove" onClick={onRemove}>
          ×
        </button>
      </div>
      {ticket.imageDataUrl && (
        <img src={ticket.imageDataUrl} alt="Bilet" className="ticket-preview" />
      )}
      {showKind && (
        <div className="field">
          <label>Tür</label>
          <select
            value={ticket.kind}
            onChange={(e) => onUpdate({ kind: e.target.value })}
          >
            {Object.entries(KIND_LABELS).map(([k, v]) => (
              <option key={k} value={k}>
                {v}
              </option>
            ))}
          </select>
        </div>
      )}
      <div className="field">
        <label>Açıklama</label>
        <input
          value={ticket.label}
          placeholder="ör. THY IST → CDG"
          onChange={(e) => onUpdate({ label: e.target.value })}
        />
      </div>
      <div className="grid-2">
        <div className="field">
          <label>Tarih</label>
          <input
            type="date"
            value={ticket.visitDate ?? ''}
            onChange={(e) => onUpdate({ visitDate: e.target.value })}
          />
        </div>
        <label
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: 8,
            fontSize: 15,
            paddingTop: 28,
          }}
        >
          <input
            type="checkbox"
            checked={ticket.purchased}
            onChange={(e) => onUpdate({ purchased: e.target.checked })}
          />
          Alındı
        </label>
      </div>
      <div className="scan-actions">
        <label className="btn btn-secondary btn-sm" style={{ cursor: 'pointer' }}>
          📷 Galeri
          <input
            type="file"
            accept="image/*"
            hidden
            disabled={scanning}
            onChange={(e) => onScanFile(e.target.files?.[0])}
          />
        </label>
        <label className="btn btn-secondary btn-sm" style={{ cursor: 'pointer' }}>
          📸 Kamera
          <input
            type="file"
            accept="image/*"
            capture="environment"
            hidden
            disabled={scanning}
            onChange={(e) => onScanFile(e.target.files?.[0])}
          />
        </label>
      </div>
      {scanning && <p className="ocr-progress">Metin okunuyor…</p>}
      {ticket.scannedText && !scanning && (
        <p style={{ fontSize: 12, color: 'var(--text-tertiary)' }}>
          Okunan: {ticket.scannedText.slice(0, 100)}…
        </p>
      )}
    </div>
  );
}
