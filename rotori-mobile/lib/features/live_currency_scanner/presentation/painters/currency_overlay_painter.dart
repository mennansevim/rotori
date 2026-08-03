import 'package:flutter/material.dart';

/// Ortadaki isteğe bağlı tarama alanını çizen hafif painter. Kamerayı
/// kapatmayan ince köşe çentikleri — Apple-kalite sade görünüm.
class CurrencyOverlayPainter extends CustomPainter {
  const CurrencyOverlayPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rect = Rect.fromCenter(
      center: Offset(w / 2, h / 2),
      width: w * 0.78,
      height: h * 0.28,
    );
    final paint = Paint()
      ..color = color.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    const corner = 26.0;
    // Dört köşe çentiği.
    void drawCorner(Offset o, Offset hDir, Offset vDir) {
      canvas.drawLine(o, o + hDir, paint);
      canvas.drawLine(o, o + vDir, paint);
    }

    drawCorner(rect.topLeft, const Offset(corner, 0), const Offset(0, corner));
    drawCorner(
        rect.topRight, const Offset(-corner, 0), const Offset(0, corner));
    drawCorner(
        rect.bottomLeft, const Offset(corner, 0), const Offset(0, -corner));
    drawCorner(
        rect.bottomRight, const Offset(-corner, 0), const Offset(0, -corner));
  }

  @override
  bool shouldRepaint(CurrencyOverlayPainter oldDelegate) =>
      oldDelegate.color != color;
}
