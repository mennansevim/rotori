import { useState } from 'react';
import { PRE_JAPAN_CARDS, type PreJapanCard } from '@japan-trip/shared';

export function PreJapanGuide() {
  const [open, setOpen] = useState(false);
  const [openCard, setOpenCard] = useState<string | null>(null);

  const toggleCard = (id: string) => {
    setOpenCard((cur) => (cur === id ? null : id));
  };

  return (
    <section className="prejapan-section">
      <button
        type="button"
        className="prejapan-header"
        onClick={() => setOpen((v) => !v)}
        aria-expanded={open}
      >
        <div>
          <div className="prejapan-title">🇯🇵 Gitmeden Önce</div>
          <div className="prejapan-subtitle">
            Visit Japan Web, ödeme, market, valiz transfer ve daha fazlası
          </div>
        </div>
        <span className={`prejapan-chevron${open ? ' open' : ''}`}>▼</span>
      </button>

      {open && (
        <div className="prejapan-grid">
          {PRE_JAPAN_CARDS.map((card) => (
            <CardItem
              key={card.id}
              card={card}
              open={openCard === card.id}
              onToggle={() => toggleCard(card.id)}
            />
          ))}
        </div>
      )}
    </section>
  );
}

function CardItem({
  card,
  open,
  onToggle,
}: {
  card: PreJapanCard;
  open: boolean;
  onToggle: () => void;
}) {
  return (
    <article className={`prejapan-card${open ? ' open' : ''}`}>
      <button
        type="button"
        className="prejapan-card-head"
        onClick={onToggle}
        aria-expanded={open}
      >
        <span className="prejapan-card-emoji">{card.emoji}</span>
        <div className="prejapan-card-text">
          <strong>{card.title}</strong>
          <span>{card.summary}</span>
        </div>
        <span className={`prejapan-chevron${open ? ' open' : ''}`}>▾</span>
      </button>

      {open && (
        <div className="prejapan-card-body">
          {card.body.split('\n\n').map((p, i) => (
            <p key={i}>{p}</p>
          ))}
          {card.bullets && card.bullets.length > 0 && (
            <ul>
              {card.bullets.map((b, i) => (
                <li key={i}>{b}</li>
              ))}
            </ul>
          )}
          {card.links && card.links.length > 0 && (
            <div className="prejapan-card-links">
              {card.links.map((l) => (
                <a key={l.url} href={l.url} target="_blank" rel="noreferrer">
                  {l.label} →
                </a>
              ))}
            </div>
          )}
        </div>
      )}
    </article>
  );
}
