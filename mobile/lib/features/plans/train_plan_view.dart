// Planı "yukarıdan çekilmiş shinkansen" gibi gösteren üst-görünüm (top-down)
// tasarım. Her gün bir vagon; ardışık aynı şehir günleri aynı renkte olduğu
// için tek bir tren gövdesi gibi görünür. İlk vagon burun (lokomotif), son
// vagon kuyruk şeklinde çizilir. Yalnızca gezi ≥ 5 gün olduğunda kullanılır.
//
// Renkler `cityColorFor` ile şehir bazında atanır — her şehir farklı renk.

import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../viewer/viewer_theme.dart';

/// Tek bir vagonun (günün) çizim verisi.
class TrainCarData {
  const TrainCarData({
    required this.date,
    required this.dayNumber,
    required this.weekdayShort,
    required this.dayOfMonth,
    required this.city,
    required this.subtitle,
    required this.color,
    required this.isPast,
    required this.isActive,
  });

  /// YYYY-MM-DD — tıklamada ilgili güne kaydırmak için.
  final String date;
  final int dayNumber;
  final String weekdayShort;

  /// Ayın günü (ör. "25") — sağ panelde büyük gösterilir.
  final String dayOfMonth;
  final String city;

  /// Gün teması / alt etiket (ör. "yerleşik", "Shin-Osaka").
  final String subtitle;
  final Color color;
  final bool isPast;
  final bool isActive;
}

/// Vagonları dikey dizip tren görünümü üreten ana widget.
class TrainPlanView extends StatelessWidget {
  const TrainPlanView({
    super.key,
    required this.cars,
    required this.palette,
    required this.onTapCar,
  });

  final List<TrainCarData> cars;
  final ViewerPalette palette;
  final void Function(String date) onTapCar;

  @override
  Widget build(BuildContext context) {
    if (cars.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < cars.length; i++)
          _TrainCarRow(
            car: cars[i],
            palette: palette,
            isFirst: i == 0,
            isLast: i == cars.length - 1,
            // Ardışık aynı renk → aynı gövde; farklıysa üstte kupling boşluğu.
            newSegmentAbove: i == 0 ||
                cars[i - 1].color.toARGB32() != cars[i].color.toARGB32(),
            newSegmentBelow: i == cars.length - 1 ||
                cars[i + 1].color.toARGB32() != cars[i].color.toARGB32(),
            onTap: () => onTapCar(cars[i].date),
          ),
      ],
    );
  }
}

class _TrainCarRow extends StatelessWidget {
  const _TrainCarRow({
    required this.car,
    required this.palette,
    required this.isFirst,
    required this.isLast,
    required this.newSegmentAbove,
    required this.newSegmentBelow,
    required this.onTap,
  });

  final TrainCarData car;
  final ViewerPalette palette;
  final bool isFirst;
  final bool isLast;
  final bool newSegmentAbove;
  final bool newSegmentBelow;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final height = isFirst ? 128.0 : (isLast ? 116.0 : 100.0);
    final row = SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Sol: tren vagonu (top-down çizim + gün no/weekday).
          SizedBox(
            width: 116,
            child: CustomPaint(
              painter: _CarPainter(
                color: car.color,
                isFirst: isFirst,
                isLast: isLast,
                capTop: newSegmentAbove,
                capBottom: newSegmentBelow,
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (isFirst) const SizedBox(height: 26),
                    Text(
                      '${car.dayNumber}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 30,
                        height: 1,
                        shadows: [
                          Shadow(color: Colors.black38, blurRadius: 4),
                        ],
                      ),
                    ),
                    if (car.weekdayShort.isNotEmpty)
                      Text(
                        car.weekdayShort,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Sağ: koyu bilgi paneli (ayın günü + şehir + tema).
          Expanded(child: _InfoPanel(car: car, palette: palette)),
        ],
      ),
    );

