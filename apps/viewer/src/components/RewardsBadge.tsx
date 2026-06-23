import { xpToLevel } from '@japan-trip/shared';
import type { UserStats } from '@japan-trip/shared';
import { ALL_BADGES } from '../utils/userStats';

interface Props {
  stats: UserStats;
  onOpen: () => void;
}

export function RewardsBadge({ stats, onOpen }: Props) {
  const { level } = xpToLevel(stats.xp);
  const earned = stats.badgesEarned.length;
  const total = ALL_BADGES.length;

  return (
    <button
      type="button"
      className="rewards-chip"
      onClick={onOpen}
      aria-label="Rozetler ve XP'yi aç"
    >
      <span className="rewards-chip-emoji" aria-hidden>
        🏆
      </span>
      <span className="rewards-chip-meta">
        <span className="rewards-chip-level">Level {level}</span>
        <span className="rewards-chip-sep">·</span>
        <span>{stats.xp} XP</span>
        <span className="rewards-chip-sep">·</span>
        <span className="rewards-chip-count">
          {earned}/{total}
        </span>
      </span>
    </button>
  );
}
