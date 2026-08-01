// Keşif haritası ekranı — "Gezgin rütbesi" (Japon efsane yaratıkları merdiveni)
// odaklı, XP tabanlı ve sade bir keşif yüzeyi. Üstte rütbe madalyonu + XP
// ilerleme, ardından keşif metrikleri, şehir kartları, konum takibi ve
// pasif görünümlü aktivite rozetleri.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  GeofenceController? _wired;
  int? _lastTier;

  /// Controller değiştiğinde rütbe-atlama dinleyicisini bağlar. İlk bağlamada
  /// mevcut rütbe referans alınır (açılışta kutlama tetiklenmez).
  void _wire(GeofenceController c) {
    if (identical(_wired, c)) return;
    _wired?.removeListener(_onTick);
    _wired = c;
    _lastTier = _tierForLevel(xpToLevel(c.stats.xp).level);
    c.addListener(_onTick);
  }

  void _onTick() {
    final c = _wired;
    if (c == null || !mounted) return;
    final tier = _tierForLevel(xpToLevel(c.stats.xp).level);
    if (_lastTier != null && tier > _lastTier!) {
      _celebrateRankUp(tier);
    }
    _lastTier = tier;
  }

  /// Ghibli esintili rütbe-atlama kutlaması: yumuşak ışık, süzülen toz
  /// zerreleri + parıltı ve nazikçe beliren madalyon. Haptik ile eşlenir.
  void _celebrateRankUp(int tier) {
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    final palette = ViewerPalette.of(context);
    final rank = _kRanks[tier.clamp(0, _kRanks.length - 1)];
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'rank-up',
      barrierColor: Colors.black.withValues(alpha: 0.5),
      transitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (_, __, ___) => _RankUpCelebration(
        palette: palette,
        rank: rank,
        color: _rankColor(palette, tier),
      ),
    );
  }

  @override
  void dispose() {
    _wired?.removeListener(_onTick);
    super.dispose();
  }

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
    if (controller != null) _wire(controller);

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
                      letterSpacing: -0.5,
                      fontFeatures: const [FontFeature.tabularFigures()],
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
                    fontFamily: 'NotoSansJPRank',
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
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
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
          fontFamily: 'NotoSansJPRank',
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
                      fontFeatures: const [FontFeature.tabularFigures()],
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
// Ghibli esintili rütbe-atlama kutlaması — yumuşak sıcak ışık, yukarı süzülen
// toz zerreleri (susuwatari) + altın parıltılar ve nazikçe beliren madalyon.
// ~2.8 sn sonra kendiliğinden yumuşakça kapanır.
// ---------------------------------------------------------------------------

class _RankUpCelebration extends StatefulWidget {
  const _RankUpCelebration({
    required this.palette,
    required this.rank,
    required this.color,
  });
  final ViewerPalette palette;
  final _RankInfo rank;
  final Color color;

  @override
  State<_RankUpCelebration> createState() => _RankUpCelebrationState();
}

