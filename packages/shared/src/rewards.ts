import type { Trip } from './types.js';

/** Kullanıcı XP eylemleri. */
export type XpAction =
  | 'plan-created'
  | 'day-completed'
  | 'edit-used'
  | 'weather-replan'
  | 'community-joined'
  | 'badge-earned';

export const XP_RULES: Record<XpAction, number> = {
  'plan-created': 10,
  'day-completed': 20,
  'edit-used': 15,
  'weather-replan': 20,
  'community-joined': 25,
  'badge-earned': 50,
};

export interface BadgeDefinition {
  id: string;
  emoji: string;
  title: string;
  /** Kısa açıklama (rozet kartında görünür). */
  description: string;
  /** Henüz kazanılmamışken nasıl kazanılır ipucu. */
  hint: string;
  /** trip + stats verisiyle değerlendirme. true dönerse rozet kazanıldı sayılır. */
  evaluate: (trip: Trip, stats: UserStats) => boolean;
}

export interface UserStats {
  xp: number;
  badgesEarned: string[];
  /** XP geçmişi (ya da action sayacı) — analytics/animation için. */
  actionCounts: Partial<Record<XpAction, number>>;
  /** Eylemin ilk gerçekleştiği tarih (ISO). */
  firstActionAt?: Partial<Record<XpAction, string>>;
  /** Topluluk tercihi (ay + şehir odası), opsiyonel. */
  community?: { month?: string; cityRoom?: string };
}

export const EMPTY_STATS: UserStats = {
  xp: 0,
  badgesEarned: [],
  actionCounts: {},
  firstActionAt: {},
};

function totalDays(trip: Trip): number {
  return trip.days?.length ?? 0;
}

function destinationCities(trip: Trip): string[] {
  return (trip.preferences.destinations ?? []).map((d) => d.city.toLowerCase());
}

function dayThemesContain(trip: Trip, needle: string): boolean {
  const n = needle.toLowerCase();
  return (trip.days ?? []).some(
    (d) =>
      (d.theme ?? '').toLowerCase().includes(n) ||
      (d.tags ?? []).some((t) => t.toLowerCase().includes(n)) ||
      (d.items ?? []).some(
        (it) =>
          (it.title ?? '').toLowerCase().includes(n) ||
          (it.description ?? '').toLowerCase().includes(n),
      ),
  );
}

function maxStepsInTrip(trip: Trip): number {
  let max = 0;
  for (const d of trip.days ?? []) {
    const s = d.stepsEstimate ?? 0;
    if (s > max) max = s;
  }
  return max;
}

