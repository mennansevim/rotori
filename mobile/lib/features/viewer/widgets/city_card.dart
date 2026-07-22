// apps/viewer/src/components/RewardMap.tsx içindeki CityCard + plotPlaces portu.
// Şehir keşif kartı: başlık + ilerleme çubuğu, mini-kroki (CustomPaint) ve
// nokta listesi.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/l10n.dart';
import '../../../domain/city_places.dart';

/// React'taki SVG viewBox boyutları — projeksiyon bu mantıksal kutuda yapılır,
/// çizimde gerçek boyuta ölçeklenir.
const double _vbW = 320;
const double _vbH = 200;
const double _pad = 30;

class PlottedPlace {
  const PlottedPlace({required this.place, required this.x, required this.y});
  final CityPlace place;
  final double x;
  final double y;
}

/// Şehrin noktalarını lat/lng oranlarını koruyarak mini-kroki kutusuna
/// yerleştirir. (React: plotPlaces — k = cos(meanLat) boylam sıkışması,
/// bounding box ölçekleme, Y ekseni ters.)
List<PlottedPlace> plotPlaces(List<CityPlace> places) {
  if (places.isEmpty) return const [];
  final meanLat =
      places.map((p) => p.lat).reduce((a, b) => a + b) / places.length;
  final k = math.cos((meanLat * math.pi) / 180); // boylam sıkışması düzeltmesi
  final pts = places.map((p) => (px: p.lng * k, py: p.lat)).toList();
  final xs = pts.map((p) => p.px);
  final ys = pts.map((p) => p.py);
  final minX = xs.reduce(math.min);
  final maxX = xs.reduce(math.max);
  final minY = ys.reduce(math.min);
  final maxY = ys.reduce(math.max);
  final spanX = (maxX - minX) != 0 ? (maxX - minX) : 1e-6;
  final spanY = (maxY - minY) != 0 ? (maxY - minY) : 1e-6;
  const availW = _vbW - 2 * _pad;
  const availH = _vbH - 2 * _pad;
  final scale = math.min(availW / spanX, availH / spanY);
  final drawW = spanX * scale;
  final drawH = spanY * scale;
  final offX = _pad + (availW - drawW) / 2;
  final offY = _pad + (availH - drawH) / 2;
  return [
    for (var i = 0; i < places.length; i++)
      PlottedPlace(
        place: places[i],
        x: offX + (pts[i].px - minX) * scale,
        // Büyük enlem → yukarı (küçük y).
        y: offY + (maxY - pts[i].py) * scale,
      ),
  ];
}

class CityCard extends StatelessWidget {
  const CityCard({
    super.key,
    required this.city,
    required this.visited,
    required this.inProgress,
  });

  final CityData city;
  final Set<String> visited;
  final Set<String> inProgress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visitedCount = city.places.where((p) => visited.contains(p.id)).length;
    final pct = visitedCount / math.max(1, city.places.length);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Başlık + sayaç + ilerleme çubuğu
            Row(
              children: [
                Text(city.emoji, style: const TextStyle(fontSize: 24)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        city.label,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        LanguageScope.of(context).p('cityCard.visitedCount',
                            {'done': '$visitedCount', 'total': '${city.places.length}'}),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 72,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: pct,
                      minHeight: 8,
                      backgroundColor:
                          theme.colorScheme.onSurface.withValues(alpha: 0.08),
                      valueColor: const AlwaysStoppedAnimation(
                        Color(0xFF4ADE80),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Mini-kroki
            AspectRatio(
              aspectRatio: _vbW / _vbH,
              child: Semantics(
                label: '${city.label} keşif krokisi',
                child: CustomPaint(
                  painter: _CityMapPainter(
                    plotted: plotPlaces(city.places),
                    visited: visited,
                    inProgress: inProgress,
                    surface: theme.colorScheme.surface,
                    outline:
                        theme.colorScheme.onSurface.withValues(alpha: 0.10),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Nokta listesi
            for (final p in city.places) _PlaceRow(place: p, visited: visited, inProgress: inProgress),
          ],
        ),
      ),
    );
  }
}

class _PlaceRow extends StatelessWidget {
  const _PlaceRow({
    required this.place,
    required this.visited,
    required this.inProgress,
  });

  final CityPlace place;
  final Set<String> visited;
  final Set<String> inProgress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = LanguageScope.of(context);
    final lang = loc.lang;
    final isVisited = visited.contains(place.id);
    final isProgress = !isVisited && inProgress.contains(place.id);
    final statusColor = isVisited
        ? const Color(0xFF4ADE80)
        : isProgress
            ? const Color(0xFFFBBF24)
            : theme.colorScheme.onSurface.withValues(alpha: 0.55);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(isVisited ? '✅' : place.emoji,
              style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              place.name,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: isVisited ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          Text(
            isVisited
                ? loc.s('cityCard.visited')
                : isProgress
                    ? loc.s('cityCard.detecting')
                    : place.category.of(lang),
            style: theme.textTheme.bodySmall?.copyWith(color: statusColor),
          ),
        ],
      ),
    );
  }
}

class _CityMapPainter extends CustomPainter {
  _CityMapPainter({
    required this.plotted,
    required this.visited,
    required this.inProgress,
    required this.surface,
    required this.outline,
  });

  final List<PlottedPlace> plotted;
  final Set<String> visited;
  final Set<String> inProgress;
  final Color surface;
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / _vbW;
    final sy = size.height / _vbH;
    canvas.scale(sx, sy);

    // Arka plan (React: .city-map-bg — yuvarlatılmış dikdörtgen)
    final bgRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(4, 4, _vbW - 8, _vbH - 8),
      const Radius.circular(14),
    );
    canvas.drawRRect(
      bgRect,
      Paint()..color = Color.alphaBlend(outline, surface),
    );
    canvas.drawRRect(
      bgRect,
      Paint()
        ..color = outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    for (final pp in plotted) {
      final isVisited = visited.contains(pp.place.id);
      final isProgress = !isVisited && inProgress.contains(pp.place.id);
      final dotColor = isVisited
          ? const Color(0xFF16A34A)
          : isProgress
              ? const Color(0xFFB45309)
              : const Color(0xFF3F3F52);
      final haloColor = isVisited
          ? const Color(0x334ADE80)
          : isProgress
              ? const Color(0x33FBBF24)
              : const Color(0x22FFFFFF);

      final c = Offset(pp.x, pp.y);
      canvas.drawCircle(c, 13, Paint()..color = haloColor);
      canvas.drawCircle(c, 9, Paint()..color = dotColor);

      final tp = TextPainter(
        text: TextSpan(
          text: isVisited ? '✓' : pp.place.emoji,
          style: const TextStyle(fontSize: 10, color: Color(0xFFFFFFFF)),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _CityMapPainter old) =>
      old.plotted != plotted ||
      old.visited != visited ||
      old.inProgress != inProgress;
}
