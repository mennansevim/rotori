import 'dart:typed_data';
import 'dart:ui' show Rect, Size;

/// Platformdan bağımsız kamera karesi girdisi (saf veri).
///
/// Controller, `camera` paketinin `CameraImage` nesnesini bu saf modele
/// çevirir; böylece OCR recognizer'ı `camera` paketine bağımlı olmaz ve
/// arayüz test edilebilir kalır.
class CameraImageInput {
  const CameraImageInput({
    required this.width,
    required this.height,
    required this.rotationDegrees,
    required this.rawFormat,
    required this.planes,
    required this.bytesPerRow,
  });

  final int width;
  final int height;

  /// Sensör → ekran rotasyonu (0/90/180/270).
  final int rotationDegrees;

  /// Platform görüntü format kodu (iOS bgra8888 / Android yuv420 vb).
  final int rawFormat;

  final List<CameraPlaneInput> planes;

  /// İlk düzlemin satır uzunluğu (byte).
  final int bytesPerRow;

  Size get imageSize => Size(width.toDouble(), height.toDouble());
}

class CameraPlaneInput {
  const CameraPlaneInput({required this.bytes, required this.bytesPerRow});
  final Uint8List bytes;
  final int bytesPerRow;
}

/// OCR'ın tanıdığı tek bir metin satırı — ham metin + görüntü-koordinat kutusu.
class RecognizedTextLine {
  const RecognizedTextLine({
    required this.text,
    required this.boundingBox,
    this.confidence = 1.0,
  });

  final String text;
  final Rect boundingBox;
  final double confidence;
}

/// Bir karenin OCR sonucu — satırlar + kaynağın görüntü boyutu/rotasyonu.
class RecognizedFrame {
  const RecognizedFrame({
    required this.lines,
    required this.imageSize,
    required this.rotationDegrees,
  });

  final List<RecognizedTextLine> lines;
  final Size imageSize;
  final int rotationDegrees;

  static const empty = RecognizedFrame(
    lines: [],
    imageSize: Size.zero,
    rotationDegrees: 0,
  );
}

/// Cihaz üstü metin tanıma sözleşmesi. OCR paketi ileride değiştirilebilir.
abstract interface class OnDeviceTextRecognizer {
  Future<RecognizedFrame> recognize(CameraImageInput frame);
  Future<void> dispose();
}