class _RankUpCelebrationState extends State<_RankUpCelebration>
    with TickerProviderStateMixin {
  late final AnimationController _drift; // sürekli süzülen zerreler
  late final AnimationController _enter; // madalyon/metin girişi
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _drift = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
    // Kendiliğinden yumuşak kapanış.
    Future.delayed(const Duration(milliseconds: 2800), _dismiss);
  }

  void _dismiss() {
    if (_closing || !mounted) return;
    _closing = true;
    Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    _drift.dispose();
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final color = widget.color;

    return GestureDetector(
      onTap: _dismiss,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        children: [
          // Yumuşak sıcak ışık — merkezden yayılan Ghibli parıltısı.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.15),
                  radius: 0.9,
                  colors: [
                    color.withValues(alpha: 0.32),
                    color.withValues(alpha: 0.10),
                    Colors.transparent,
                  ],
                  stops: const [0, 0.45, 1],
                ),
              ),
            ),
          ),
          // Süzülen toz zerreleri + parıltılar.
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _drift,
              builder: (_, __) => CustomPaint(
                painter: _DustPainter(t: _drift.value, color: color),
              ),
            ),
          ),
          // Merkez içerik.
          Center(
            child: AnimatedBuilder(
              animation: _enter,
              builder: (_, child) {
                final e = Curves.easeOutBack.transform(
                  _enter.value.clamp(0.0, 1.0),
                );
                final fade = Curves.easeOut.transform(
                  _enter.value.clamp(0.0, 1.0),
                );
                return Opacity(
                  opacity: fade,
                  child: Transform.scale(scale: 0.7 + 0.3 * e, child: child),
                );
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _GlowMedallion(kanji: widget.rank.kanji, color: color),
                  const SizedBox(height: 20),
                  Text(
                    s.s('reward.rankUp.label'),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.rank.romaji,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    s.s('reward.rank.${widget.rank.id}'),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.82),
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 48),
                    child: Text(
                      s.s('reward.rankUp.body'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.62),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Kutlama madalyonu — dış ışık halesiyle beliren, kanji taşıyan yuvarlak.
class _GlowMedallion extends StatelessWidget {
  const _GlowMedallion({required this.kanji, required this.color});
  final String kanji;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 116,
      height: 116,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, Color.lerp(color, Colors.black, 0.24)!],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.30), width: 2),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.55),
            blurRadius: 40,
            spreadRadius: 4,
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        kanji,
        style: TextStyle(
          fontFamily: 'NotoSansJPRank',
          color: Colors.white,
          fontSize: kanji.runes.length > 1 ? 44 : 60,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}

/// Yukarı süzülen toz zerreleri (susuwatari) + altın parıltılar. Deterministik
/// tohumla üretilir; [t] 0..1 döngüsel zamandır.
class _DustPainter extends CustomPainter {
  _DustPainter({required this.t, required this.color});
  final double t;
  final Color color;

  static final _rng = math.Random(7);
  static final List<_Mote> _motes = List.generate(26, (i) {
    return _Mote(
      x: _rng.nextDouble(),
      phase: _rng.nextDouble(),
      speed: 0.4 + _rng.nextDouble() * 0.8,
      size: 1.5 + _rng.nextDouble() * 3.5,
      wobble: 6 + _rng.nextDouble() * 22,
      sparkle: _rng.nextDouble() > 0.62,
    );
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final m in _motes) {
      final prog = (t * m.speed + m.phase) % 1.0;
      // Aşağıdan yukarı süzülüş.
      final y = size.height * (1.05 - prog * 1.15);
      final wob = math.sin((prog * 2 * math.pi) + m.phase * 6) * m.wobble;
      final x = size.width * m.x + wob;
      // Girişte belirip çıkışta sönen yumuşak opaklık.
      final fade = math.sin(prog * math.pi).clamp(0.0, 1.0);

      if (m.sparkle) {
        final paint = Paint()
          ..color = color.withValues(alpha: 0.9 * fade)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2);
        _drawSparkle(canvas, Offset(x, y), m.size * 1.6, paint);
      } else {
        // Susuwatari — yumuşak koyu toz zerresi.
        final paint = Paint()
          ..color = Colors.black.withValues(alpha: 0.28 * fade)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);
        canvas.drawCircle(Offset(x, y), m.size, paint);
      }
    }
  }

  void _drawSparkle(Canvas canvas, Offset c, double r, Paint paint) {
    final path = Path();
    for (var i = 0; i < 4; i++) {
      final a = i * math.pi / 2;
      path.moveTo(c.dx, c.dy);
      path.lineTo(c.dx + math.cos(a) * r, c.dy + math.sin(a) * r);
    }
    canvas.drawPath(
      path,
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _DustPainter old) =>
      old.t != t || old.color != color;
}

class _Mote {
  const _Mote({
    required this.x,
    required this.phase,
    required this.speed,
    required this.size,
    required this.wobble,
    required this.sparkle,
  });
  final double x;
  final double phase;
  final double speed;
  final double size;
  final double wobble;
  final bool sparkle;
}

