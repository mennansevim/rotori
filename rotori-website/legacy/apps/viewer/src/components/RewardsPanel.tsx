import { ALL_BADGES } from '../utils/userStats';
import type { UserStats } from '@japan-trip/shared';
import { xpToLevel } from '@japan-trip/shared';

interface Props {
  stats: UserStats;
}

export function RewardsPanel({ stats }: Props) {
  const earned = new Set(stats.badgesEarned);
  const { level, progress, nextThreshold } = xpToLevel(stats.xp);
  const earnedCount = stats.badgesEarned.length;
  const total = ALL_BADGES.length;

  return (
    <section className="rewards-panel" id="rozetler">
      <div className="section-header">
        <div
          className="section-icon"
          style={{ background: 'linear-gradient(135deg, #f59e0b, #ec4899)' }}
        >
          🏆
        </div>
        <div>
          <h2 className="section-title">Rozetler & XP</h2>
          <div className="section-subtitle">
            Level {level} · {stats.xp} XP · {earnedCount}/{total} rozet
          </div>
        </div>
      </div>

      <div className="rewards-progress">
        <div className="rewards-progress-bar">
          <div
            className="rewards-progress-fill"
            style={{ width: `${Math.round(progress * 100)}%` }}
          />
        </div>
        <div className="rewards-progress-meta">
          <span>Level {level}</span>
          <span>{nextThreshold} XP sonraki seviyeye</span>
        </div>
      </div>

      <div className="badge-grid">
        {ALL_BADGES.map((b) => {
          const isEarned = earned.has(b.id);
          return (
            <article key={b.id} className={`badge-card${isEarned ? ' earned' : ''}`}>
              <div className="badge-emoji" aria-hidden>
                {b.emoji}
              </div>
              <div className="badge-title">{b.title}</div>
              <div className="badge-desc">{isEarned ? b.description : b.hint}</div>
              {!isEarned && <div className="badge-locked">🔒 Kilitli</div>}
            </article>
          );
        })}
      </div>
    </section>
  );
}
