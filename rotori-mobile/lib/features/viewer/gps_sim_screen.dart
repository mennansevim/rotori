// GPS SİMÜLATÖRÜ (test/dev aracı) — gerçek GPS olmadan (preview/web dahil)
// keşif → rozet onay akışını denemek için sahte konum verisi besler.
//
// Aynı `geofenceControllerProvider(trip)` örneğini kullanır; böylece burada
// yapılan keşifler kalıcıdır ve keşif haritasında da yeşillenir.
//
// Nasıl çalışır: "Buraya git" ile ilgili fence merkezine girilir ve dwell
// oturumu başlar. Simüle saat ilerletildikçe motor 120 sn adımlarla beslenir;
// 10 dakika eşiği geçilince keşif otomatik tamamlanır (+XP + rozet).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
import '../../domain/geofence.dart';
import '../../domain/types.dart';
import 'geofence_service.dart';

class GpsSimScreen extends ConsumerStatefulWidget {
  const GpsSimScreen({super.key, required this.trip});
  final Trip trip;

  @override
  ConsumerState<GpsSimScreen> createState() => _GpsSimScreenState();
}

class _GpsSimScreenState extends ConsumerState<GpsSimScreen> {
  // Simüle edilen saat — gerçek zamandan bağımsız ilerletilir.
  DateTime _simClock = DateTime.now();
  String? _activeFenceId;
  DateTime? _activeFenceEnteredAt;

