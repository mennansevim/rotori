// Keşif haritası ekranı — "Gezgin rütbesi" (Japon efsane yaratıkları merdiveni)
// odaklı, XP tabanlı ve sade bir keşif yüzeyi. Üstte rütbe madalyonu + XP
// ilerleme, ardından keşif metrikleri, şehir kartları, konum takibi ve
// pasif görünümlü aktivite rozetleri.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
import '../../data/user_stats_store.dart';
import '../../domain/city_places.dart';
import '../../domain/geofence.dart';
import '../../domain/types.dart';
import 'geofence_service.dart';
import 'gps_sim_screen.dart';
import 'viewer_theme.dart';
import 'widgets/city_card.dart';

// ---------------------------------------------------------------------------
// Gezgin rütbesi — her 100 XP bir rütbe (xpToLevel ile birebir). Kanji + romaji
// proper isimlerdir (çevrilmez); anlam metni l10n'den gelir.
// ---------------------------------------------------------------------------

class _RankInfo {
  const _RankInfo({required this.kanji, required this.romaji, required this.id});
  final String kanji;
  final String romaji;
  final String id; // l10n anahtarı: reward.rank.<id>
}

const List<_RankInfo> _kRanks = [
  _RankInfo(kanji: '狸', romaji: 'Tanuki', id: 'tanuki'),
  _RankInfo(kanji: '狐', romaji: 'Kitsune', id: 'kitsune'),
  _RankInfo(kanji: '河童', romaji: 'Kappa', id: 'kappa'),
  _RankInfo(kanji: '天狗', romaji: 'Tengu', id: 'tengu'),
  _RankInfo(kanji: '鶴', romaji: 'Tsuru', id: 'tsuru'),
  _RankInfo(kanji: '麒麟', romaji: 'Kirin', id: 'kirin'),
  _RankInfo(kanji: '鳳凰', romaji: 'Hōō', id: 'hoo'),
  _RankInfo(kanji: '龍', romaji: 'Ryū', id: 'ryu'),
];

int _tierForLevel(int level) => (level - 1).clamp(0, _kRanks.length - 1);

/// Rütbe kademesine palete uyumlu bir vurgu rengi verir (temaya göre uyum).
Color _rankColor(ViewerPalette p, int tier) {
  final colors = [
    p.matcha,
    p.gold,
    p.sky,
    p.sunset,
    p.fuji,
    p.accent,
    p.sakura,
    p.accent,
  ];
  return colors[tier.clamp(0, colors.length - 1)];
}

class RewardMapScreen extends ConsumerStatefulWidget {
  const RewardMapScreen({super.key, required this.trip});
  final Trip trip;

  @override
  ConsumerState<RewardMapScreen> createState() => _RewardMapScreenState();
}

class _RewardMapScreenState extends ConsumerState<RewardMapScreen> {
  void _showDiscovery(Geofence fence) {
    if (!mounted) return;
    final s = LanguageScope.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
          s.p('reward.discovered', {
            'emoji': fence.emoji,
            'name': fence.name,
            'xp': '${fence.xp}',
          }),
        ),
      ),
    );
  }

  void _showBadges(List<BadgeDefinition> newly) {
    if (!mounted || newly.isEmpty) return;
    final s = LanguageScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    for (final b in newly) {
      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(s.p('reward.badgeEarned', {
            'emoji': b.emoji,
            'title': s.s(b.title),
          })),
        ),
      );
    }
  }

  void _openSimulator() {
    final palette = ViewerPalette.of(context);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Theme(
          data: palette.toThemeData(),
          child: ViewerPaletteScope(
            palette: palette,
            child: GpsSimScreen(trip: widget.trip),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(geofenceControllerProvider(widget.trip));
    final s = LanguageScope.of(context);
    final p = ViewerPalette.of(context);

    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        backgroundColor: p.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: p.textPrimary,
        title: Text(
          s.s('reward.title'),
          style: TextStyle(
            color: p.textPrimary,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        actions: [
          IconButton(
            tooltip: s.s('reward.gpsSimTooltip'),
            icon: const Text('🧪', style: TextStyle(fontSize: 18)),
            onPressed: controller == null ? null : _openSimulator,
          ),
        ],
      ),
      body: controller == null
          ? const Center(child: CircularProgressIndicator())
          : _RewardMapBody(
              trip: widget.trip,
              controller: controller
                ..onDiscovered = _showDiscovery
                ..onBadgesEarned = _showBadges,
            ),
    );
  }
}

class _RewardMapBody extends StatelessWidget {
  const _RewardMapBody({required this.trip, required this.controller});

  final Trip trip;
  final GeofenceController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final p = ViewerPalette.of(context);
        final s = LanguageScope.of(context);
        final routeCities = detectTripCities(trip);
        final visits = controller.visits;
        final stats = controller.stats;

        final visited = <String>{};
        final inProgress = <String>{};
        visits.records.forEach((id, rec) {
          if (rec.completedAt != null) {
            visited.add(id);
          } else if (rec.totalDwellSeconds > 0) {
            inProgress.add(id);
          }
        });

        final allPlaces = [for (final c in routeCities) ...c.places];
        final visitedCount =
            allPlaces.where((pl) => visited.contains(pl.id)).length;

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _RankHero(stats: stats, palette: p),
            const SizedBox(height: 14),
            _DiscoveryStats(
              palette: p,
              visited: visitedCount,
              total: allPlaces.length,
              cities: routeCities.length,
            ),
            const SizedBox(height: 20),

            if (routeCities.isEmpty)
              _EmptyCities(palette: p)
            else ...[
              _SectionLabel(
                label: s.s('reward.exploreProgress'),
                palette: p,
              ),
              const SizedBox(height: 6),
              _IntroHint(palette: p, text: s.s('reward.cityIntro')),
              const SizedBox(height: 14),
              for (final city in routeCities)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: CityCard(
                    city: city,
                    visited: visited,
                    inProgress: inProgress,
                  ),
                ),
            ],

            const SizedBox(height: 8),
            _TrackingCard(controller: controller, palette: p),
            const SizedBox(height: 24),

            _SectionLabel(label: s.s('reward.badgesTitle'), palette: p),
            const SizedBox(height: 4),
            Text(
              s.s('reward.badgesSubtitle'),
              style: TextStyle(color: p.textMuted, fontSize: 12, height: 1.35),
            ),
            const SizedBox(height: 12),
            _BadgeShelf(earned: stats.badgesEarned.toSet(), palette: p),
          ],
        );
      },
    );
  }
}

