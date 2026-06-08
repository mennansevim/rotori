import type { Trip } from '@japan-trip/shared';

export type ThemeId = 'japan-dark' | 'apple-light' | 'sakura-soft';

const THEMES: { id: ThemeId; label: string }[] = [
  { id: 'japan-dark', label: 'Japonya' },
  { id: 'apple-light', label: 'Apple' },
  { id: 'sakura-soft', label: 'Sakura' },
];

interface Props {
  open: boolean;
  theme: ThemeId;
  username: string;
  trip: Trip;
  onTheme: (t: ThemeId) => void;
  onClose: () => void;
}

export function SettingsDrawer({ open, theme, username, trip, onTheme, onClose }: Props) {
  if (!open) return null;

  const plannerUrl = `/planner/?u=${encodeURIComponent(username)}`;
  const shareUrl = typeof window !== 'undefined'
    ? `${window.location.protocol}//${window.location.host}/viewer/?u=${encodeURIComponent(username)}`
    : `/viewer/?u=${username}`;

  const copyShare = async () => {
    try {
      await navigator.clipboard.writeText(shareUrl);
      alert('Bağlantı kopyalandı ✓');
    } catch {
      alert(shareUrl);
    }
  };

  return (
    <div className="settings-backdrop" role="dialog" aria-modal="true" onClick={onClose}>
      <div className="settings-drawer" onClick={(e) => e.stopPropagation()}>
        <div className="settings-head">
          <h3>⚙ Ayarlar</h3>
          <button type="button" className="settings-close" onClick={onClose} aria-label="Kapat">
            ×
          </button>
        </div>

        <div className="settings-section">
          <h4>Kullanıcı</h4>
          <div className="settings-user-line">
            <strong>{username}</strong>
            <br />
            Plan: <em>{trip.title || 'İsimsiz seyahat'}</em>
          </div>
          <button type="button" className="settings-link-btn" onClick={() => void copyShare()}>
            <span className="icon">🔗</span>
            <span>
              Paylaşılabilir bağlantıyı kopyala
              <div className="sub">Başkaları aynı linkten görür, planınız çakışmaz</div>
            </span>
          </button>
        </div>

        <div className="settings-section">
          <h4>Tema</h4>
          <div className="theme-options">
            {THEMES.map((t) => (
              <button
                key={t.id}
                type="button"
                className={`theme-option${theme === t.id ? ' active' : ''}`}
                onClick={() => onTheme(t.id)}
              >
                <div className={`theme-preview ${t.id}`} />
                <div className="theme-label">{t.label}</div>
              </button>
            ))}
          </div>
        </div>

        <div className="settings-section">
          <h4>Düzenleme</h4>
          <a className="settings-link-btn" href={plannerUrl}>
            <span className="icon">✏️</span>
            <span>
              Planlayıcıyı aç
              <div className="sub">Geçmemiş günleri, aktiviteleri ve rotayı düzenle</div>
            </span>
          </a>
          <a className="settings-link-btn" href="/">
            <span className="icon">🏠</span>
            <span>
              Klasik rehber
              <div className="sub">Statik index.html sürümü</div>
            </span>
          </a>
        </div>
      </div>
    </div>
  );
}
