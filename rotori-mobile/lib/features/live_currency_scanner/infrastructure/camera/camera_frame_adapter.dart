import 'package:camera/camera.dart';

import '../ocr/on_device_text_recognizer.dart';

/// `camera` paketinin [CameraImage] nesnesini saf [CameraImageInput] modeline
/// çevirir. `camera` paketi çapraz platformdur (mobil + web) — bu adapter web
/// grafiğine ML Kit sızdırmaz.
class CameraFrameAdapter {
  const CameraFrameAdapter();

  CameraImageInput fromCameraImage(
    CameraImage image, {
    required int rotationDegrees,
  }) {
    final planes = image.planes
        .map((p) => CameraPlaneInput(
              bytes: p.bytes,
              bytesPerRow: p.bytesPerRow,
            ))
        .toList();
    return CameraImageInput(
      width: image.width,
      height: image.height,
      rotationDegrees: rotationDegrees,
      rawFormat: image.format.raw is int ? image.format.raw as int : 0,
      planes: planes,
      bytesPerRow: image.planes.isNotEmpty ? image.planes.first.bytesPerRow : 0,
    );
  }
}
