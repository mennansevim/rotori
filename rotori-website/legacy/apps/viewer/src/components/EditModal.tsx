import { useEffect, useState } from 'react';
import type { DayPlan, Trip } from '@japan-trip/shared';
import { submitEdit, type EditScope } from '../utils/editApi';

interface Props {
  trip: Trip;
  activeDayNumber: number | null;
  initialInstruction?: string;
  initialWeather?: string;
  onClose: () => void;
  onApply: (next: { summary: string; days: DayPlan[] }) => void;
}

const SCOPE_OPTIONS: { id: EditScope; label: string; hint: string }[] = [
  { id: 'today', label: 'Bugün', hint: 'Sadece aktif günü revize et' },
  { id: 'day', label: 'Seçili gün', hint: 'Belirli bir günü revize et' },
  { id: 'all', label: 'Tüm gezi', hint: 'Tüm günleri revize et' },
];

const QUICK_PROMPTS: string[] = [
  'Bugün çok yorulduk, daha hafif planla.',
  'Sabah geç kalktık, planı 11:30’dan başlat.',
  'Yağmur başladı, kapalı alanlara göre değiştir.',
  'Bu gündeki tapınak gezisini çıkar, yerine alışveriş ekle.',
  'Akşam Dotonbori’de yemek yemek istiyorum.',
  'Çocuk yoruldu, öğleden sonrayı daha hafif yap.',
];

export function EditModal({
  trip,
  activeDayNumber,
  initialInstruction = '',
  initialWeather,
  onClose,
  onApply,
}: Props) {
  const [scope, setScope] = useState<EditScope>(activeDayNumber != null ? 'today' : 'all');
  const [targetDayNumber, setTargetDayNumber] = useState<number>(
    activeDayNumber ?? trip.days[0]?.dayNumber ?? 1,
  );
  const [instruction, setInstruction] = useState(initialInstruction);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [preview, setPreview] = useState<{ summary: string; days: DayPlan[] } | null>(null);

  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [onClose]);

  const canSubmit = instruction.trim().length >= 4 && !busy;

  const send = async () => {
    setBusy(true);
    setError(null);
    setPreview(null);
    const resp = await submitEdit({
      trip,
      instruction: instruction.trim(),
      scope,
      targetDayNumber: scope === 'all' ? undefined : targetDayNumber,
      weather: initialWeather,
    });
    setBusy(false);
    if (!resp.ok) {
      const msg =
        resp.error.kind === 'not-configured'
          ? 'AI servisi yapılandırılmadı (GROQ_API_KEY gerekli).'
          : resp.error.kind === 'network'
            ? 'Ağ hatası — internet bağlantını kontrol et.'
            : 'AI yanıtı alınamadı, tekrar dene.';
      setError(msg);
      return;
    }
    setPreview({ summary: resp.result.summary, days: resp.result.days });
  };

  const confirm = () => {
    if (!preview) return;
    onApply(preview);
  };

  return (
    <div className="edit-modal-overlay" onClick={onClose}>
      <div
        className="edit-modal"
        role="dialog"
        aria-modal="true"
        aria-labelledby="edit-modal-title"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="edit-modal-head">
          <h3 id="edit-modal-title">✨ AI ile düzenle</h3>
          <button
            type="button"
            className="edit-modal-close"
            onClick={onClose}
            aria-label="Kapat"
          >
            ×
          </button>
        </div>

        {!preview ? (
          <>
            <div className="edit-modal-body">
              <label className="edit-label">Planında neyi değiştirmek istersin?</label>
              <textarea
                value={instruction}
                onChange={(e) => setInstruction(e.target.value)}
                rows={4}
                placeholder="Örn: Bugün çok yorulduk, daha hafif planla."
                className="edit-textarea"
                autoFocus
              />

              <div className="edit-quick-prompts">
                {QUICK_PROMPTS.map((p) => (
                  <button
                    key={p}
                    type="button"
                    className="edit-quick-prompt"
                    onClick={() => setInstruction(p)}
                  >
                    {p}
                  </button>
                ))}
              </div>

              <label className="edit-label">Kapsam</label>
              <div className="edit-scope">
                {SCOPE_OPTIONS.map((opt) => (
                  <button
                    key={opt.id}
                    type="button"
                    className={`edit-scope-chip${scope === opt.id ? ' active' : ''}`}
                    onClick={() => setScope(opt.id)}
                  >
                    <strong>{opt.label}</strong>
                    <span>{opt.hint}</span>
                  </button>
                ))}
              </div>

              {scope === 'day' && (
                <div className="edit-day-pick">
                  <label className="edit-label">Hangi gün?</label>
                  <select
                    value={targetDayNumber}
                    onChange={(e) => setTargetDayNumber(Number(e.target.value))}
                  >
                    {trip.days.map((d) => (
                      <option key={d.dayNumber} value={d.dayNumber}>
                        Gün {d.dayNumber} — {d.theme || d.date}
                      </option>
                    ))}
                  </select>
                </div>
              )}

              {error && <div className="edit-error">{error}</div>}
            </div>

            <div className="edit-modal-foot">
              <button type="button" className="btn-ghost" onClick={onClose}>
                İptal
              </button>
              <button
                type="button"
                className="btn-primary"
                disabled={!canSubmit}
                onClick={send}
              >
                {busy ? 'AI düşünüyor…' : '✨ Revize et'}
              </button>
            </div>
          </>
        ) : (
          <>
            <div className="edit-modal-body">
              <div className="edit-summary">
                <strong>Değişiklik özeti</strong>
                <p>{preview.summary || 'AI değişiklikleri uyguladı.'}</p>
              </div>
              <div className="edit-preview-days">
                {preview.days
                  .filter(
                    (d) =>
                      scope === 'all' ||
                      d.dayNumber === targetDayNumber ||
                      (scope === 'today' && d.dayNumber === activeDayNumber),
                  )
                  .map((d) => (
                    <div key={d.dayNumber} className="edit-preview-day">
                      <div className="edit-preview-day-head">
                        <strong>Gün {d.dayNumber}</strong>
                        <span>{d.theme}</span>
                      </div>
                      <ul>
                        {d.items.slice(0, 8).map((it) => (
                          <li key={it.id}>
                            <span className="edit-preview-time">{it.time}</span> {it.title}
                          </li>
                        ))}
                        {d.items.length > 8 && <li>… +{d.items.length - 8} daha</li>}
                      </ul>
                    </div>
                  ))}
              </div>
            </div>

            <div className="edit-modal-foot">
              <button type="button" className="btn-ghost" onClick={() => setPreview(null)}>
                ← Geri
              </button>
              <button type="button" className="btn-primary" onClick={confirm}>
                ✓ Uygula
              </button>
            </div>
          </>
        )}
      </div>
    </div>
  );
}
