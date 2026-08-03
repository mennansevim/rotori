import { useEffect, useState } from 'react';
import type { DayPlan, TripPreferences } from '@japan-trip/shared';

interface Props {
  day: DayPlan;
  prefs: TripPreferences;
  weather?: string;
  /** Sabah aralığında mıyız (06:00-12:00). */
  visible: boolean;
  onEdit: () => void;
  onDismiss: () => void;
}

interface ApiResponse {
  source?: string;
  summary?: string;
  error?: string;
}

export function MorningSummary({ day, prefs, weather, visible, onEdit, onDismiss }: Props) {
  const [summary, setSummary] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!visible || summary != null) return;
    let cancelled = false;
    setLoading(true);
    setError(null);
    (async () => {
      try {
        const resp = await fetch('/api/morning-summary', {
          method: 'POST',
          headers: { 'content-type': 'application/json' },
          body: JSON.stringify({ day, prefs, weather }),
        });
        const data = (await resp.json()) as ApiResponse;
        if (cancelled) return;
        if (data.summary) {
          setSummary(data.summary);
        } else {
          setError('Özet alınamadı.');
        }
      } catch {
        if (!cancelled) setError('Bağlantı hatası.');
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [visible, day, prefs, weather, summary]);

  if (!visible) return null;

  return (
    <div className="morning-summary" role="region" aria-label="Sabah özeti">
      <div className="morning-summary-head">
        <span className="morning-summary-emoji">☀️</span>
        <strong>Sabah özeti</strong>
        <button
          type="button"
          className="morning-summary-close"
          onClick={onDismiss}
          aria-label="Kapat"
        >
          ×
        </button>
      </div>
      <div className="morning-summary-body">
        {loading && <p className="morning-summary-loading">Günün özeti hazırlanıyor…</p>}
        {error && <p className="morning-summary-error">{error}</p>}
        {summary && <p>{summary}</p>}
      </div>
      <div className="morning-summary-actions">
        <button type="button" className="btn-primary btn-sm-rounded" onClick={onEdit}>
          ✨ Bugünü düzenle
        </button>
        <button type="button" className="btn-ghost btn-sm-rounded" onClick={onDismiss}>
          Devam et
        </button>
      </div>
    </div>
  );
}