/// Küçük harfli, harf aralığı geniş bölüm başlığı.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.palette});
  final String label;
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        color: palette.textMuted,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.4,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Rütbe kahramanı — madalyon + rütbe adı + XP ilerleme çubuğu.
// ---------------------------------------------------------------------------

class _RankHero extends StatelessWidget {
  const _RankHero({required this.stats, required this.palette});
  final UserStats stats;
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final s = LanguageScope.of(context);
    final level = xpToLevel(stats.xp);
    final tier = _tierForLevel(level.level);
    final rank = _kRanks[tier];
    final color = _rankColor(p, tier);
    final isMax = tier >= _kRanks.length - 1;
    final next = isMax ? null : _kRanks[tier + 1];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.16),
            color.withValues(alpha: 0.04),
            p.card,
          ],
        ),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _RankMedallion(kanji: rank.kanji, color: color),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      s.s('reward.rankTier').toUpperCase(),
                      style: TextStyle(
                        color: p.textMuted,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.3,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      rank.romaji,
                      style: TextStyle(
                        color: p.textPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        height: 1.05,
                      ),
                    ),
                    Text(
                      s.s('reward.rank.${rank.id}'),
                      style: TextStyle(
                        color: p.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${stats.xp}',
                    style: TextStyle(
                      color: color,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      height: 1,
                    ),
                  ),
                  Text(
                    'XP',
                    style: TextStyle(
                      color: p.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: isMax ? 1.0 : level.progress,
              minHeight: 8,
              backgroundColor: p.textMuted.withValues(alpha: 0.14),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  isMax
                      ? s.s('reward.maxRank')
                      : s.p('reward.toNextRank', {
                          'rank': next!.romaji,
                          'xp': '${level.nextThreshold}',
                        }),
                  style: TextStyle(
                    color: p.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (!isMax) ...[
                const SizedBox(width: 8),
                Text(
                  next!.kanji,
                  style: TextStyle(
                    color: _rankColor(p, tier + 1).withValues(alpha: 0.65),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Rütbe kanji'sini taşıyan yuvarlak, degrade madalyon.
class _RankMedallion extends StatelessWidget {
  const _RankMedallion({required this.kanji, required this.color});
  final String kanji;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 68,
      height: 68,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, Color.lerp(color, Colors.black, 0.22)!],
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        kanji,
        style: TextStyle(
          color: Colors.white,
          fontSize: kanji.runes.length > 1 ? 24 : 34,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Keşif metrik şeridi — Gezilen · Toplam · Şehir.
// ---------------------------------------------------------------------------

class _DiscoveryStats extends StatelessWidget {
  const _DiscoveryStats({
    required this.palette,
    required this.visited,
    required this.total,
    required this.cities,
  });
  final ViewerPalette palette;
  final int visited;
  final int total;
  final int cities;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final s = LanguageScope.of(context);
    final metrics = [
      (Icons.check_circle_outline, '$visited', s.s('reward.stat.visited'), p.matcha),
      (Icons.place_outlined, '$total', s.s('reward.stat.total'), p.accent),
      (Icons.apartment_outlined, '$cities', s.s('reward.stat.cities'), p.fuji),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.border),
      ),
      child: Row(
        children: [
          for (var i = 0; i < metrics.length; i++) ...[
            Expanded(
              child: Column(
                children: [
                  Icon(metrics[i].$1, color: metrics[i].$4, size: 20),
                  const SizedBox(height: 7),
                  Text(
                    metrics[i].$2,
                    style: TextStyle(
                      color: p.textPrimary,
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    metrics[i].$3,
                    style: TextStyle(
                      color: p.textSecondary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            if (i < metrics.length - 1)
              Container(width: 1, height: 44, color: p.border),
          ],
        ],
      ),
    );
  }
}

/// Konum takibi ipucu — pin ikonlu, sakin bilgi satırı.
class _IntroHint extends StatelessWidget {
  const _IntroHint({required this.palette, required this.text});
  final ViewerPalette palette;
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.sky.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.my_location_outlined, size: 16, color: p.sky),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text.replaceAll(' 📍', ''),
              style: TextStyle(
                color: p.textSecondary,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyCities extends StatelessWidget {
  const _EmptyCities({required this.palette});
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final s = LanguageScope.of(context);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.border),
      ),
      child: Column(
        children: [
          const Text('🧭', style: TextStyle(fontSize: 36)),
          const SizedBox(height: 10),
          Text(
            s.s('reward.noCities'),
            textAlign: TextAlign.center,
            style: TextStyle(color: p.textSecondary, fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Konum takibi kartı.
// ---------------------------------------------------------------------------

class _TrackingCard extends StatelessWidget {
  const _TrackingCard({required this.controller, required this.palette});
  final GeofenceController controller;
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final s = LanguageScope.of(context);
    final status = controller.status;
    final watching = controller.isTracking;

    final title = switch (status) {
      GeofencePermissionStatus.unsupported =>
        s.s('reward.tracking.unsupported'),
      GeofencePermissionStatus.denied => s.s('reward.tracking.denied'),
      GeofencePermissionStatus.deniedForever =>
        s.s('reward.tracking.deniedForever'),
      _ when watching => s.s('reward.tracking.on'),
      _ => s.s('reward.tracking.off'),
    };
    final active = watching &&
        status != GeofencePermissionStatus.denied &&
        status != GeofencePermissionStatus.deniedForever &&
        status != GeofencePermissionStatus.unsupported;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: (active ? p.matcha : p.textMuted)
                      .withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  active ? Icons.location_on : Icons.location_off_outlined,
                  size: 18,
                  color: active ? p.matcha : p.textMuted,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: p.textPrimary,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            s.s('reward.tracking.body'),
            style: TextStyle(color: p.textSecondary, fontSize: 12.5, height: 1.4),
          ),
          const SizedBox(height: 14),
          if (status == GeofencePermissionStatus.deniedForever)
            _TrackingButton(
              palette: p,
              label: s.s('reward.tracking.openSettings'),
              color: p.accent,
              onPressed: controller.openSettings,
            )
          else if (status != GeofencePermissionStatus.unsupported &&
              status != GeofencePermissionStatus.denied)
            _TrackingButton(
              palette: p,
              label: watching
                  ? s.s('reward.tracking.stop')
                  : s.s('reward.tracking.start'),
              color: watching ? p.sunset : p.matcha,
              onPressed: watching ? controller.stop : controller.start,
            ),
        ],
      ),
    );
  }
}

class _TrackingButton extends StatelessWidget {
  const _TrackingButton({
    required this.palette,
    required this.label,
    required this.color,
    required this.onPressed,
  });
  final ViewerPalette palette;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Aktivite rozetleri — pasif, sakin görünüm. Kazanılan renkli, kilitli soluk.
// ---------------------------------------------------------------------------

class _BadgeShelf extends StatelessWidget {
  const _BadgeShelf({required this.earned, required this.palette});
  final Set<String> earned;
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final s = LanguageScope.of(context);
    return Column(
      children: [
        for (final b in kBadgeDefinitions)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _BadgeRow(
              badge: b,
              unlocked: earned.contains(b.id),
              palette: p,
              s: s,
            ),
          ),
      ],
    );
  }
}

class _BadgeRow extends StatelessWidget {
  const _BadgeRow({
    required this.badge,
    required this.unlocked,
    required this.palette,
    required this.s,
  });
  final BadgeDefinition badge;
  final bool unlocked;
  final ViewerPalette palette;
  final LanguageScope s;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: unlocked ? p.card : p.card.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: unlocked ? p.gold.withValues(alpha: 0.28) : p.border,
        ),
      ),
      child: Row(
        children: [
          Opacity(
            opacity: unlocked ? 1 : 0.4,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: (unlocked ? p.gold : p.textMuted).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(badge.emoji, style: const TextStyle(fontSize: 18)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.s(badge.title),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: unlocked ? p.textPrimary : p.textSecondary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  unlocked ? s.s(badge.description) : s.s(badge.hint),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: p.textMuted,
                    fontSize: 11.5,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            unlocked ? Icons.check_circle : Icons.lock_outline_rounded,
            size: 18,
            color: unlocked ? p.matcha : p.textMuted.withValues(alpha: 0.6),
          ),
        ],
      ),
    );
  }
}
