// apps/viewer/src/utils/userStats.ts + packages/shared/src/rewards.ts portu.
// XP / level / rozet durumu — SharedPreferences arkasında JSON depolar.
// Anahtar formatı React ile aynı: viewer:stats:<userId>

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/types.dart';

// ---------------------------------------------------------------------------
// XP kuralları + level hesabı (rewards.ts)
// ---------------------------------------------------------------------------

/// Kullanıcı XP eylemleri.
const Map<String, int> kXpRules = {
  'plan-created': 10,
  'day-completed': 20,
  'edit-used': 15,
  'weather-replan': 20,
  'community-joined': 25,
  'badge-earned': 50,
};

class LevelInfo {
  const LevelInfo({
    required this.level,
    required this.progress,
    required this.nextThreshold,
  });

  final int level;

  /// 0..1 — mevcut level içindeki ilerleme.
  final double progress;

  /// Sonraki levele kalan XP.
  final int nextThreshold;
}

/// XP'yi level + ilerleme yüzdesine çevirir.
/// Basit progresyon: her level 100 XP gerektirir.
LevelInfo xpToLevel(int xp) {
  final level = (xp ~/ 100) + 1;
  final into = xp % 100;
  return LevelInfo(level: level, progress: into / 100, nextThreshold: 100 - into);
}

// ---------------------------------------------------------------------------
// UserStats modeli
// ---------------------------------------------------------------------------

class UserStats {
  const UserStats({
    this.xp = 0,
    this.badgesEarned = const [],
    this.actionCounts = const {},
    this.firstActionAt = const {},
    this.discoveredPlaceIds = const [],
    this.discoveredCityCounts = const {},
    this.communityMonth,
    this.communityCityRoom,
  });

  final int xp;
  final List<String> badgesEarned;

  /// XP geçmişi (action sayacı) — analytics/animation için.
  final Map<String, int> actionCounts;

  /// Eylemin ilk gerçekleştiği tarih (ISO).
  final Map<String, String> firstActionAt;

  /// GPS ile fiziksel olarak keşfedilen geofence id'leri (dwell tamamlanan).
  final List<String> discoveredPlaceIds;

  /// Küçük-harf şehir -> o şehirde keşfedilen nokta sayısı.
  final Map<String, int> discoveredCityCounts;

  /// Topluluk tercihi (ay + şehir odası), opsiyonel.
  final String? communityMonth;
  final String? communityCityRoom;

  UserStats copyWith({
    int? xp,
    List<String>? badgesEarned,
    Map<String, int>? actionCounts,
    Map<String, String>? firstActionAt,
    List<String>? discoveredPlaceIds,
    Map<String, int>? discoveredCityCounts,
  }) =>
      UserStats(
        xp: xp ?? this.xp,
        badgesEarned: badgesEarned ?? this.badgesEarned,
        actionCounts: actionCounts ?? this.actionCounts,
        firstActionAt: firstActionAt ?? this.firstActionAt,
        discoveredPlaceIds: discoveredPlaceIds ?? this.discoveredPlaceIds,
        discoveredCityCounts: discoveredCityCounts ?? this.discoveredCityCounts,
        communityMonth: communityMonth,
        communityCityRoom: communityCityRoom,
      );

  /// GPS ile yeni bir nokta keşfedildiğinde çağrılır. [placeId] daha önce
  /// keşfedilmediyse listeye eklenir ve [city] (küçük harfe çevrilir) sayacı
  /// bir artar. Aynı id tekrar gelirse `this` değişmeden döner (idempotent).
  UserStats withDiscovery(String placeId, String city) {
    if (discoveredPlaceIds.contains(placeId)) return this;
    final key = city.toLowerCase();
    return copyWith(
      discoveredPlaceIds: [...discoveredPlaceIds, placeId],
      discoveredCityCounts: {
        ...discoveredCityCounts,
        key: (discoveredCityCounts[key] ?? 0) + 1,
      },
    );
  }

