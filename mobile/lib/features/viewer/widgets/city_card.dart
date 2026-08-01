// Şehir keşif kartı — başlık + ilerleme, sade mini-kroki (CustomPaint) ve
// okunaklı nokta listesi. Gezilmemiş noktalar pasif (soluk) görünür; gezilen
// yeşil onay, tespit sürüyor ise amber olur. Renkler ViewerPalette'ten gelir.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/l10n.dart';
import '../../../domain/city_places.dart';
import '../viewer_theme.dart';

/// Mini-kroki mantıksal viewBox boyutları; çizimde gerçek boyuta ölçeklenir.
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
/// yerleştirir (k = cos(meanLat) boylam sıkışması, bounding box ölçekleme,
/// Y ekseni ters).
List<PlottedPlace> plotPlaces(List<CityPlace> places) {
  if (places.isEmpty) return const [];
  final meanLat =
      places.map((p) => p.lat).reduce((a, b) => a + b) / places.length;
  final k = math.cos((meanLat * math.pi) / 180);
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
    final p = ViewerPalette.of(context);
    final s = LanguageScope.of(context);
    final visitedCount =
        city.places.where((pl) => visited.contains(pl.id)).length;
    final total = city.places.length;
    final pct = visitedCount / math.max(1, total);
    final complete = visitedCount == total && total > 0;

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
          // Başlık + sayaç + yüzde rozeti
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: p.accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(city.emoji, style: const TextStyle(fontSize: 20)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      city.label,
                      style: TextStyle(
                        color: p.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      s.p('cityCard.visitedCount',
                          {'done': '$visitedCount', 'total': '$total'}),
                      style: TextStyle(color: p.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: (complete ? p.matcha : p.textMuted)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${(pct * 100).round()}%',
                  style: TextStyle(
                    color: complete ? p.matcha : p.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // İlerleme çubuğu — ince, sakin.
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 6,
              backgroundColor: p.textMuted.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation(p.matcha),
            ),
          ),
          const SizedBox(height: 14),

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
                  bg: p.bg,
                  outline: p.border,
                  visitedColor: p.matcha,
                  progressColor: p.gold,
                  mutedColor: p.textMuted,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Nokta listesi
          for (var i = 0; i < city.places.length; i++) ...[
            if (i > 0)
              Divider(color: p.border, height: 1),
            _PlaceRow(
              place: city.places[i],
              visited: visited,
              inProgress: inProgress,
              palette: p,
            ),
          ],
        ],
      ),
    );
  }
}

class _PlaceRow extends StatelessWidget {
  const _PlaceRow({
    required this.place,
    required this.visited,
    required this.inProgress,
    required this.palette,
  });

  final CityPlace place;
  final Set<String> visited;
  final Set<String> inProgress;
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final loc = LanguageScope.of(context);
    final lang = loc.lang;
    final isVisited = visited.contains(place.id);
    final isProgress = !isVisited && inProgress.contains(place.id);
    final statusColor = isVisited
        ? p.matcha
        : isProgress
            ? p.gold
            : p.textMuted;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          // Durum noktası — gezilmemiş pasif (içi boş), gezilen dolu onay.
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: isVisited
                  ? p.matcha.withValues(alpha: 0.14)
                  : Colors.transparent,
              shape: BoxShape.circle,
              border: Border.all(
                color: isVisited
                    ? p.matcha
                    : statusColor.withValues(alpha: 0.35),
                width: 1.4,
              ),
            ),
            alignment: Alignment.center,
            child: isVisited
                ? Icon(Icons.check, size: 14, color: p.matcha)
                : Text(place.emoji, style: const TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              place.name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isVisited ? p.textPrimary : p.textSecondary,
                fontSize: 14,
                fontWeight: isVisited ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            isVisited
                ? loc.s('cityCard.visited')
                : isProgress
                    ? loc.s('cityCard.detecting')
                    : place.category.of(lang),
            style: TextStyle(
              color: isVisited || isProgress ? statusColor : p.textMuted,
              fontSize: 11.5,
              fontWeight:
                  isVisited || isProgress ? FontWeight.w600 : FontWeight.w400,
            ),
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
    required this.bg,
    required this.outline,
    required this.visitedColor,
    required this.progressColor,
    required this.mutedColor,
  });

  final List<PlottedPlace> plotted;
  final Set<String> visited;
  final Set<String> inProgress;
  final Color bg;
  final Color outline;
  final Color visitedColor;
  final Color progressColor;
  final Color mutedColor;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / _vbW;
    final sy = size.height / _vbH;
    canvas.scale(sx, sy);

    final bgRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(4, 4, _vbW - 8, _vbH - 8),
      const Radius.circular(16),
    );
    canvas.drawRRect(bgRect, Paint()..color = bg);
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
          ? visitedColor
          : isProgress
              ? progressColor
              : mutedColor.withValues(alpha: 0.45);
      final haloColor = isVisited
          ? visitedColor.withValues(alpha: 0.22)
          : isProgress
              ? progressColor.withValues(alpha: 0.22)
              : mutedColor.withValues(alpha: 0.10);

      final c = Offset(pp.x, pp.y);
      canvas.drawCircle(c, 13, Paint()..color = haloColor);
      canvas.drawCircle(c, 9, Paint()..color = dotColor);

      // Gezilmiş noktalar onay işaretiyle vurgulanır; diğerleri sade kalır.
      if (isVisited) {
        final tp = TextPainter(
          text: const TextSpan(
            text: '✓',
            style: TextStyle(
              fontSize: 11,
              color: Color(0xFFFFFFFF),
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CityMapPainter old) =>
      old.plotted != plotted ||
      old.visited != visited ||
      old.inProgress != inProgress ||
      old.bg != bg;
}
