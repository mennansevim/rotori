// apps/viewer/src/components/RewardMap.tsx + RewardsBadge.tsx portu.
// Keşif haritası ekranı: rozet çipi, XP/level çubuğu, şehir keşif kartları,
// konum takibi bölümü ve aktivite rozetleri.

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

    return Scaffold(
      appBar: AppBar(
        title: Text(s.s('reward.title')),
        actions: [
          IconButton(
            tooltip: s.s('reward.gpsSimTooltip'),
            icon: const Text('🧪', style: TextStyle(fontSize: 20)),
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
        final theme = Theme.of(context);
        final s = LanguageScope.of(context);
        final routeCities = detectTripCities(trip);
        final visits = controller.visits;
        final stats = controller.stats;

        // Gezildi durumu GPS ile belirlenir: 10 dk+ kalınca otomatik tamamlanır.
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
            allPlaces.where((p) => visited.contains(p.id)).length;
        final level = xpToLevel(stats.xp);

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Başlık + rozet çipi
            Row(
              children: [
                const Text('🗺️', style: TextStyle(fontSize: 32)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.s('reward.title'),
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        s.p('reward.summary', {
                          'cities': '${routeCities.length}',
                          'visited': '$visitedCount',
                          'total': '${allPlaces.length}',
                          'level': '${level.level}',
                        }),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _RewardsChip(stats: stats),
            const SizedBox(height: 16),

            // XP / level çubuğu
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: level.progress,
                minHeight: 10,
                backgroundColor:
                    theme.colorScheme.onSurface.withValues(alpha: 0.08),
                valueColor:
                    AlwaysStoppedAnimation(theme.colorScheme.primary),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  s.p('reward.level', {'n': '${level.level}'}),
                  style: theme.textTheme.bodySmall,
                ),
                Text(
                  s.p('reward.xpToNext', {'xp': '${level.nextThreshold}'}),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Şehir kartları
            if (routeCities.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      const Text('🧭', style: TextStyle(fontSize: 36)),
                      const SizedBox(height: 8),
                      Text(
                        s.s('reward.noCities'),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              Text(
                s.s('reward.cityIntro'),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
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

            // Özet istatistikler
            Row(
              children: [
                Expanded(
                  child: _StatBox(
                    label: s.s('reward.stat.visited'),
                    value: s.p('reward.stat.pointsValue', {'n': '$visitedCount'}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatBox(
                    label: s.s('reward.stat.total'),
                    value: s.p(
                      'reward.stat.pointsValue',
                      {'n': '${allPlaces.length}'},
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatBox(
                    label: s.s('reward.stat.cities'),
                    value: '${routeCities.length}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            _TrackingCard(controller: controller),
            const SizedBox(height: 20),

            // Aktivite rozetleri
            Text(
              s.s('reward.badgesTitle'),
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              s.s('reward.badgesSubtitle'),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            _BadgeGrid(earned: stats.badgesEarned.toSet()),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }
}

/// React RewardsBadge portu — Level + XP + rozet sayısı çipi.
class _RewardsChip extends StatelessWidget {
  const _RewardsChip({required this.stats});
  final UserStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = LanguageScope.of(context);
    final level = xpToLevel(stats.xp);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.12),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🏆', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              s.p('reward.chip', {
                'level': '${level.level}',
                'xp': '${stats.xp}',
                'earned': '${stats.badgesEarned.length}',
                'total': '${kBadgeDefinitions.length}',
              }),
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          children: [
            Text(label, style: theme.textTheme.bodySmall),
            const SizedBox(height: 2),
            Text(
              value,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrackingCard extends StatelessWidget {
  const _TrackingCard({required this.controller});
  final GeofenceController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              s.s('reward.tracking.body'),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (status == GeofencePermissionStatus.deniedForever)
              FilledButton(
                onPressed: controller.openSettings,
                child: Text(s.s('reward.tracking.openSettings')),
              )
            else if (status != GeofencePermissionStatus.unsupported &&
                status != GeofencePermissionStatus.denied)
              FilledButton(
                onPressed: watching ? controller.stop : controller.start,
                child: Text(
                  watching
                      ? s.s('reward.tracking.stop')
                      : s.s('reward.tracking.start'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BadgeGrid extends StatelessWidget {
  const _BadgeGrid({required this.earned});
  final Set<String> earned;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = LanguageScope.of(context);
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.35,
      children: [
        for (final b in kBadgeDefinitions)
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Opacity(
                    opacity: earned.contains(b.id) ? 1 : 0.45,
                    child: Text(b.emoji, style: const TextStyle(fontSize: 22)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    s.s(b.title),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Expanded(
                    child: Text(
                      earned.contains(b.id)
                          ? s.s(b.description)
                          : s.s(b.hint),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  if (!earned.contains(b.id))
                    Text(
                      s.s('reward.locked'),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
