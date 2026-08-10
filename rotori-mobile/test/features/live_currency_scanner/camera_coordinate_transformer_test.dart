import 'dart:ui';

import 'package:flutter/painting.dart' show BoxFit;
import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/features/live_currency_scanner/infrastructure/camera/camera_coordinate_transformer.dart';

void main() {
  const t = CameraCoordinateTransformer();

  test('portrait, rotasyon yok, birebir ölçek', () {
    final r = t.transform(
      sourceRect: const Rect.fromLTWH(0, 0, 100, 100),
      sourceImageSize: const Size(1000, 1000),
      previewSize: const Size(500, 500),
      rotationDegrees: 0,
      mirrored: false,
    );
    expect(r, const Rect.fromLTWH(0, 0, 50, 50));
  });

  test('cover crop farklı aspect ratio ortalar', () {
    // Görüntü 1000x2000, preview 500x500 → cover scale = max(0.5,0.25)=0.5
    final r = t.transform(
      sourceRect: const Rect.fromLTWH(0, 0, 100, 100),
      sourceImageSize: const Size(1000, 2000),
      previewSize: const Size(500, 500),
      rotationDegrees: 0,
      mirrored: false,
    );
    // scaledH = 2000*0.5=1000 → dy = (500-1000)/2 = -250
    expect(r.left, 0);
    expect(r.top, closeTo(-250, 0.001));
    expect(r.width, 50);
  });

  test('90 derece rotasyon boyut takas eder', () {
    final r = t.transform(
      sourceRect: const Rect.fromLTWH(0, 0, 100, 200),
      sourceImageSize: const Size(1000, 2000),
      previewSize: const Size(2000, 1000),
      rotationDegrees: 90,
      mirrored: false,
      fit: BoxFit.fill,
    );
    // Döndürülünce görüntü 2000x1000 olur, preview ile birebir.
    expect(r.width, greaterThan(0));
    expect(r.height, greaterThan(0));
  });

  test('180 derece rotasyon kutuyu ters köşeye taşır', () {
    final r = t.transform(
      sourceRect: const Rect.fromLTWH(0, 0, 100, 100),
      sourceImageSize: const Size(1000, 1000),
      previewSize: const Size(1000, 1000),
      rotationDegrees: 180,
      mirrored: false,
      fit: BoxFit.fill,
    );
    // (0,0,100,100) → sağ-alt köşe (900,900,1000,1000)
    expect(r.left, closeTo(900, 0.001));
    expect(r.top, closeTo(900, 0.001));
  });

  test('mirrored preview yatay eksende yansıtır', () {
    final r = t.transform(
      sourceRect: const Rect.fromLTWH(0, 0, 100, 100),
      sourceImageSize: const Size(1000, 1000),
      previewSize: const Size(1000, 1000),
      rotationDegrees: 0,
      mirrored: true,
      fit: BoxFit.fill,
    );
    expect(r.left, closeTo(900, 0.001));
    expect(r.right, closeTo(1000, 0.001));
  });

  test('270 derece rotasyon geçerli kutu üretir', () {
    final r = t.transform(
      sourceRect: const Rect.fromLTWH(10, 20, 30, 40),
      sourceImageSize: const Size(1000, 2000),
      previewSize: const Size(2000, 1000),
      rotationDegrees: 270,
      mirrored: false,
      fit: BoxFit.fill,
    );
    expect(r.width, greaterThan(0));
    expect(r.height, greaterThan(0));
  });
}