export const BADGE_DEFINITIONS: BadgeDefinition[] = [
  {
    id: 'first-japan-plan',
    emoji: '🇯🇵',
    title: 'İlk Japonya Planı',
    description: 'Japonya gezi planını oluşturdun.',
    hint: 'Planlayıcıdan ilk planı kaydet.',
    evaluate: (trip) => totalDays(trip) >= 1,
  },
  {
    id: 'osaka-explorer',
    emoji: '🐙',
    title: 'Osaka Kaşifi',
    description: "Osaka'yı rotana ekledin.",
    hint: 'Rotaya Osaka eklendiğinde açılır.',
    evaluate: (trip) => destinationCities(trip).some((c) => c.includes('osaka')),
  },
  {
    id: 'kyoto-temple-wanderer',
    emoji: '⛩️',
    title: 'Kyoto Tapınak Gezgini',
    description: 'Kyoto’da tapınak rotası planladın.',
    hint: "Kyoto'ya git + Fushimi Inari / tapınak ekle.",
    evaluate: (trip) =>
      destinationCities(trip).some((c) => c.includes('kyoto')) &&
      (dayThemesContain(trip, 'tapınak') || dayThemesContain(trip, 'fushimi')),
  },
  {
    id: 'nara-deer-friend',
    emoji: '🦌',
    title: 'Nara Geyik Dostu',
    description: 'Nara durağı planına girdi.',
    hint: 'Rotana Nara ekle.',
    evaluate: (trip) => destinationCities(trip).some((c) => c.includes('nara')),
  },
  {
    id: 'pokemon-hunter',
    emoji: '⚡',
    title: 'Pokémon Avcısı',
    description: 'Pokémon ilgisini açtın.',
    hint: 'Onboarding\'de Pokémon ilgi alanını seç.',
    evaluate: (trip) => (trip.preferences.interests ?? []).includes('pokemon'),
  },
  {
    id: 'donki-expert',
    emoji: '🛍️',
    title: 'Donki Uzmanı',
    description: 'Alışverişe odaklı bir plan kurdun.',
    hint: 'Shopping ilgi alanını seç.',
    evaluate: (trip) => (trip.preferences.interests ?? []).includes('shopping'),
  },
  {
    id: 'kids-japan',
    emoji: '🧸',
    title: 'Çocukla Japonya',
    description: 'Çocuklu bir Japonya gezisi planladın.',
    hint: 'Çocuk profili gir.',
    evaluate: (trip) =>
      (trip.preferences.childProfiles?.length ?? trip.preferences.childrenCount ?? 0) > 0,
  },
  {
    id: 'rainy-day-saviour',
    emoji: '🌧️',
    title: 'Yağmurlu Gün Kurtarıcısı',
    description: "Hava'ya göre planla özelliğini kullandın.",
    hint: 'WeatherStrip\'teki "🪄 Hava\'ya göre planla" butonunu kullan.',
    evaluate: (_t, stats) => (stats.actionCounts['weather-replan'] ?? 0) > 0,
  },
  {
    id: 'first-revision',
    emoji: '✨',
    title: 'İlk Plan Revizyonu',
    description: 'AI düzenleme kullandın.',
    hint: 'Düzenle butonuyla planı revize et.',
    evaluate: (_t, stats) => (stats.actionCounts['edit-used'] ?? 0) > 0,
  },
  {
    id: 'long-walker',
    emoji: '👟',
    title: '20.000 Adım Günü',
    description: 'Plana çok yürüyüşlü bir gün koydun.',
    hint: 'Bir günün adım tahmini 20.000+ olsun.',
    evaluate: (trip) => maxStepsInTrip(trip) >= 20000,
  },
  {
    id: 'medium-walker',
    emoji: '🥾',
    title: '10.000 Adım Günü',
    description: '10.000+ adım hedefli bir gün hazırladın.',
    hint: 'Bir günün adım tahmini 10.000+ olsun.',
    evaluate: (trip) => maxStepsInTrip(trip) >= 10000,
  },
  {
    id: 'community-joined',
    emoji: '👥',
    title: 'Topluluğa Katkı',
    description: 'Beta topluluğa ilgi gösterdin.',
    hint: 'Beta topluluk bölümünden bir oda seç.',
    evaluate: (_t, stats) => !!stats.community?.cityRoom,
  },
];

export function getBadge(id: string): BadgeDefinition | undefined {
  return BADGE_DEFINITIONS.find((b) => b.id === id);
}

/**
 * trip + stats üzerinden tüm rozetleri değerlendirir; yeni kazanılanları döndürür.
 */
export function evaluateBadges(
  trip: Trip,
  stats: UserStats,
): { newly: BadgeDefinition[]; allEarnedIds: string[] } {
  const earned = new Set(stats.badgesEarned);
  const newly: BadgeDefinition[] = [];
  for (const badge of BADGE_DEFINITIONS) {
    if (earned.has(badge.id)) continue;
    try {
      if (badge.evaluate(trip, stats)) {
        earned.add(badge.id);
        newly.push(badge);
      }
    } catch {
      /* ignore evaluator errors */
    }
  }
  return { newly, allEarnedIds: Array.from(earned) };
}

/**
 * XP'yi level + ilerleme yüzdesine çevirir.
 * Basit progresyon: her level 100 XP gerektirir.
 */
export function xpToLevel(xp: number): { level: number; progress: number; nextThreshold: number } {
  const level = Math.floor(xp / 100) + 1;
  const into = xp % 100;
  return { level, progress: into / 100, nextThreshold: 100 - into };
}
