import {
  BADGE_DEFINITIONS,
  EMPTY_STATS,
  XP_RULES,
  evaluateBadges,
  type BadgeDefinition,
  type Trip,
  type UserStats,
  type XpAction,
} from '@japan-trip/shared';

function key(user: string) {
  return `viewer:stats:${user}`;
}

export function loadStats(user: string): UserStats {
  try {
    const raw = localStorage.getItem(key(user));
    if (!raw) return { ...EMPTY_STATS, actionCounts: {}, firstActionAt: {} };
    const parsed = JSON.parse(raw) as UserStats;
    return {
      xp: parsed.xp ?? 0,
      badgesEarned: parsed.badgesEarned ?? [],
      actionCounts: parsed.actionCounts ?? {},
      firstActionAt: parsed.firstActionAt ?? {},
      community: parsed.community,
    };
  } catch {
    return { ...EMPTY_STATS, actionCounts: {}, firstActionAt: {} };
  }
}

export function saveStats(user: string, stats: UserStats): void {
  try {
    localStorage.setItem(key(user), JSON.stringify(stats));
  } catch {
    /* ignore quota */
  }
}

/**
 * Stats üzerine bir XP eylemi uygular ve trip'le birlikte yeni rozetleri değerlendirir.
 * Dönen değer: güncellenmiş stats + yeni kazanılan rozetler (UI toast için).
 */
export function recordAction(
  current: UserStats,
  action: XpAction,
  trip: Trip,
): { next: UserStats; newBadges: BadgeDefinition[] } {
  const counts = { ...(current.actionCounts ?? {}) };
  counts[action] = (counts[action] ?? 0) + 1;
  const firstAt = { ...(current.firstActionAt ?? {}) };
  if (!firstAt[action]) firstAt[action] = new Date().toISOString();

  let xp = (current.xp ?? 0) + (XP_RULES[action] ?? 0);

  const interim: UserStats = {
    xp,
    badgesEarned: current.badgesEarned ?? [],
    actionCounts: counts,
    firstActionAt: firstAt,
    community: current.community,
  };

  const { newly, allEarnedIds } = evaluateBadges(trip, interim);
  if (newly.length > 0) {
    xp += newly.length * (XP_RULES['badge-earned'] ?? 0);
  }

  const next: UserStats = {
    xp,
    badgesEarned: allEarnedIds,
    actionCounts: counts,
    firstActionAt: firstAt,
    community: current.community,
  };

  return { next, newBadges: newly };
}

/** Plan açıldığında pasif değerlendirme — sayaç artırmadan, sadece rozet kontrolü. */
export function evaluatePassive(
  current: UserStats,
  trip: Trip,
): { next: UserStats; newBadges: BadgeDefinition[] } {
  const { newly, allEarnedIds } = evaluateBadges(trip, current);
  if (newly.length === 0) return { next: current, newBadges: [] };
  const xp = (current.xp ?? 0) + newly.length * (XP_RULES['badge-earned'] ?? 0);
  return {
    next: {
      ...current,
      xp,
      badgesEarned: allEarnedIds,
    },
    newBadges: newly,
  };
}

export function setCommunity(
  current: UserStats,
  community: NonNullable<UserStats['community']>,
  trip: Trip,
): { next: UserStats; newBadges: BadgeDefinition[] } {
  const interim: UserStats = { ...current, community };
  return evaluatePassive(interim, trip);
}

export const ALL_BADGES = BADGE_DEFINITIONS;