  factory UserStats.fromJson(Map<String, dynamic> j) {
    final community = (j['community'] as Map?)?.cast<String, dynamic>();
    return UserStats(
      xp: ((j['xp'] as num?) ?? 0).toInt(),
      badgesEarned: List<String>.from(j['badgesEarned'] as List? ?? const []),
      actionCounts: ((j['actionCounts'] as Map?) ?? const {})
          .map((k, v) => MapEntry(k as String, (v as num).toInt())),
      firstActionAt: ((j['firstActionAt'] as Map?) ?? const {})
          .map((k, v) => MapEntry(k as String, v as String)),
      discoveredPlaceIds:
          List<String>.from(j['discoveredPlaceIds'] as List? ?? const []),
      discoveredCityCounts: ((j['discoveredCityCounts'] as Map?) ?? const {})
          .map((k, v) => MapEntry(k as String, (v as num).toInt())),
      communityMonth: community?['month'] as String?,
      communityCityRoom: community?['cityRoom'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'xp': xp,
        'badgesEarned': badgesEarned,
        'actionCounts': actionCounts,
        'firstActionAt': firstActionAt,
        'discoveredPlaceIds': discoveredPlaceIds,
        'discoveredCityCounts': discoveredCityCounts,
        if (communityMonth != null || communityCityRoom != null)
          'community': {
            if (communityMonth != null) 'month': communityMonth,
            if (communityCityRoom != null) 'cityRoom': communityCityRoom,
          },
      };
}

// ---------------------------------------------------------------------------
// Rozet tanımları (rewards.ts BADGE_DEFINITIONS)
// ---------------------------------------------------------------------------

class BadgeDefinition {
  const BadgeDefinition({
    required this.id,
    required this.emoji,
    required this.title,
    required this.description,
    required this.hint,
    required this.evaluate,
  });

  final String id;
  final String emoji;
  final String title;

  /// Kısa açıklama (rozet kartında görünür).
  final String description;

  /// Henüz kazanılmamışken nasıl kazanılır ipucu.
  final String hint;

  /// trip + stats verisiyle değerlendirme. true dönerse rozet kazanıldı sayılır.
  final bool Function(Trip trip, UserStats stats) evaluate;
}

int _totalDays(Trip trip) => trip.days.length;

List<String> _destinationCities(Trip trip) =>
    trip.preferences.destinations.map((d) => d.city.toLowerCase()).toList();

bool _dayThemesContain(Trip trip, String needle) {
  final n = needle.toLowerCase();
  return trip.days.any(
    (d) =>
        d.theme.toLowerCase().contains(n) ||
        d.tags.any((t) => t.toLowerCase().contains(n)) ||
        d.items.any(
          (it) =>
              it.title.toLowerCase().contains(n) ||
              (it.description ?? '').toLowerCase().contains(n),
        ),
  );
}

int _maxStepsInTrip(Trip trip) {
  var max = 0;
  for (final d in trip.days) {
    final s = d.stepsEstimate ?? 0;
    if (s > max) max = s;
  }
  return max;
}

final List<BadgeDefinition> kBadgeDefinitions = [
  BadgeDefinition(
    id: 'first-japan-plan',
    emoji: '🇯🇵',
    title: 'İlk Japonya Planı',
    description: 'Japonya gezi planını oluşturdun.',
    hint: 'Planlayıcıdan ilk planı kaydet.',
    evaluate: (trip, _) => _totalDays(trip) >= 1,
  ),
  BadgeDefinition(
    id: 'osaka-explorer',
    emoji: '🐙',
    title: 'Osaka Kaşifi',
    description: "Osaka'yı rotana ekledin.",
    hint: 'Rotaya Osaka eklendiğinde açılır.',
    evaluate: (trip, _) =>
        _destinationCities(trip).any((c) => c.contains('osaka')),
  ),
  BadgeDefinition(
    id: 'kyoto-temple-wanderer',
    emoji: '⛩️',
    title: 'Kyoto Tapınak Gezgini',
    description: 'Kyoto’da tapınak rotası planladın.',
    hint: "Kyoto'ya git + Fushimi Inari / tapınak ekle.",
    evaluate: (trip, _) =>
        _destinationCities(trip).any((c) => c.contains('kyoto')) &&
        (_dayThemesContain(trip, 'tapınak') ||
            _dayThemesContain(trip, 'fushimi')),
  ),
  BadgeDefinition(
    id: 'nara-deer-friend',
    emoji: '🦌',
    title: 'Nara Geyik Dostu',
    description: 'Nara durağı planına girdi.',
    hint: 'Rotana Nara ekle.',
    evaluate: (trip, _) =>
        _destinationCities(trip).any((c) => c.contains('nara')),
  ),
  BadgeDefinition(
    id: 'pokemon-hunter',
    emoji: '⚡',
    title: 'Pokémon Avcısı',
    description: 'Pokémon ilgisini açtın.',
    hint: "Onboarding'de Pokémon ilgi alanını seç.",
    evaluate: (trip, _) =>
        trip.preferences.interests.contains(InterestTag.pokemon),
  ),
  BadgeDefinition(
    id: 'donki-expert',
    emoji: '🛍️',
    title: 'Donki Uzmanı',
    description: 'Alışverişe odaklı bir plan kurdun.',
    hint: 'Shopping ilgi alanını seç.',
    evaluate: (trip, _) =>
        trip.preferences.interests.contains(InterestTag.shopping),
  ),
  BadgeDefinition(
    id: 'kids-japan',
    emoji: '🧸',
    title: 'Çocukla Japonya',
    description: 'Çocuklu bir Japonya gezisi planladın.',
    hint: 'Çocuk profili gir.',
    evaluate: (trip, _) =>
        (trip.preferences.childProfiles.isNotEmpty
            ? trip.preferences.childProfiles.length
            : (trip.preferences.childrenCount ?? 0)) >
        0,
  ),
  BadgeDefinition(
    id: 'rainy-day-saviour',
    emoji: '🌧️',
    title: 'Yağmurlu Gün Kurtarıcısı',
    description: "Hava'ya göre planla özelliğini kullandın.",
    hint: 'WeatherStrip\'teki "🪄 Hava\'ya göre planla" butonunu kullan.',
    evaluate: (_, stats) => (stats.actionCounts['weather-replan'] ?? 0) > 0,
  ),
  BadgeDefinition(
    id: 'first-revision',
    emoji: '✨',
    title: 'İlk Plan Revizyonu',
    description: 'AI düzenleme kullandın.',
    hint: 'Düzenle butonuyla planı revize et.',
    evaluate: (_, stats) => (stats.actionCounts['edit-used'] ?? 0) > 0,
  ),
  BadgeDefinition(
    id: 'long-walker',
    emoji: '👟',
    title: '20.000 Adım Günü',
    description: 'Plana çok yürüyüşlü bir gün koydun.',
    hint: 'Bir günün adım tahmini 20.000+ olsun.',
    evaluate: (trip, _) => _maxStepsInTrip(trip) >= 20000,
  ),
  BadgeDefinition(
    id: 'medium-walker',
    emoji: '🥾',
    title: '10.000 Adım Günü',
    description: '10.000+ adım hedefli bir gün hazırladın.',
    hint: 'Bir günün adım tahmini 10.000+ olsun.',
    evaluate: (trip, _) => _maxStepsInTrip(trip) >= 10000,
  ),
  BadgeDefinition(
    id: 'community-joined',
    emoji: '👥',
    title: 'Topluluğa Katkı',
    description: 'Beta topluluğa ilgi gösterdin.',
    hint: 'Beta topluluk bölümünden bir oda seç.',
    evaluate: (_, stats) =>
        stats.communityCityRoom != null && stats.communityCityRoom!.isNotEmpty,
  ),
  // --- GPS keşif rozetleri (yalnız stats okur; trip yok sayılır) ---
  BadgeDefinition(
    id: 'first-discovery',
    emoji: '🧭',
    title: 'İlk Keşif',
    description: 'GPS ile ilk yerini keşfettin.',
    hint: 'Rotandaki bir yere git ve 10 dk kal.',
    evaluate: (_, stats) => stats.discoveredPlaceIds.isNotEmpty,
  ),
  BadgeDefinition(
    id: 'explorer-5',
    emoji: '🗺️',
    title: 'Kaşif',
    description: '5 yer keşfettin.',
    hint: 'GPS ile 5 farklı yeri gez.',
    evaluate: (_, stats) => stats.discoveredPlaceIds.length >= 5,
  ),
  BadgeDefinition(
    id: 'explorer-10',
    emoji: '🎌',
    title: 'Japonya Gezgini',
    description: '10 yer keşfettin.',
    hint: 'GPS ile 10 farklı yeri gez.',
    evaluate: (_, stats) => stats.discoveredPlaceIds.length >= 10,
  ),
  BadgeDefinition(
    id: 'tokyo-roamer',
    emoji: '🗼',
    title: 'Tokyo Kâşifi',
    description: "Tokyo'da 3 yer gezdin.",
    hint: "Tokyo'da GPS ile 3 yer keşfet.",
    evaluate: (_, stats) => (stats.discoveredCityCounts['tokyo'] ?? 0) >= 3,
  ),
  BadgeDefinition(
    id: 'kyoto-roamer',
    emoji: '⛩️',
    title: 'Kyoto Kâşifi',
    description: "Kyoto'da 3 yer gezdin.",
    hint: "Kyoto'da GPS ile 3 yer keşfet.",
    evaluate: (_, stats) => (stats.discoveredCityCounts['kyoto'] ?? 0) >= 3,
  ),
  BadgeDefinition(
    id: 'osaka-roamer',
    emoji: '🐙',
    title: 'Osaka Kâşifi',
    description: "Osaka'da 3 yer gezdin.",
    hint: "Osaka'da GPS ile 3 yer keşfet.",
    evaluate: (_, stats) => (stats.discoveredCityCounts['osaka'] ?? 0) >= 3,
  ),
];

/// trip + stats üzerinden tüm rozetleri değerlendirir; yeni kazanılanları döndürür.
({List<BadgeDefinition> newly, List<String> allEarnedIds}) evaluateBadges(
  Trip trip,
  UserStats stats,
) {
  final earned = {...stats.badgesEarned};
  final newly = <BadgeDefinition>[];
  for (final badge in kBadgeDefinitions) {
    if (earned.contains(badge.id)) continue;
    try {
      if (badge.evaluate(trip, stats)) {
        earned.add(badge.id);
        newly.add(badge);
      }
    } catch (_) {
      // evaluator hatalarını yut
    }
  }
  return (newly: newly, allEarnedIds: earned.toList());
}

// ---------------------------------------------------------------------------
// Persistans (userStats.ts)
// ---------------------------------------------------------------------------

class UserStatsStore {
  UserStatsStore(this._prefs, this._userId);

  final SharedPreferences _prefs;
  final String _userId;

  String get _key => 'viewer:stats:$_userId';

  UserStats load() {
    final raw = _prefs.getString(_key);
    if (raw == null) return const UserStats();
    try {
      final parsed = jsonDecode(raw);
      if (parsed is! Map<String, dynamic>) return const UserStats();
      return UserStats.fromJson(parsed);
    } on FormatException {
      return const UserStats();
    }
  }

  Future<void> save(UserStats stats) async {
    await _prefs.setString(_key, jsonEncode(stats.toJson()));
  }

  /// GPS ile keşfedilen her nokta için XP ekler (nokta başına +25).
  /// Dönen değer: güncellenmiş (ve kaydedilmiş) stats.
  Future<UserStats> addXp(UserStats current, int xp) async {
    final next = current.copyWith(xp: current.xp + xp);
    await save(next);
    return next;
  }
}
