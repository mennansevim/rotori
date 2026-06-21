import { useState } from 'react';
import { collectTripWarnings, type TripWarning } from '@japan-trip/shared';
import type { Trip } from '@japan-trip/shared';

interface Props {
  trip: Trip;
  onExport: () => void;
  onImport: (file: File) => void;
  username?: string;
  onJumpToStep?: (step: NonNullable<TripWarning['step']>) => void;
}

const STEP_LABELS: Record<NonNullable<TripWarning['step']>, string> = {
  journey: 'Rota',
  explore: 'Keşfet',
  title: 'Başlık',
  hotels: 'Konaklama',
  food: 'Yemek',
  plan: 'Plan',
  calendar: 'Takvim',
};

function buildShareUrl(username: string): string {
  if (typeof window === 'undefined') return `/viewer/?u=${username}`;
  const base = `${window.location.protocol}//${window.location.host}/viewer/`;
  return `${base}?u=${encodeURIComponent(username)}`;
}

export function PublishStep({
  trip,
  onExport,
  onImport,
  username = 'default',
  onJumpToStep,
}: Props) {
  const warnings = collectTripWarnings(trip);
  const shareUrl = buildShareUrl(username);
  const [copied, setCopied] = useState(false);

  const copyShare = async () => {
    try {
      await navigator.clipboard.writeText(shareUrl);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 1800);
    } catch {
      /* ignore */
    }
  };

  return (
    <>
      <h2 className="page-headline">Yayına hazır</h2>
      <p className="page-sub">
        Planınız <strong>{username}</strong> kullanıcısı altında kaydedildi. Aşağıdaki bağlantıyı paylaşarak başka tarayıcıdan/cihazdan
        rehbere ulaşılabilir. Her kullanıcının planı kendi adıyla saklanır — başkalarınınkiyle çakışmaz.
      </p>

      {warnings.map((w) => (
        <div
          key={w.id}
          className={`alert-banner ${w.severity === 'urgent' ? 'warn' : w.severity}`}
        >
          <span>{w.message}</span>
          {w.step && onJumpToStep && (
            <button
              type="button"
              className="btn btn-secondary btn-sm alert-banner-action"
              onClick={() => onJumpToStep(w.step!)}
            >
              {STEP_LABELS[w.step]} adımına dön →
            </button>
          )}
        </div>
      ))}

      <div className="card">
        <div className="card-title">Paylaşılabilir bağlantı</div>
        <div
          style={{
            display: 'flex',
            gap: 8,
            alignItems: 'center',
            background: 'var(--bg)',
            border: '1px solid var(--border)',
            borderRadius: 10,
            padding: '8px 12px',
            marginBottom: 12,
            fontFamily: 'ui-monospace, SFMono-Regular, Menlo, monospace',
            fontSize: 13,
            wordBreak: 'break-all',
          }}
        >
          <span style={{ flex: 1 }}>{shareUrl}</span>
          <button type="button" className="btn btn-secondary btn-sm" onClick={copyShare}>
            {copied ? '✓ Kopyalandı' : 'Kopyala'}
          </button>
        </div>
        <a
          href={`/viewer/?u=${encodeURIComponent(username)}`}
          target="_blank"
          rel="noopener noreferrer"
          className="btn btn-primary btn-block"
          style={{ textDecoration: 'none', marginBottom: 12 }}
        >
          Mobil rehberi aç →
        </a>
        <div style={{ display: 'flex', gap: 10, flexWrap: 'wrap' }}>
          <button type="button" className="btn btn-secondary" onClick={onExport}>
            JSON indir
          </button>
          <label className="btn btn-secondary" style={{ cursor: 'pointer' }}>
            JSON yükle
            <input
              type="file"
              accept="application/json"
              hidden
              onChange={(e) => {
                const f = e.target.files?.[0];
                if (f) onImport(f);
              }}
            />
          </label>
        </div>
        <p style={{ fontSize: 13, color: 'var(--text-tertiary)', marginTop: 16 }}>
          Pi deploy: <code>data/trips/{trip.slug}.json</code> dosyasını commit edin.
        </p>
      </div>
    </>
  );
}
