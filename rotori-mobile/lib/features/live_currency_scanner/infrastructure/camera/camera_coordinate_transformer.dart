import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter/painting.dart' show BoxFit;

/// OCR görüntü koordinatlarını Flutter kamera preview koordinatlarına çevirir.
///
/// Saf Dart, durumsuz, birim testlenebilir. Rotation (0/90/180/270), ön/arka
/// kamera aynalaması ([mirrored]) ve [BoxFit.cover] kırpma offset'i hesaba
/// katılır. Koordinat dönüşümü UI'dan bağımsızdır.
class CameraCoordinateTransformer {
  const CameraCoordinateTransformer();

  Rect transform({
    required Rect sourceRect,
    required Size sourceImageSize,
    required Size previewSize,
    required int rotationDegrees,
    required bool mirrored,
    BoxFit fit = BoxFit.cover,
  }) {
    final rot = ((rotationDegrees % 360) + 360) % 360;

    // 1) Rotasyon: kutuyu ve görüntü boyutunu döndür.
    final rotated = _rotateRect(sourceRect, sourceImageSize, rot);
    final displayed = _rotatedSize(sourceImageSize, rot);

    // 2) Aynalama (yatay eksende, döndürülmüş görüntü genişliğine göre).
    var box = rotated;
    if (mirrored) {
      final left = displayed.width - box.right;
      box = Rect.fromLTWH(left, box.top, box.width, box.height);
    }

    // 3) BoxFit ölçekleme + ortalanmış kırpma offset'i.
    final sx = previewSize.width / displayed.width;
    final sy = previewSize.height / displayed.height;
    final scale = switch (fit) {
      BoxFit.cover => math.max(sx, sy),
      BoxFit.contain => math.min(sx, sy),
      BoxFit.fill => sx, // yalnız genişlik; y ayrı ölçeklenir
      _ => math.max(sx, sy),
    };

    if (fit == BoxFit.fill) {
      return Rect.fromLTRB(
        box.left * sx,
        box.top * sy,
        box.right * sx,
        box.bottom * sy,
      );
    }

    final scaledW = displayed.width * scale;
    final scaledH = displayed.height * scale;
    final dx = (previewSize.width - scaledW) / 2;
    final dy = (previewSize.height - scaledH) / 2;

    return Rect.fromLTWH(
      box.left * scale + dx,
      box.top * scale + dy,
      box.width * scale,
      box.height * scale,
    );
  }

  Size _rotatedSize(Size s, int rot) {
    if (rot == 90 || rot == 270) return Size(s.height, s.width);
    return s;
  }

  Rect _rotateRect(Rect r, Size s, int rot) {
    final corners = <Offset>[
      Offset(r.left, r.top),
      Offset(r.right, r.top),
      Offset(r.right, r.bottom),
      Offset(r.left, r.bottom),
    ];
    final mapped = corners.map((c) => _rotatePoint(c, s, rot)).toList();
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final p in mapped) {
      minX = math.min(minX, p.dx);
      minY = math.min(minY, p.dy);
      maxX = math.max(maxX, p.dx);
      maxY = math.max(maxY, p.dy);
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  Offset _rotatePoint(Offset p, Size s, int rot) {
    switch (rot) {
      case 90:
        // 90° saat yönü: (x,y) → (H - y, x), yeni boyut (H,W).
        return Offset(s.height - p.dy, p.dx);
      case 180:
        return Offset(s.width - p.dx, s.height - p.dy);
      case 270:
        return Offset(p.dy, s.width - p.dx);
      default:
        return p;
    }
  }
}