  void _advance(GeofenceController c, Duration d) {
    final from = _simClock;
    final to = from.add(d);
    _feedActiveFenceDwell(c, from: from, to: to);
    setState(() => _simClock = to);
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(behavior: SnackBarBehavior.floating, content: Text(msg)),
    );
  }

  /// Fence konumuna anlık ışınlanma (tek örnek, current sim saatiyle).
  void _teleport(GeofenceController c, Geofence f, {bool silent = false}) {
    c.debugPushSample(GeoSample(
      lat: f.lat,
      lng: f.lng,
      accuracy: 10,
      timestamp: _simClock,
    ));
    setState(() {
      _activeFenceId = f.id;
      _activeFenceEnteredAt = _simClock;
    });
    if (!silent) {
      _snack(LanguageScope.of(context)
          .p('gps.snack.teleport', {'emoji': f.emoji, 'name': f.name}));
    }
  }

  void _feedActiveFenceDwell(
    GeofenceController c, {
    required DateTime from,
    required DateTime to,
  }) {
    final activeId = _activeFenceId;
    if (activeId == null) return;
    Geofence? f;
    for (final item in c.fences) {
      if (item.id == activeId) {
        f = item;
        break;
      }
    }
    if (f == null || c.visits.records[f.id]?.completedAt != null) {
      _activeFenceId = null;
      _activeFenceEnteredAt = null;
      return;
    }

    var cursor = from;
    while (cursor.isBefore(to)) {
      final next = cursor.add(const Duration(seconds: 120));
      final tick = next.isAfter(to) ? to : next;
      c.debugPushSample(GeoSample(
        lat: f.lat,
        lng: f.lng,
        accuracy: 10,
        timestamp: tick,
      ));
      cursor = tick;
    }

    if (c.visits.records[f.id]?.completedAt != null) {
      _activeFenceId = null;
      _activeFenceEnteredAt = null;
    }
  }

  /// İlk ~6 fence'i sırayla ziyaret eder; her durakta saat ilerledikçe keşif
  /// otomatik tamamlanır.
  void _autoTour(GeofenceController c, List<Geofence> fences) {
    final targets = fences.take(6).toList();
    for (final f in targets) {
      if (c.visits.records[f.id]?.completedAt != null) continue;
      _teleport(c, f, silent: true);
      _advance(c, const Duration(minutes: 11));
      // Sonraki durağa "yolculuk" için saati biraz ilerlet.
      _advance(c, const Duration(minutes: 5));
    }
    _snack(LanguageScope.of(context).s('gps.snack.autoTourDone'));
  }

  Geofence? _activeFence(GeofenceController c) {
    final id = _activeFenceId;
    if (id == null) return null;
    for (final f in c.fences) {
      if (f.id == id) return f;
    }
    return null;
  }

  int _activeElapsedMinutes() {
    final enteredAt = _activeFenceEnteredAt;
    if (enteredAt == null) return 0;
    final delta = _simClock.difference(enteredAt);
    return delta.inMinutes.clamp(0, 24 * 60);
  }

  String _fmtClock(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = LanguageScope.of(context);
    final controller = ref.watch(geofenceControllerProvider(widget.trip));

    return Scaffold(
      appBar: AppBar(title: Text(s.s('gps.title'))),
      body: controller == null
          ? const Center(child: CircularProgressIndicator())
          : ListenableBuilder(
              listenable: controller,
              builder: (context, _) {
                final fences = controller.fences;
                final visits = controller.visits;
                final stats = controller.stats;

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      s.s('gps.intro'),
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),

                    // Simüle saat + ilerletme
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                s.p('gps.simClock',
                                    {'time': _fmtClock(_simClock)}),
                                style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                OutlinedButton(
                                  onPressed: () =>
                                      _advance(controller, const Duration(minutes: 1)),
                                  child: Text(s.s('gps.plus1min')),
                                ),
                                OutlinedButton(
                                  onPressed: () =>
                                      _advance(controller, const Duration(minutes: 10)),
                                  child: Text(s.s('gps.plus10min')),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            _CurrentZoneChip(
                              activeFence: _activeFence(controller),
                              elapsedMinutes: _activeElapsedMinutes(),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Canlı okumalar
                    Row(
                      children: [
                        Expanded(
                          child: _Readout(
                            label: 'XP',
                            value: '${stats.xp}',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _Readout(
                            label: s.s('gps.readout.discoveries'),
                            value: '${stats.discoveredPlaceIds.length}',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _Readout(
                            label: s.s('gps.readout.badges'),
                            value: '${stats.badgesEarned.length}',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    FilledButton(
                      onPressed: () => _autoTour(controller, fences),
                      child: Text(s.s('gps.autoTour')),
                    ),
                    const SizedBox(height: 16),

                    if (fences.isEmpty)
                      Text(
                        s.s('gps.emptyFences'),
                        style: theme.textTheme.bodyMedium,
                      )
                    else
                      for (final f in fences)
                        _FenceRow(
                          fence: f,
                          discovered:
                              visits.records[f.id]?.completedAt != null,
                          isActive: _activeFenceId == f.id,
                          activeElapsedMinutes: _activeFenceId == f.id
                              ? _activeElapsedMinutes()
                              : 0,
                          onGo: () => _teleport(controller, f),
                        ),
                    const SizedBox(height: 24),
                  ],
                );
              },
            ),
    );
  }
}

class _Readout extends StatelessWidget {
  const _Readout({required this.label, required this.value});
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
            Text(value,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

class _FenceRow extends StatelessWidget {
  const _FenceRow({
    required this.fence,
    required this.discovered,
    required this.isActive,
    required this.activeElapsedMinutes,
    required this.onGo,
  });

  final Geofence fence;
  final bool discovered;
  final bool isActive;
  final int activeElapsedMinutes;
  final VoidCallback onGo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = LanguageScope.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Text(fence.emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(fence.name,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  Text('${fence.city} · +${fence.xp} XP',
                      style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (discovered)
              Text(s.s('gps.fence.discovered'),
                  style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700))
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (isActive)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        s.p('gps.fence.activeProgress', {
                          'mins': '$activeElapsedMinutes',
                        }),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  OutlinedButton(
                    onPressed: onGo,
                    child: Text(s.s('gps.fence.goHere')),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _CurrentZoneChip extends StatelessWidget {
  const _CurrentZoneChip({
    required this.activeFence,
    required this.elapsedMinutes,
  });

  final Geofence? activeFence;
  final int elapsedMinutes;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final theme = Theme.of(context);
    final active = activeFence != null;
    final label = active
        ? s.p('gps.currentZone.active', {
            'emoji': activeFence!.emoji,
            'name': activeFence!.name,
            'city': activeFence!.city,
            'mins': '$elapsedMinutes',
          })
        : s.s('gps.currentZone.none');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: active ? 0.08 : 0.04),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}
