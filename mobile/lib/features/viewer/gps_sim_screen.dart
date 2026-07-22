// GPS SİMÜLATÖRÜ (test/dev aracı) — gerçek GPS olmadan (preview/web dahil)
// keşif → rozet onay akışını denemek için sahte konum verisi besler.
//
// Aynı `geofenceControllerProvider(trip)` örneğini kullanır; böylece burada
// yapılan keşifler kalıcıdır ve keşif haritasında da yeşillenir.
//
// Nasıl çalışır: her fence için, fence merkezinde iki GeoSample itilir —
// biri `t` anında (oturum açılır), biri `t + minDwellSeconds + 1s` anında
// (dwell eşiği aşılır → engine tamamlar → +XP + rozet). Sim saati elle veya
// otomatik turla ilerletilir.

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

  void _advance(Duration d) => setState(() => _simClock = _simClock.add(d));

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(behavior: SnackBarBehavior.floating, content: Text(msg)),
    );
  }

  /// Fence konumuna anlık ışınlanma (tek örnek, current sim saatiyle).
  void _teleport(GeofenceController c, Geofence f) {
    c.debugPushSample(GeoSample(
      lat: f.lat,
      lng: f.lng,
      accuracy: 10,
      timestamp: _simClock,
    ));
    _snack(LanguageScope.of(context)
        .p('gps.snack.teleport', {'emoji': f.emoji, 'name': f.name}));
  }

  /// Fence'te 10 dk kal & onayla. Motor her örnek arası dwell artışını
  /// graceSeconds+60 ile sınırladığı için TEK büyük sıçrama yetmez —
  /// bu yüzden minDwellSeconds boyunca 120 sn'lik küçük adımlarla besleriz.
  void _dwellAndConfirm(GeofenceController c, Geofence f) {
    var t = _simClock;
    GeoSample sampleAt(DateTime ts) =>
        GeoSample(lat: f.lat, lng: f.lng, accuracy: 10, timestamp: ts);
    c.debugPushSample(sampleAt(t)); // oturum açılır
    const step = 120; // saniye — motorun 180 sn'lik delta sınırının altında
    var dwelled = 0;
    while (dwelled < f.minDwellSeconds + step) {
      t = t.add(const Duration(seconds: step));
      c.debugPushSample(sampleAt(t));
      dwelled += step;
    }
    setState(() => _simClock = t);
  }

  /// İlk ~6 fence'i sırayla tamamlayarak birden çok rozetin açılışını izletir.
  void _autoTour(GeofenceController c, List<Geofence> fences) {
    final targets = fences.take(6).toList();
    for (final f in targets) {
      if (c.visits.records[f.id]?.completedAt != null) continue;
      _dwellAndConfirm(c, f);
      // Sonraki durağa "yolculuk" için saati biraz ilerlet.
      _simClock = _simClock.add(const Duration(minutes: 5));
    }
    setState(() {});
    _snack(LanguageScope.of(context).s('gps.snack.autoTourDone'));
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
                                      _advance(const Duration(minutes: 1)),
                                  child: Text(s.s('gps.plus1min')),
                                ),
                                OutlinedButton(
                                  onPressed: () =>
                                      _advance(const Duration(minutes: 10)),
                                  child: Text(s.s('gps.plus10min')),
                                ),
                              ],
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
                          onGo: () => _teleport(controller, f),
                          onDwell: () => _dwellAndConfirm(controller, f),
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
    required this.onGo,
    required this.onDwell,
  });

  final Geofence fence;
  final bool discovered;
  final VoidCallback onGo;
  final VoidCallback onDwell;

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
                  OutlinedButton(
                    onPressed: onGo,
                    child: Text(s.s('gps.fence.goHere')),
                  ),
                  const SizedBox(height: 4),
                  FilledButton(
                    onPressed: onDwell,
                    child: Text(s.s('gps.fence.dwell')),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