    return Opacity(
      opacity: car.isPast ? 0.55 : 1,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: row,
        ),
      ),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.car, required this.palette});
  final TrainCarData car;
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
      decoration: BoxDecoration(
        color: car.isActive ? p.cardHover : p.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: car.isActive ? car.color.withValues(alpha: 0.65) : p.border,
          width: car.isActive ? 1.5 : 1,
        ),
        boxShadow: car.isActive
            ? [
                BoxShadow(
                  color: car.color.withValues(alpha: 0.28),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            car.dayOfMonth,
            style: TextStyle(
              color: p.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 22,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: car.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  car.city,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: p.textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          if (car.subtitle.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              car.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: p.textMuted,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Tek bir vagonu üstten görünümle (silindirik gövde + burun/kuyruk) çizer.
class _CarPainter extends CustomPainter {
  _CarPainter({
    required this.color,
    required this.isFirst,
    required this.isLast,
    required this.capTop,
    required this.capBottom,
  });

  final Color color;
  final bool isFirst;
  final bool isLast;

  /// Üstte yeni bir segment (şehir) başlıyor → üst kenarı yuvarla/burun yap.
  final bool capTop;

  /// Altta segment bitiyor → alt kenarı yuvarla/kuyruk yap.
  final bool capBottom;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 8.0;
    const left = inset;
    final right = size.width - inset;
    final bodyW = right - left;

    // Burun/kuyruk yarıçapları — segment sınırında büyük (yuvarlak), aksi
    // halde ufak (vagonlar birleşik görünür).
    final topR = isFirst
        ? bodyW * 0.5
        : (capTop ? 22.0 : 6.0);
    final botR = isLast
        ? bodyW * 0.42
        : (capBottom ? 22.0 : 6.0);

    final top = isFirst ? 10.0 : 0.0;
    final bottom = isLast ? size.height - 6.0 : size.height;

    final rrect = RRect.fromLTRBAndCorners(
      left,
      top,
      right,
      bottom,
      topLeft: Radius.circular(topR.clamp(0, bodyW / 2)),
      topRight: Radius.circular(topR.clamp(0, bodyW / 2)),
      bottomLeft: Radius.circular(botR.clamp(0, bodyW / 2)),
      bottomRight: Radius.circular(botR.clamp(0, bodyW / 2)),
    );

    // Gölge (zemine düşen) — hafif.
    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawRRect(rrect.shift(const Offset(0, 3)), shadow);

    // Silindirik gövde: yatay gradient (kenarlar koyu, merkez parlak) → üstten
    // yuvarlak metal gövdenin ışık yansıması hissi.
    final hsl = HSLColor.fromColor(color);
    final edge = hsl.withLightness((hsl.lightness * 0.62).clamp(0.0, 1.0)).toColor();
    final mid = color;
    final shine = hsl
        .withLightness((hsl.lightness + 0.28).clamp(0.0, 1.0))
        .withSaturation((hsl.saturation * 0.7).clamp(0.0, 1.0))
        .toColor();

    final body = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [edge, mid, shine, mid, edge],
        stops: const [0.0, 0.22, 0.5, 0.78, 1.0],
      ).createShader(Rect.fromLTRB(left, top, right, bottom));
    canvas.drawRRect(rrect, body);

    // Üst boylamsal parlak çizgi (spine highlight) — tepeden ışık.
    final spine = Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..style = PaintingStyle.fill;
    final cx = (left + right) / 2;
    canvas.drawRRect(
      RRect.fromLTRBR(cx - 6, top + 8, cx + 6, bottom - 8, const Radius.circular(6)),
      spine,
    );

    // Camlar (koyu). İlk vagonda çift kokpit, diğerlerinde tek şerit.
    final glass = Paint()..color = const Color(0xFF0B1220).withValues(alpha: 0.9);
    if (isFirst) {
      final wy = top + topR * 0.55;
      final ww = bodyW * 0.22;
      final gap = bodyW * 0.08;
      final r1 = Rect.fromLTWH(cx - gap / 2 - ww, wy, ww, 18);
      final r2 = Rect.fromLTWH(cx + gap / 2, wy, ww, 18);
      canvas.drawRRect(
          RRect.fromRectAndRadius(r1, const Radius.circular(6)), glass);
      canvas.drawRRect(
          RRect.fromRectAndRadius(r2, const Radius.circular(6)), glass);
    } else {
      final ww = bodyW * 0.5;
      final strip = Rect.fromLTWH(cx - ww / 2, top + 8, ww, 14);
      canvas.drawRRect(
          RRect.fromRectAndRadius(strip, const Radius.circular(5)), glass);
    }

    // Kupling (bağlantı) — segment ortasındayken alt/üstte koyu tampon.
    final coupler = Paint()..color = const Color(0xFF111827);
    final couplerW = bodyW * 0.30;
    if (!isLast && !capBottom) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(cx - couplerW / 2, bottom - 4, couplerW, 8),
          const Radius.circular(3),
        ),
        coupler,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CarPainter old) =>
      old.color != color ||
      old.isFirst != isFirst ||
      old.isLast != isLast ||
      old.capTop != capTop ||
      old.capBottom != capBottom;
}

/// Yardımcı: dil bazlı kısa hafta günü (viewer badge ile aynı mantık).
String trainWeekdayShort(AppLang lang, DateTime? d, String? weekdayHint) {
  final wd = (lang == AppLang.tr && (weekdayHint?.isNotEmpty ?? false))
      ? weekdayHint!
      : (d != null ? L10n.weekdaysFor(lang)[d.weekday] : '');
  if (wd.isEmpty) return '';
  return wd.length > 3 ? wd.substring(0, 3) : wd;
}
